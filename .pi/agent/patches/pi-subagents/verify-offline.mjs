// Offline verification of the pi-subagents display-label patch.
// Loads the PATCHED package source through jiti (the loader pi uses) and drives
// the real async-agents widget line builder with synthetic job states, so the
// row label the user sees is asserted without a running pi session.
//
// The job states fed here mirror the tracker's own output: `summaryToJob`
// (src/runs/background/async-job-tracker.js) spreads each status.json step into
// the job's `steps`, so a labelled step on disk is a labelled step in the widget.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";
import { readFileSync } from "node:fs";

const PKG = "/home/tinoy/.pi/agent/npm/node_modules/pi-subagents";
const FLEET = "/home/tinoy/.pi/agent/extensions/fleet";
const jiti = createJiti(import.meta.url);

const ok = (label, cond, extra = "") => {
	console.log(`${cond ? "PASS" : "FAIL"}  ${label}${extra ? " :: " + extra : ""}`);
	if (!cond) process.exitCode = 1;
};

const render = await jiti.import(`${PKG}/src/tui/render.js`);
const schemas = await jiti.import(`${PKG}/src/extension/schemas.js`);

// Theme stub: the widget path only colours text, so returning the text unchanged
// keeps the assertions about labels readable.
const theme = { fg: (_token, text) => text, bold: (text) => text };

const now = Date.now();
const job = ({ id, mode, agents, steps, chainStepCount = steps.length, status = "running" }) => ({
	asyncId: id,
	asyncDir: `/tmp/offline-rig/${id}`,
	toolCallId: `call_${id}`,
	status,
	mode,
	agents,
	steps,
	stepsTotal: steps.length,
	runningSteps: steps.filter((step) => step.status === "running").length,
	completedSteps: 0,
	currentStep: 0,
	chainStepCount,
	parallelGroups: [],
	startedAt: now,
	updatedAt: now,
});

const step = (extra = {}) => ({ agent: "worker", status: "running", turnCount: 3, toolCount: 5, ...extra });

// The user's panel: two plain single-mode crew runs at the same indent.
const crewJobs = [
	job({ id: "run-alice", mode: "single", agents: ["worker"], steps: [step({ label: "alice" })] }),
	job({ id: "run-bob", mode: "single", agents: ["worker"], steps: [step({ label: "bob" })] }),
];
const crewLines = render.buildWidgetLines(crewJobs, theme, 120, false, 0);
const crewText = crewLines.join("\n");
ok("panel renders without a live session", crewLines.length >= 3, `${crewLines.length} lines`);
ok("crew name 'alice' labels its row", crewText.includes("alice"));
ok("crew name 'bob' labels its row", crewText.includes("bob"));
ok("the agent type no longer labels the rows", !/^\S*?[├└]─?.*\bworker\b/m.test(crewText) || !crewText.includes("worker ·"), crewLines.find((l) => l.includes("alice")) ?? "");

// Negative control: with no label supplied the row must read like it does today.
const plainJobs = [job({ id: "run-plain", mode: "single", agents: ["worker"], steps: [step()] })];
const plainText = render.buildWidgetLines(plainJobs, theme, 120, false, 0).join("\n");
ok("unlabelled run still shows the agent type (control)", plainText.includes("worker") && !plainText.includes("alice"), plainText.split("\n").find((l) => l.includes("worker")) ?? "");

// Composite runs keep their own naming even when their steps carry labels.
const parallelJobs = [
	job({ id: "run-par", mode: "parallel", agents: ["worker", "worker"], steps: [step({ label: "alice" }), step({ label: "bob" })], chainStepCount: 2 }),
];
const parallelText = render.buildWidgetLines(parallelJobs, theme, 120, false, 0).join("\n");
ok("parallel run is still named 'parallel'", parallelText.includes("parallel") && !/^\S*?├─.*alice/m.test(parallelText));

// The seam the fleet uses: `label` is a declared spawn parameter, and the single
// status step is what the widget reads.
const props = schemas.SubagentParams?.properties ?? {};
ok("spawn schema declares a top-level label", typeof props.label === "object" && props.label !== null && props.label.type === "string", JSON.stringify(props.label ?? null).slice(0, 120));
ok("spawn schema still declares agent/task", typeof props.agent === "object" && typeof props.task === "object");

// The hiring side: the envelope the foreman's `fleet` tool sends to the spawn RPC
// must name the crew member.
const launch = await jiti.import(`${FLEET}/launch.ts`);
const envelope = launch.spawnParams("task text", 60_000, { worker: "delphine", scope: "recon", owns: ["a/**"], exclusive: [] });
ok("fleet spawn envelope carries label = the crew name", envelope.label === "delphine", String(envelope.label));
ok("fleet spawn envelope carries the crew binding", envelope.extensionBindings?.[launch.BINDING_NAMESPACE]?.worker === "delphine");
const bare = launch.spawnParams("task text", 60_000);
ok("fleet spawn envelope without a binding carries no label", bare.label === undefined);

// The executor hop cannot be driven offline: reaching it launches a real child
// runner. Assert on the shipped bytes instead — the single async spawn call site
// forwards the label into executeAsyncSingle, which is the hop that was missing.
const executor = readFileSync(`${PKG}/src/runs/foreground/subagent-executor.js`, "utf8").split("\n");
const callSite = executor.findIndex((line) => line.includes("task: shouldForkAgent(contextPolicy, params.agent)"));
const callBlock = callSite >= 0 ? executor.slice(callSite, callSite + 8).join("\n") : "";
ok("executor forwards label into the single async spawn (source assertion)", callBlock.includes("label: params.label.trim()"), callSite < 0 ? "call site not found" : `line ${callSite + 1}`);

console.log(process.exitCode ? "VERIFY FAILED" : "VERIFY OK");
