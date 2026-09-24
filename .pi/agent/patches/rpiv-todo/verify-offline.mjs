// Offline verification of the rpiv-todo external-refresh patch.
// Loads the PATCHED package through jiti (the loader pi uses), drives it with a
// fake ExtensionAPI, and proves the subscriber replays branch truth into the
// store the registered `todo` tool reads.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";

const PKG = "/home/tinoy/.pi/agent/npm/node_modules/@juicesharp/rpiv-todo";
const CHANNEL = "rpiv-todo:external-refresh";
const jiti = createJiti(import.meta.url);

const ok = (label, cond, extra = "") => {
	console.log(`${cond ? "PASS" : "FAIL"}  ${label}${extra ? " :: " + extra : ""}`);
	if (!cond) process.exitCode = 1;
};

// Same jiti registry as index.ts -> the SAME store module instance the tool uses.
const store = await jiti.import(`${PKG}/state/store.js`);
const mod = await jiti.import(`${PKG}/index.ts`);

const bus = new Map();
const handlers = new Map();
const tools = [];
let overlayImports = 0;
const pi = {
	on(event, handler) {
		if (!handlers.has(event)) handlers.set(event, []);
		handlers.get(event).push(handler);
	},
	events: {
		on(channel, handler) {
			if (!bus.has(channel)) bus.set(channel, []);
			bus.get(channel).push(handler);
		},
		emit() {},
	},
	registerTool(tool) { tools.push(tool); },
	registerCommand() {},
	registerShortcut() {},
};

mod.default(pi, async () => { overlayImports++; throw new Error("overlay import must not be needed here"); });

// --- the branch the crew proxy writes -------------------------------------
const BASE = [1, 2, 3, 4, 5, 6].map((id) => ({ id, subject: `Task ${id}`, status: "completed" }));
const CREW = { id: 7, subject: "todo_parent end-to-end verification", status: "completed", activeForm: "verifying todo_parent" };
const entries = [
	{ type: "message", message: { role: "toolResult", toolName: "todo", content: [{ type: "text", text: "No tasks" }], details: { action: "list", tasks: BASE, nextId: 7 }, isError: false, timestamp: 1 } },
	{ type: "message", message: { role: "toolResult", toolName: "todo", content: [{ type: "text", text: "todo_parent mutation" }], details: { action: "create", tasks: [...BASE, CREW], nextId: 8 }, isError: false, timestamp: 2 } },
];
const ctx = { hasUI: false, sessionManager: { getSessionId: () => "sid-A", getBranch: () => entries } };
const SID = "sid-A";
const stale = { tasks: BASE.map((t) => ({ ...t })), nextId: 7 };

ok("subscriber registered on " + CHANNEL, (bus.get(CHANNEL) ?? []).length === 1);
ok("package still registers its own handlers", (handlers.get("session_start") ?? []).length === 1 && (handlers.get("session_tree") ?? []).length === 1);
ok("package still registers the todo tool", tools.some((t) => t.name === "todo"));

await handlers.get("session_start")[0]({}, ctx);
ok("session_start replays the branch (unchanged behaviour)", store.getState(SID).tasks.length === 7, `tasks=${store.getState(SID).tasks.length}`);

const todoTool = tools.find((t) => t.name === "todo");
// Simulate what the user sees today: the live store holding the pre-append snapshot.
store.replaceState(SID, stale);
const before = await todoTool.execute("c1", { action: "list" }, undefined, undefined, ctx);
ok("pre-fix divergence reproduces in the rig (tool cannot see #7)", !before.content[0].text.includes("#7"), JSON.stringify(before.content[0].text.slice(0, 60)));

// The fix: the crew proxy's emit.
await bus.get(CHANNEL)[0]({ sid: SID });
ok("subscriber replaced the store with branch truth", store.getState(SID).tasks.some((t) => t.id === 7 && t.subject === CREW.subject));

const after = await todoTool.execute("c2", { action: "list" }, undefined, undefined, ctx);
ok("the todo TOOL now reports the crew entry", after.content[0].text.includes("#7") && after.content[0].text.includes("todo_parent end-to-end verification"));

// Ownership gate: a request for another session must not touch this board.
store.replaceState(SID, stale);
await bus.get(CHANNEL)[0]({ sid: "sid-OTHER" });
ok("foreign-sid request ignored", store.getState(SID).tasks.length === 6);
await bus.get(CHANNEL)[0]({});
ok("request without sid falls back to the stashed session", store.getState(SID).tasks.length === 7);

ok("overlay import untouched in a headless ctx (uICtx unbound)", overlayImports === 0);

// Also load the package entrypoints that the patch touches downstream.
await jiti.import(`${PKG}/todo.ts`);
await jiti.import(`${PKG}/state/replay.ts`);
ok("todo.ts + state/replay.ts still load", true);

// --- phase 2: the REAL pi event bus (one per process, shared by both extensions)
// Proves the channel actually carries todo-parent.ts's `emit(channel, { sid })`
// into this subscriber, using the SDK's own EventBus implementation.
const { createEventBus } = await jiti.import(
	"/usr/lib/node_modules/@earendil-works/pi-coding-agent/dist/index.js",
);
const bus2 = createEventBus();
const tools2 = [];
const handlers2 = new Map();
const pi2 = {
	on(event, handler) {
		if (!handlers2.has(event)) handlers2.set(event, []);
		handlers2.get(event).push(handler);
	},
	events: bus2,
	registerTool(tool) { tools2.push(tool); },
	registerCommand() {},
	registerShortcut() {},
};
mod.default(pi2, async () => { throw new Error("overlay import must not be needed here"); });
await handlers2.get("session_start")[0]({}, ctx);
store.replaceState(SID, stale);
const delivered = await new Promise((resolve) => {
	const unsub = bus2.on(CHANNEL, (data) => { resolve(true); void data; });
	// exactly what todo-parent.ts emits after appending its row
	bus2.emit(CHANNEL, { sid: SID });
	setTimeout(() => { unsub(); resolve(false); }, 50);
});
ok("SDK EventBus delivers todo-parent's emit to the subscriber", delivered);
ok("…and the shared store then holds the crew entry", store.getState(SID).tasks.some((t) => t.id === 7));
const tool2 = tools2.find((t) => t.name === "todo");
const afterBus = await tool2.execute("c3", { action: "list" }, undefined, undefined, ctx);
ok("…and the tool reports it", afterBus.content[0].text.includes("todo_parent end-to-end verification"));
