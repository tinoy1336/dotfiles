// Offline verification of the pi-subagents pause-aware control patch.
//
// Loads the PATCHED package source through jiti (the loader pi uses) and drives the
// real control-notification gate — `shouldNotifyControlEvent`, the one decision every
// foreground and detached-run control signal passes — with synthetic quiet-run events.
// The pause is a scratch state file (`PI_PAUSE_STATE`), driven through the pause
// library's own `setPause`/`clearPause`, so no real machine-wide pause is started and
// no live session is parked.
//
// Three cases:
//   A  pause ACTIVE with a future deadline -> every quiet-run signal is held back
//   B  pause RELEASED                      -> the normal signal returns, and the held
//                                             signals come back as ONE line per run
//   C  no state file at all                -> unchanged behaviour (signal as usual)
//
// `PI_SUBAGENTS_PKG=<dir>` drives another package tree. Unset PI_SUBAGENT_CHILD when
// running this from a subagent.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const PKG = process.env.PI_SUBAGENTS_PKG ?? "/home/tinoy/.pi/agent/npm/node_modules/pi-subagents";
const AGENT_DIR = process.env.PI_CODING_AGENT_DIR ?? "/home/tinoy/.pi/agent";
const WORK = process.env.PI_PAUSE_PROOF_DIR ?? "/tmp/pause-aware-watchdog-2026-09-23/proof";
const STATE = `${WORK}/pi-pause.json`;

mkdirSync(WORK, { recursive: true });
rmSync(STATE, { force: true });
process.env.PI_CODING_AGENT_DIR = AGENT_DIR;
process.env.PI_PAUSE_STATE = STATE;

const jiti = createJiti(import.meta.url);
const control = await jiti.import(`${PKG}/src/runs/shared/subagent-control.js`);
const pause = await jiti.import(`${AGENT_DIR}/extensions/lib/pause-state.ts`);

let failed = false;
const ok = (label, cond, extra = "") => {
	if (!cond)
		failed = true;
	console.log(`${cond ? "PASS" : "FAIL"}  ${label}${extra ? ` :: ${extra}` : ""}`);
};
/** The signal a supervising session sees for a run that has gone quiet. */
const quietEvent = (runId, ts, index) => control.buildControlEvent({
	type: "needs_attention",
	to: "needs_attention",
	runId,
	agent: "worker",
	index,
	ts,
	lastActivityAt: ts - 90_000,
	elapsedMs: 90_000,
	reason: "idle",
});

const RUNS = [
	["run-anja", 0],
	["run-build", 0],
	["run-design", 0],
];

console.log(`package      ${PKG}`);
console.log(`pause state  ${pause.pauseStatePath()}`);
console.log(`gate config  notifyOn=${JSON.stringify(control.DEFAULT_CONTROL_CONFIG.notifyOn)} enabled=${control.DEFAULT_CONTROL_CONFIG.enabled}`);
console.log("");

