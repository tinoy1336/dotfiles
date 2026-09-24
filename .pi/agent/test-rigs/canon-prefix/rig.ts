/**
 * rig.ts — shared loader/path core for the offline canon rig.
 *
 * The offline harnesses test the INSTALLED modules, never copies: the extensions
 * are imported from the real extensions directory and canon from the installed
 * package, so a green run says something about what pi actually loads. Two seams
 * make that possible without a running pi:
 *
 *  - `@earendil-works/pi-coding-agent` is bundled INSIDE the pi binary (the
 *    shipped package has no importable dist), so the specifier cannot resolve
 *    from a plain node process. The resolve hook maps it to `pi-sdk-shim.mjs`,
 *    which provides the one value the extensions import from it (`defineTool`);
 *    every other member they import from that specifier is type-only, erased by
 *    node's type stripping.
 *  - `lib/hook-log.ts` is observability only, and its real copy appends to
 *    `~/.local/share/pi-hooks/log.jsonl`. The resolve hook redirects it to
 *    `hook-log-recorder.mjs`, which captures the same `(source, kind, detail)`
 *    lines in-process and mirrors them into this run's own dir — the rig never
 *    writes the user's real hook log. BOTH copies of that module are redirected:
 *    the tree's `lib/hook-log.ts` and the published `@tinoy/pi-ext-lib` one the
 *    canon package imports.
 *
 * Every path resolves from this file, so the rig runs from any directory. Each
 * invocation writes into a fresh stamped `runs/<ts>-<pid>/`, so a re-run can
 * never be read as the previous run's evidence.
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { registerHooks } from "node:module";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const RIG_DIR = dirname(fileURLToPath(import.meta.url));

/** The real agent dir — canon reads its store from here. PI_CODING_AGENT_DIR
 *  wins, matching the extension's own resolution. */
const AGENT_DIR =
	process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");

/** Installed extensions. Overridable only for a relocated install, never to
 *  point at a rig copy. */
export const EXTENSIONS_DIR =
	process.env.PI_EXTENSIONS_DIR || join(AGENT_DIR, "extensions");

/** The live canon store the fixture block is rendered from. */
export const STORE_PATH = join(AGENT_DIR, "canon", "canon.json");

/**
 * The launch shapes a session can have. Every real launcher produces exactly one
 * of them: a parent session carries no marker, `~/.local/bin/pi-subagent`
 * exports PI_SUBAGENT=1 into the pi process it starts, and the pi-subagents
 * async runner sets PI_SUBAGENT_CHILD=1 at module load (the shape every crew
 * worker arrives through).
 */
export type SessionShape = "parent" | "wrapper-child" | "async-child";

/**
 * Every marker the extensions under test read to classify a session: canon.ts
 * and child-prompt-freeze.ts both treat PI_SUBAGENT (pi-subagent wrapper) or
 * PI_SUBAGENT_CHILD (pi-subagents async runner) as "child", and canon adds
 * PI_FOREMAN to a parent's audiences.
 */
const SESSION_MARKERS = [
	"PI_SUBAGENT",
	"PI_SUBAGENT_CHILD",
	"PI_FOREMAN",
] as const;

/**
 * Declare the shape a case means to test, clearing every marker first so nothing
 * is inherited from the shell that launched the rig. A rig that reads the
 * shell's own shape instead silently switches subject depending on where it runs
 * — a crew worker shell exports PI_SUBAGENT_CHILD=1, so a case that means
 * "parent session" must clear it explicitly.
 */
export function setSessionShape(shape: SessionShape): void {
	for (const marker of SESSION_MARKERS) delete process.env[marker];
	if (shape === "wrapper-child") process.env.PI_SUBAGENT = "1";
	if (shape === "async-child") process.env.PI_SUBAGENT_CHILD = "1";
}

const STAMP = `${new Date().toISOString().replace(/[:.]/g, "-")}-${process.pid}`;
export const RUN_DIR = join(RIG_DIR, "runs", STAMP);
mkdirSync(RUN_DIR, { recursive: true });

