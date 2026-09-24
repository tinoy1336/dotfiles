// Offline verification of the resume-hop half of the crew-name fix.
//
// The spawn hop is covered by verify-offline.mjs; this rig drives the OTHER hop,
// the one a warm `fleet assign` / `fleet review` takes: the fleet sends a resume
// request with the worker's name as `label`, the installed RPC bridge normalises
// it, and the executor receives it. Loading the installed `rpc.js` through jiti
// (the loader pi uses) and feeding the request envelope the fleet builds asserts
// that the label survives the normaliser instead of being dropped there.
//
// The hop after the bridge — the revive call that puts the label on the newly
// launched step — cannot be driven offline: reaching it starts a real child
// runner. Assert on the shipped bytes instead.
//
// Set PI_SUBAGENTS_PKG to point at another package tree (a pre-patch copy, say) to
// drive the same envelope through it.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";
import { readFileSync } from "node:fs";

const PKG = process.env.PI_SUBAGENTS_PKG ?? "/home/tinoy/.pi/agent/npm/node_modules/pi-subagents";
const FLEET = "/home/tinoy/.pi/agent/extensions/fleet/index.ts";
const jiti = createJiti(import.meta.url);

const ok = (label, cond, extra = "") => {
	console.log(`${cond ? "PASS" : "FAIL"}  ${label}${extra ? " :: " + extra : ""}`);
	if (!cond) process.exitCode = 1;
};

// The hiring side: every resume envelope the fleet sends names the crew member.
// The payload keys are read out of the fleet source, so the envelope driven below
// is the fleet's own shape and not a rig invention.
const fleetSource = readFileSync(FLEET, "utf8");
const resumeCalls = [...fleetSource.matchAll(/rpc\(pi, "resume", \{([^}]*)\}/g)].map((match) => match[1]);
ok("fleet sends resume envelopes", resumeCalls.length >= 2, `${resumeCalls.length} call sites`);
for (const [index, keys] of resumeCalls.entries()) {
	ok(`fleet resume call ${index + 1} carries a label`, /\blabel:/.test(keys), keys.trim().replace(/\s+/g, " "));
}

// Drive the installed bridge with that envelope, one request per case.
const rpc = await jiti.import(`${PKG}/src/extension/rpc.js`);
const makeBus = () => {
	const handlers = new Map();
	const replies = [];
	return {
		replies,
		on(event, handler) {
			const list = handlers.get(event) ?? [];
			list.push(handler);
			handlers.set(event, list);
			return () => {};
		},
		emit(event, data) {
			if (event.startsWith("subagents:rpc:v1:reply:")) replies.push({ event, data });
		},
		async request(envelope) {
			for (const handler of handlers.get("subagents:rpc:v1:request") ?? []) await handler(envelope);
		},
	};
};

async function resumeHop(params) {
	const bus = makeBus();
	let seen;
	let execError;
	const bridge = rpc.registerSubagentRpcBridge({
		events: bus,
		getContext: () => ({ sessionManager: { getSessionId: () => "resume-label-rig" }, cwd: "/tmp", hasUI: false, modelRegistry: { getAvailable: () => [] } }),
		execute: async (_id, execParams) => {
			seen = { ...execParams };
			return { content: [{ type: "text", text: "stub: no child runner is started offline" }], details: { mode: "management", results: [] } };
		},
	});
	await bus.request({ version: rpc.SUBAGENT_RPC_PROTOCOL_VERSION, requestId: "rig-1", method: "resume", params, source: { extension: "fleet" } });
	bridge.dispose();
	const reply = bus.replies.at(-1)?.data;
	if (reply?.success === false) execError = `${reply.error?.code}: ${reply.error?.message}`;
	return { seen, error: execError };
}

// The fleet's assign payload for a warm worker: the id and index the roster
// holds, the crew name as the label, and the follow-up as the message.
const labelled = await resumeHop({ id: "89be04b4-1c1f-4ee0-9d0f-6f1c2f4a7b31", index: 0, label: "carol", message: "follow-up" });
ok("bridge hands the resume to the executor", Boolean(labelled.seen), labelled.error ?? "");
ok("resume reaches the executor as a resume", labelled.seen?.action === "resume", JSON.stringify(labelled.seen));
ok("the crew label survives the resume normaliser", labelled.seen?.label === "carol", JSON.stringify(labelled.seen));
ok("the target id survives", labelled.seen?.id === "89be04b4-1c1f-4ee0-9d0f-6f1c2f4a7b31");
ok("the child index survives", labelled.seen?.index === 0);
ok("the follow-up message survives", labelled.seen?.message === "follow-up");
ok("the resume params are exactly action, id, index, label, message", Object.keys(labelled.seen ?? {}).sort().join(",") === "action,id,index,label,message", Object.keys(labelled.seen ?? {}).join(","));

// Control: a resume with no label must not gain one, and must keep reaching the
// executor — the label is display metadata, never a requirement.
const bare = await resumeHop({ id: "89be04b4-1c1f-4ee0-9d0f-6f1c2f4a7b31", index: 0, message: "follow-up" });
ok("an unlabelled resume still reaches the executor (control)", bare.seen?.action === "resume", JSON.stringify(bare.seen));
ok("an unlabelled resume stays unlabelled", bare.seen !== undefined && !("label" in bare.seen), JSON.stringify(bare.seen));

// A stray non-string label is refused rather than forwarded as garbage.
const junk = await resumeHop({ id: "89be04b4-1c1f-4ee0-9d0f-6f1c2f4a7b31", index: 0, label: "   ", message: "follow-up" });
ok("a blank label is dropped", junk.seen !== undefined && !("label" in junk.seen), JSON.stringify(junk.seen));

// The revive call site: the label must ride the launch params the child rebuilds
// its status step from, exactly as the single-spawn call site does.
const executor = readFileSync(`${PKG}/src/runs/foreground/subagent-executor.js`, "utf8").split("\n");
const reviveCall = executor.findIndex((line) => line.includes("task: buildRevivedAsyncTask("));
const reviveBlock = reviveCall >= 0 ? executor.slice(reviveCall, reviveCall + 10).join("\n") : "";
ok("revive call site forwards label into the revived run (source assertion)", reviveBlock.includes("label: input.params.label.trim()"), reviveCall < 0 ? "revive call site not found" : `line ${reviveCall + 1}`);

console.log(process.exitCode ? "VERIFY FAILED" : "VERIFY OK");