// --- baseline mode: a package tree without the patch ---------------------------
// The control for this verification: the same events against an UNPATCHED tree, which
// is what the machine ran before the patch — a pause parks every run and each one still
// reports its own inactivity notice.
if (typeof control.pauseHoldsControlNotifications !== "function") {
	console.log("=== BASELINE: this tree is UNPATCHED (no pause gate) ===");
	pause.setPause(Date.now() + 30 * 60_000, "verify-pause-aware-control");
	const notified = RUNS.map(([runId, index]) => {
			const event = quietEvent(runId, Date.now(), index);
			const verdict = control.shouldNotifyControlEvent(control.DEFAULT_CONTROL_CONFIG, event);
			console.log(`  ${runId} signal "${event.message}" -> shouldNotifyControlEvent=${verdict}`);
			return verdict;
	});
	ok("unpatched: every parked run still reports its inactivity notice", notified.every((value) => value === true), `notified=${notified.filter(Boolean).length}/${notified.length}`);
	pause.clearPause("verify-pause-aware-control");
	console.log("");
	console.log(failed ? "verify-pause-aware-control (baseline): FAIL" : "verify-pause-aware-control (baseline): PASS");
	process.exitCode = failed ? 1 : 0;
}
else {

// --- case A: a pause is active ------------------------------------------------
console.log("=== A: pause ACTIVE, deadline in the future ===");
const setAt = Date.now();
pause.setPause(setAt + 30 * 60_000, "verify-pause-aware-control");
// The file is rewritten with the pause's own record shape and a `since` twelve minutes
// back, so the aggregated line reports a realistic held time instead of the harness's
// own runtime. Only the timestamp moves: the record is the library's.
const heldSince = new Date(setAt - 12 * 60_000).toISOString();
writeFileSync(STATE, `${JSON.stringify({ paused: true, until: new Date(setAt + 30 * 60_000).toISOString(), since: heldSince, rev: 2, by: "verify-pause-aware-control" }, null, 2)}\n`);
console.log(`setPause(now+30m), pause holding since ${heldSince} -> ${JSON.stringify(pause.readPauseState())}`);
ok("the gate reports the pause as holding", control.pauseHoldsControlNotifications() === true);

const heldSignals = [];
for (const [runId, index] of RUNS) {
	for (let n = 0; n < 2; n++) {
		const event = quietEvent(runId, Date.now(), index);
		const notified = control.shouldNotifyControlEvent(control.DEFAULT_CONTROL_CONFIG, event);
		heldSignals.push([runId, notified, event.message]);
		console.log(`  ${runId} signal "${event.message}" -> shouldNotifyControlEvent=${notified}`);
	}
}
ok("no quiet-run signal notifies while the pause is active", heldSignals.every(([, notified]) => notified === false));
console.log(`  signals offered=${heldSignals.length} notified=${heldSignals.filter(([, n]) => n).length}`);
const whilePaused = control.takePauseSuppressedControlEvents(Date.now());
console.log(`  takePauseSuppressedControlEvents() while still paused -> ${JSON.stringify(whilePaused)}`);
ok("nothing is reported while the pause is still active", whilePaused.length === 0);
console.log("");

// --- case B: the pause is released --------------------------------------------
console.log("=== B: pause RELEASED ===");
pause.clearPause("verify-pause-aware-control");
console.log(`clearPause -> ${JSON.stringify(pause.readPauseState())}`);
ok("the gate reports the pause as over", control.pauseHoldsControlNotifications() === false);

const afterRelease = quietEvent("run-anja", Date.now(), 0);
console.log(`  a new quiet-run signal -> shouldNotifyControlEvent=${control.shouldNotifyControlEvent(control.DEFAULT_CONTROL_CONFIG, afterRelease)}`);
ok("the normal signal is back once the pause is over", control.shouldNotifyControlEvent(control.DEFAULT_CONTROL_CONFIG, afterRelease) === true);

const records = control.takePauseSuppressedControlEvents(Date.now());
console.log(`  takePauseSuppressedControlEvents() -> ${records.length} record(s)`);
for (const record of records) {
	console.log(`    ${JSON.stringify({ runId: record.runId, agent: record.agent, count: record.count, firstSignal: record.firstSignal, lastSignal: record.lastSignal, pauseSince: record.pauseSince, heldMs: record.heldMs, held: pause.formatDuration(record.heldMs) })}`);
	console.log(`    line: ${control.formatPauseSuppressionMessage(record)}`);
}
ok("one aggregated record per affected run", records.length === RUNS.length, `${records.length}/${RUNS.length}`);
ok("each record counts the signals held for that run", records.every((record) => record.count === 2));
ok("the aggregated reason is the pause reason", control.PAUSE_SUPPRESSION_REASON === "paused");
ok("each record carries the held duration", records.every((record) => Number.isFinite(record.heldMs) && record.heldMs >= 0));
const secondTake = control.takePauseSuppressedControlEvents(Date.now());
console.log(`  takePauseSuppressedControlEvents() again -> ${JSON.stringify(secondTake)}`);
ok("the records are taken once, not repeated", secondTake.length === 0);
console.log("");

// --- case C: no pause state file at all --------------------------------------
console.log("=== C: no pause state file ===");
rmSync(STATE, { force: true });
console.log(`state file exists -> ${existsSync(STATE)}`);
ok("the gate reports no pause", control.pauseHoldsControlNotifications() === false);
const noState = quietEvent("run-anja", Date.now(), 0);
const notifiedWithoutState = control.shouldNotifyControlEvent(control.DEFAULT_CONTROL_CONFIG, noState);
console.log(`  a quiet-run signal -> shouldNotifyControlEvent=${notifiedWithoutState}`);
ok("the signal notifies exactly as it does today", notifiedWithoutState === true);
const withoutState = control.takePauseSuppressedControlEvents(Date.now());
console.log(`  takePauseSuppressedControlEvents() -> ${JSON.stringify(withoutState)}`);
ok("nothing was suppressed to report", withoutState.length === 0);

console.log("");

// --- shipped bytes: the two flush call sites ---------------------------------
// Neither call site can be driven offline — the execution loop needs a live child run
// and the runner needs a detached one — so they are asserted on the shipped bytes, the
// way the display-label patch asserts its own un-drivable hop.
console.log("=== shipped bytes: the flush call sites ===");
const executionSource = readFileSync(`${PKG}/src/runs/foreground/execution.js`, "utf8");
const runnerSource = readFileSync(`${PKG}/src/runs/background/subagent-runner.js`, "utf8");
const controlSource = readFileSync(`${PKG}/src/runs/shared/subagent-control.js`, "utf8");
ok("the foreground execution loop reports the held signals per tick",
	executionSource.includes("reportPauseSuppressedControlEvents(now);"));
ok("the async runner writes the aggregate into the run's own event log",
	runnerSource.includes("appendControlEvent(buildControlEvent(omitUndefinedProperties({") && runnerSource.includes("for (const record of takePauseSuppressedControlEvents(now))") && runnerSource.includes("reason: PAUSE_SUPPRESSION_REASON"));
ok("the pause gate reads the shared library rather than re-parsing its file",
	controlSource.includes("createRequire(import.meta.url)") && controlSource.includes("lib.isPauseActive(lib.readPauseState())"));

console.log("");
console.log(failed ? "verify-pause-aware-control: FAIL" : "verify-pause-aware-control: PASS");
process.exitCode = failed ? 1 : 0;
}
