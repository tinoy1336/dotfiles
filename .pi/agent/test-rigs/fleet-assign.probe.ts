// Runnable probe for the `assign` reuse decision, driven through the REAL fleet
// tool: a fixture crew, a fixture run-record root and a fake pi whose event bus
// answers the owner's RPC — all of it under a scratch HOME, so the live roster,
// mode files and claims are never read or written.
//
// What it pins, one scenario each:
//   absent      no run record at all -> assign reaches the resume attempt (it is
//               NOT refused as unverifiable); a `no persisted session` answer from
//               the owner marks the worker `not-resumable`
//   gone-bus    the same absence with no owner listening -> the resume failure is
//               reported as transient and the worker's state is left unchanged
//   unreadable  a status.json that exists and cannot be parsed -> the refusal
//               stays, and names the unreadable-record case
//   no-stamp    a row with no activity stamp -> the refusal stays, and names that
//               case rather than the absent record
//   no-id       a worker with no run id -> the refusal names the unresolvable
//               identity instead of aiming a resume at null
//   live        a running row -> steer, do not resume
//   warm        a settled row inside the reuse window -> the warm resume proceeds
//
// Every scenario but `no-id` runs with the worker's identity claim held by THIS
// process, which is what a warm worker looks like to the gone-run pass
// (`identity.identityClaimLive`): without it the pass releases the claim as
// provably gone and the roster row is `retired` before the resume is even tried.

// jiti is the loader because `fleet/index.ts` imports `fleet/board.ts`, which
// imports the rpiv-todo package's TypeScript; plain type-stripping refuses those.
// The loader is resolved through the extensions directory, because this rig lives
// outside the tree that holds the node_modules link. Run:
//   node ~/.pi/agent/test-rigs/fleet-assign.probe.ts
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import { join } from "node:path"

const AGENT_DIR = `${process.env.HOME}/.pi/agent`
const require = createRequire(`${AGENT_DIR}/extensions/`)
const { createJiti } = require("jiti") as { createJiti: (url: string) => { import: (p: string) => Promise<never> } }

const WORKER = "alice"
const SCOPE = "probe-scope"
const SESSION = "probe-session"
const OLD_RUN = "run-probe-0001"
const NEW_RUN = "run-probe-0002"

const scratch = mkdtempSync(join(tmpdir(), "fleet-assign-probe-"))
const HOME = join(scratch, "home")
const TEMP_ROOT = join(scratch, "subagents")
const ROSTER_DIR = join(HOME, ".local/pi/foreman/roster")
const RUNTIME_DIR = join(HOME, ".local/pi/foreman/io/runtime")
// The real fleet directory's one config file, under the scratch agent dir: without
// a readable `reuseWindowSeconds` every settled worker measures as outside the
// window (`status.loadWindowMs` returns 0) and the warm scenario could not run.
const FLEET_CONFIG_DIR = join(HOME, ".pi/agent/extensions/fleet")
// Read when `fleet/roster.ts`, `fleet/mode.ts` and `fleet/status.ts` load, so it
// must be in place before any of them is imported.
process.env.HOME = HOME
process.env.PI_CODING_AGENT_DIR = join(HOME, ".pi/agent")
process.env.PI_SUBAGENTS_TEMP_ROOT = TEMP_ROOT
mkdirSync(FLEET_CONFIG_DIR, { recursive: true })
writeFileSync(join(FLEET_CONFIG_DIR, "config.json"), JSON.stringify({ reuseWindowSeconds: 3600 }))

const jiti = createJiti(`${AGENT_DIR}/test-rigs/`)
const roster = await jiti.import(`${AGENT_DIR}/extensions/fleet/roster.ts`)
const mode = await jiti.import(`${AGENT_DIR}/extensions/fleet/mode.ts`)
const identity = await jiti.import(`${AGENT_DIR}/extensions/io-guard/identity.ts`) as { procStartTime: (pid: number) => string | null }

// ── the fake pi ──────────────────────────────────────────────────────────────
type Reply = { ok: boolean; data?: unknown; error?: { code?: string; message?: string } }
type Responder = (call: { method: string; params: Record<string, unknown> }) => Reply | undefined

let responder: Responder = () => undefined
const listeners = new Map<string, Array<(payload: unknown) => void>>()
const tools = new Map<string, { execute: (...args: unknown[]) => Promise<unknown> }>()