/** A per-run artifact path inside this run's own dir (never a shared name). */
export function runPath(name: string): string {
	return join(RUN_DIR, name);
}

// The recorder reads this at load; set it before any extension is imported.
process.env.RIG_HOOK_LOG = runPath("hook-log.jsonl");

const SDK_SHIM = pathToFileURL(join(RIG_DIR, "pi-sdk-shim.mjs")).href;
const HOOK_LOG_RECORDER = pathToFileURL(
	join(RIG_DIR, "hook-log-recorder.mjs"),
).href;

registerHooks({
	resolve(specifier, context, nextResolve) {
		if (specifier === "@earendil-works/pi-coding-agent") {
			return { url: SDK_SHIM, shortCircuit: true };
		}
		const resolved = nextResolve(specifier, context);
		if (
			typeof resolved?.url === "string" &&
			resolved.url.endsWith("/hook-log.ts")
		) {
			return { url: HOOK_LOG_RECORDER, shortCircuit: true };
		}
		return resolved;
	},
});

/**
 * The installed canon PACKAGE, resolved the way pi resolves it. Canon is no
 * longer a file in the extensions directory: it is the settings `packages` entry
 * `npm:@tinoy/pi-canon`, whose file lives under the agent dir's npm tree. A bare
 * specifier is NOT usable here — bare specifiers resolve by walking UP from this
 * rig's own directory, and the tree holding these packages is reached through a
 * sibling link (`extensions/node_modules -> ../npm/node_modules`), never an
 * ancestor of `test-rigs/`.
 */
const NPM_TREE = join(AGENT_DIR, "npm", "node_modules");
export const CANON_ENTRY = join(NPM_TREE, "@tinoy", "pi-canon", "canon.ts");

/**
 * The shared library that OWNS the system-prompt seam. `canonicalSystemPrompt`,
 * `systemPromptSlot` and `PROMPT_APPEND_SEP` live there, not in canon: canon
 * imports them, and `child-prompt-freeze.ts` imports `systemPromptSlot` from the
 * same package. Consumers therefore take the seam from the package — the rig
 * does the same rather than looking for a re-export canon no longer has.
 */
export const EXT_LIB_ENTRY = join(NPM_TREE, "@tinoy", "pi-ext-lib", "src", "index.ts");

/** Import the real installed modules (resolve hooks already armed). */
export async function loadCanon(): Promise<any> {
	return import(pathToFileURL(CANON_ENTRY).href);
}
/** The prompt seam as its consumers see it: the shared package. */
export async function loadSeam(): Promise<any> {
	return import(pathToFileURL(EXT_LIB_ENTRY).href);
}
export async function loadFreeze(): Promise<any> {
	return import(
		pathToFileURL(join(EXTENSIONS_DIR, "child-prompt-freeze.ts")).href
	);
}
export async function loadLogger(): Promise<any> {
	return import(
		pathToFileURL(join(EXTENSIONS_DIR, "cache-prefix-log.ts")).href
	);
}

export const RIG_SESSION = "01a0972c-c592-73c0";

export interface FakePi {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	api: any;
	handlers: Record<string, Array<(event: unknown, ctx: unknown) => unknown>>;
}

/** A fake pi API that records `on()` handlers and no-ops every tool/command
 *  member the extensions may touch. */
export function fakePi(): FakePi {
	const handlers: FakePi["handlers"] = {};
	const noop = () => {};
	const base: Record<string | symbol, unknown> = {
		on(ev: string, h: (event: unknown, ctx: unknown) => unknown) {
			(handlers[ev] ??= []).push(h);
		},
		registerTool: noop,
		registerCommand: noop,
		events: { on: noop, emit: noop },
		getSessionName: () => "rig",
		sendMessage: noop,
		appendEntry: noop,
		getActiveTools: () => [],
		setActiveTools: noop,
		exec: async () => ({ stdout: "", stderr: "", code: 0 }),
	};
	const api = new Proxy(base, {
		get: (t, k) => (k in t ? t[k] : noop),
	});
	return { api, handlers };
}

