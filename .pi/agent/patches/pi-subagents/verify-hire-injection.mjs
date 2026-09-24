// Offline verification of the hire-time worker instruction the `fleet` tool injects.
// Drives the real hire path with a stub pi host — no model, no child run — and
// captures the spawn request the tool emits, so the task text a hired worker would
// actually receive is asserted from the shipped code.
//
// The stub host redirects HOME to a scratch directory before the fleet modules
// load, because the mode file, the crew roster and the claim roots are derived
// from HOME at module load: the real foreman state is never touched.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOME = mkdtempSync(join(tmpdir(), "pi-hire-rig-"));
process.env.HOME = HOME;
const SID = "hire-rig-session";
mkdirSync(join(HOME, ".local", "pi", "foreman", "roster"), { recursive: true });
writeFileSync(join(HOME, ".local", "pi", "foreman", "roster", `mode-${SID}.json`), `${JSON.stringify({ on: true, sessionId: SID, since: Date.now() })}\n`);

const jiti = createJiti(import.meta.url);
const fleet = await jiti.import("/home/tinoy/.pi/agent/extensions/fleet/index.ts");

let fail = 0;
const ok = (name, cond, extra = "") => {
	console.log(`${cond ? "PASS" : "FAIL"}  ${name}${extra ? " :: " + extra : ""}`);
	if (!cond) fail = 1;
};

let tool;
let captured;
const listeners = new Map();
const emit = (event, payload) => {
	if (event !== "subagents:rpc:v1:request") return;
	captured = payload;
	// Answer the spawn request immediately with a stub refusal: the injected task
	// text is what this rig asserts, and waiting would stall on the tool's own
	// 30s transport deadline.
	listeners.get(`subagents:rpc:v1:reply:${payload.requestId}`)?.({ success: false, error: { code: "stub", message: "stub host: no spawn" } });
};
const pi = {
	events: { on: (event, cb) => listeners.set(event, cb), emit },
	registerTool: (cfg) => {
		tool = cfg;
	},
	registerCommand: () => {},
	registerSection: () => {},
	on: () => {},
	setStatus: () => {},
	getActiveTools: () => ["fleet", "todo", "read", "write"],
	setActiveTools: () => {},
	getAllTools: () => [{ name: "fleet" }, { name: "todo" }, { name: "read" }, { name: "write" }],
};

fleet.default(pi);
ok("the fleet tool registers", Boolean(tool));

const ctx = { sessionManager: { getSessionId: () => SID }, ui: { notify: () => {} }, cwd: HOME };
await tool.execute("call-1", { action: "hire", name: "delphine", scope: "read-only recon of the app specs", task: ["list the flows"], owns: ["/tmp/recon.md"], exclusive: ["none"] }, undefined, undefined, ctx);

const task = captured?.params?.task;
const lines = typeof task === "string" ? task.split("\n") : [];
ok("hire emits a spawn request", Boolean(captured));
ok("the spawn names the crew member", captured?.params?.label === "delphine", String(captured?.params?.label));
ok("the injected first line names the worker and its scope", lines[0] === "read ~/.local/pi/foreman/worker.md and follow it; your name is delphine, your scope is read-only recon of the app specs", String(lines[0]));
ok("the board-entry form reaches the worker with its own name", lines[1] === 'your todo entries are written with your own name first — "delphine: <imperative subject>", e.g. "delphine: extract the shared divider into common/media"', String(lines[1]));
ok("the literal agent type is never offered as the worker's name", typeof task === "string" && !/your name is worker/.test(task));
ok("the caller's task text follows the injected lines", typeof task === "string" && task.trimEnd().endsWith("list the flows"));

rmSync(HOME, { recursive: true, force: true });
console.log(fail ? "VERIFY FAILED" : "VERIFY OK");
process.exitCode = fail;