const events = {
	on(name: string, cb: (payload: unknown) => void): void {
		listeners.set(name, [...(listeners.get(name) ?? []), cb])
	},
	emit(name: string, payload: unknown): void {
		if (name !== "subagents:rpc:v1:request") {
			for (const cb of listeners.get(name) ?? []) cb(payload)
			return
		}
		const call = payload as { requestId: string; method: string; params: Record<string, unknown> }
		const answer = responder({ method: call.method, params: call.params })
		// No answer = no listener in this session, which is what the extension reads
		// as an absent owner.
		if (answer === undefined) return
		const reply = { success: answer.ok, data: answer.data, error: answer.error }
		for (const cb of listeners.get(`subagents:rpc:v1:reply:${call.requestId}`) ?? []) cb(reply)
	},
}

const ctx = () => ({
	sessionManager: {
		getSessionId: () => SESSION,
		getSessionFile: () => join(scratch, "session.jsonl"),
		buildContextEntries: () => [],
	},
	ui: { notify: () => {} },
})

const pi = {
	on(name: string, cb: (payload: unknown, ctx: unknown) => void): void {
		events.on(name, (payload) => cb(payload, ctx()))
	},
	sendMessage(): void {},
	registerCommand(): void {},
	registerTool(config: { name: string; execute: (...args: unknown[]) => Promise<unknown> }): void {
		tools.set(config.name, config)
	},
	events,
}

// The mode file is written through the extension's own arming path, so the fixture
// cannot invent a shape the loader would not read.
const armed = mode.activate(
	{
		getActiveTools: () => [...mode.FOREMAN_TOOLS],
		setActiveTools: () => {},
		getAllTools: () => mode.FOREMAN_TOOLS.map((name: string) => ({ name })),
	},
	SESSION,
)
if (!armed.ok) {
	console.error(`the rig could not arm foreman mode: ${armed.error}`)
	process.exit(2)
}
const fleet = await jiti.import(`${AGENT_DIR}/extensions/fleet/index.ts`)
fleet.default(pi)
if (!mode.isOn(SESSION)) {
	console.error("foreman mode did not arm on this session id")
	process.exit(2)
}

// ── fixtures ─────────────────────────────────────────────────────────────────
function saveRoster(overrides: Record<string, unknown> = {}): void {
	mkdirSync(ROSTER_DIR, { recursive: true })
	// The identity claim the gone-run pass reads, written in the shape
	// `identity.claimProcessIdentity` writes: this process holds the worker's name,
	// so the pass leaves the worker alone and `assign` is the only thing deciding.
	mkdirSync(RUNTIME_DIR, { recursive: true })
	writeFileSync(
		join(RUNTIME_DIR, `${WORKER}.json`),
		JSON.stringify({ pid: process.pid, procStart: identity.procStartTime(process.pid), at: Date.now() }),
	)
	const r = roster.fresh(SESSION)
	r.crew.push({
		name: WORKER,
		state: "live",
		scope: SCOPE,
		asyncRunId: OLD_RUN,
		runIds: [OLD_RUN],
		handleUnverified: false,
		owns: ["probe/worker/**"],
		exclusive: ["none"],
		exclusiveDeclared: true,
		authored: ["probe/worker/**"],
		notResumableReason: null,
		...overrides,
	})
	roster.save(r)
}

function writeRecord(runId: string, text: string): void {
	const dir = join(TEMP_ROOT, "async-subagent-runs", runId)
	mkdirSync(dir, { recursive: true })
	writeFileSync(join(dir, "status.json"), text)
}

function clearRecords(): void {
	rmSync(join(TEMP_ROOT, "async-subagent-runs"), { recursive: true, force: true })
}

const rows = (...entries: Array<{ id: string; state: string; lastActivityAt?: number }>) => ({
	ok: true,
	data: { asyncSnapshot: { runs: entries } },
})

async function assign(): Promise<{ text: string; parsed: Record<string, unknown> }> {
	// The tool refuses a second action in one turn, so every scenario is its own turn.
	for (const cb of listeners.get("message_start") ?? []) cb({ message: { role: "assistant" } })
	const tool = tools.get("fleet")
	if (!tool) throw new Error("the fleet tool registered nothing")
	const res = (await tool.execute("probe", { action: "assign", name: WORKER, scope: SCOPE, task: ["probe task"], owns: ["probe/task/**"] }, null, null, ctx())) as {
		content: Array<{ text: string }>
	}
	const text = res.content[0].text
	return { text, parsed: JSON.parse(text) as Record<string, unknown> }
}

let failures = 0
function check(label: string, condition: boolean, detail: string): void {
	if (!condition) failures++
	console.log(`  ${condition ? "ok  " : "FAIL"} ${label} — ${detail}`)
}
const show = (label: string, text: string): void => console.log(`\n${label}:\n  ${text.replace(/\n/g, "\n  ")}`)

console.log(`scratch HOME ${HOME}`)