/** Emit one event through every handler, in registration order; returns the
 *  last non-undefined handler result (how pi threads before_agent_start). */
export async function emitEvent(
	handlers: FakePi["handlers"],
	ev: string,
	event: unknown,
	ctx: unknown,
): Promise<unknown> {
	let last: unknown;
	for (const h of handlers[ev] ?? []) {
		const r = await h(event, ctx);
		if (r !== undefined) last = r;
	}
	return last;
}

export function makeEmit(
	handlers: FakePi["handlers"],
	ctx: unknown,
): (ev: string, event: unknown) => Promise<unknown> {
	return (ev, event) => emitEvent(handlers, ev, event, ctx);
}

export const tick = (): Promise<void> =>
	new Promise((resolve) => setTimeout(resolve, 20));

export function canonCtx(model = "deepseek-flash"): unknown {
	return {
		model: { id: model },
		sessionManager: { getSessionId: () => RIG_SESSION },
	};
}

/** Abort loudly (exit 2) — used when a precondition cannot be met, so the run
 *  can never fall through to a green "everything passed" on missing data. */
export function fail(message: string): never {
	console.error(`\nRIG ABORT: ${message}`);
	process.exit(2);
}

/**
 * Derive the canon block from the LIVE store at run time, through the real
 * extension: register canon's real `before_agent_start` hook, fire it, and take
 * the bytes it appends. There is no recorded block to age — if the store cannot
 * render one, the rig aborts naming the store instead of testing a stale copy.
 */
export async function deriveBlock(
	canon: any,
	opts: { model?: string; base?: string } = {},
): Promise<string> {
	const model = opts.model ?? "deepseek-flash";
	const base = opts.base ?? "RIG-BASE-PROMPT";
	const { api, handlers } = fakePi();
	canon.default(api);
	const ctx = canonCtx(model);
	const appended = (await emitEvent(
		handlers,
		"before_agent_start",
		{ systemPrompt: base },
		ctx,
	)) as { systemPrompt?: unknown } | undefined;
	const sys = appended?.systemPrompt;
	// The block is located by its OWN header, never by the separator in front of it:
	// the separator belongs to the seam package (`PROMPT_APPEND_SEP`) and its length
	// is that module's business, not this helper's.
	const MARKER = "## Canon";
	const at = typeof sys === "string" ? sys.indexOf(MARKER) : -1;
	if (at < base.length) {
		fail(
			`the live canon store ${STORE_PATH} rendered no canon block through the real ` +
				`before_agent_start hook (model=${model}); expected marker ${JSON.stringify(MARKER)}. ` +
				`The rig refuses to run against a stale or foreign fixture.`,
		);
	}
	const block = sys.slice(at);
	if (!block.startsWith(MARKER)) {
		fail(
			`the derived canon block did not start with its marker (store ${STORE_PATH}); ` +
				`the renderer or the strip rule changed.`,
		);
	}
	return block;
}

export interface Checker {
	check: (name: string, ok: boolean, detail?: string) => void;
	count: () => number;
}

export function createChecker(): Checker {
	let failures = 0;
	const check = (name: string, ok: boolean, detail = ""): void => {
		if (!ok) failures++;
		console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  ${detail}` : ""}`);
	};
	return { check, count: () => failures };
}

export function finish(name: string, failures: number): void {
	console.log(`\nrun artifacts: ${RUN_DIR}`);
	console.log(
		failures === 0
			? `\nALL ${name} CHECKS PASSED`
			: `\n${failures} CHECK(S) FAILED`,
	);
	// Keep the artifact dir, but leave a one-line pointer for the run's stdout.
	try {
		appendFileSync(
			join(RUN_DIR, "result.txt"),
			`${name}: ${failures === 0 ? "PASS" : `FAIL(${failures})`}\n`,
		);
	} catch {
		/* evidence only */
	}
	process.exit(failures === 0 ? 0 : 1);
}