// absent record, owner answers: the resume is attempted and its verdict sticks
clearRecords()
saveRoster()
responder = ({ method }) => (method === "resume" ? { ok: false, error: { code: "no-session", message: "no persisted session to resume" } } : undefined)
{
	const { text, parsed } = await assign()
	show("absent (owner answers no-session)", text)
	check("reaches the resume attempt", !/cannot verify/.test(text) && /marked not-resumable/.test(text), parsed.message as string)
	check("worker marked not-resumable", roster.load(SESSION).crew[0].state === "not-resumable", roster.load(SESSION).crew[0].state)
}

// absent record, nobody answers: transient, and the worker is left alone
clearRecords()
saveRoster()
responder = () => undefined
{
	const { text, parsed } = await assign()
	show("absent (no owner listening)", text)
	check("reaches the resume attempt", !/cannot verify/.test(text) && /resume failed/.test(text), parsed.message as string)
	check("state unchanged", roster.load(SESSION).crew[0].state === "live", roster.load(SESSION).crew[0].state)
}

// a record that exists and cannot be read keeps the refusal, naming the case
clearRecords()
saveRoster()
writeRecord(OLD_RUN, "{ this is not json")
responder = () => undefined
{
	const { text, parsed } = await assign()
	show("unreadable record", text)
	check("refused, naming the unreadable record", /cannot verify/.test(text) && /cannot be read/.test(text), parsed.message as string)
}

// no run id at all: the identity refusal, not a resume aimed at null
clearRecords()
saveRoster({ asyncRunId: null, runIds: [] })
responder = () => undefined
{
	const { text, parsed } = await assign()
	show("no run id", text)
	check("refused, naming the unresolvable identity", /cannot be resolved/.test(text) && !/cannot verify/.test(text), parsed.message as string)
}

// absent record, owner answers the resume: the cold resume is the fix's headline
// path — a pruned record no longer costs a fresh hire under a new name
clearRecords()
saveRoster()
let coldSnapshot = rows()
responder = ({ method }) => {
	if (method === "status") return coldSnapshot
	if (method === "resume") {
		coldSnapshot = rows({ id: NEW_RUN, state: "running" })
		return { ok: true, data: { asyncRunId: NEW_RUN, childIndex: 0 } }
	}
	return undefined
}
{
	const { text, parsed } = await assign()
	show("absent (owner resumes)", text)
	check("assign succeeded", parsed.ok === true, parsed.ok === true ? "ok" : (parsed.message as string))
	check("resume reported cold", (parsed.reuse as { decision?: string } | undefined)?.decision === "cold-resume", JSON.stringify(parsed.reuse))
	check("the new run is the adopted handle", (parsed.handle as { asyncRunId?: string } | undefined)?.asyncRunId === NEW_RUN, JSON.stringify(parsed.handle))
}

// a row with no activity stamp: ambiguous, and the refusal names that case
clearRecords()
saveRoster()
responder = ({ method }) => (method === "status" ? rows({ id: OLD_RUN, state: "complete" }) : undefined)
{
	const { text, parsed } = await assign()
	show("row with no activity stamp", text)
	check("refused, naming the missing stamp", /cannot verify/.test(text) && /no activity stamp/.test(text), parsed.message as string)
}

// a running row: steer, never resume
clearRecords()
saveRoster()
responder = ({ method }) => (method === "status" ? rows({ id: OLD_RUN, state: "running" }) : undefined)
{
	const { text, parsed } = await assign()
	show("live row", text)
	check("refused as live", /is live \(running\/queued\)/.test(text), parsed.message as string)
}

// a settled row inside the window: the warm resume still proceeds
clearRecords()
saveRoster()
let snapshot = rows({ id: OLD_RUN, state: "complete", lastActivityAt: Date.now() - 1000 })
responder = ({ method }) => {
	if (method === "status") return snapshot
	if (method === "resume") {
		// The resumed run is a NEW one, which the snapshot confirms after the reply.
		snapshot = rows({ id: OLD_RUN, state: "complete", lastActivityAt: Date.now() - 1000 }, { id: NEW_RUN, state: "running" })
		return { ok: true, data: { asyncRunId: NEW_RUN, childIndex: 0 } }
	}
	return undefined
}
{
	const { text, parsed } = await assign()
	show("warm row", text)
	check("assign succeeded", parsed.ok === true, parsed.ok === true ? "ok" : (parsed.message as string))
	check("resume reported warm", (parsed.reuse as { decision?: string } | undefined)?.decision === "warm-resume", JSON.stringify(parsed.reuse))
}

console.log(`\n${failures === 0 ? "all scenarios ok" : `${failures} FAILURES`}`)
rmSync(scratch, { recursive: true, force: true })
process.exit(failures === 0 ? 0 : 1)
