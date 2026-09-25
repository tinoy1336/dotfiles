// Check the INSTALLED @tinoy/pi-deepseek-cost label functions.
//
// The subject is the installed copy in place, not the repository source: node's
// --experimental-strip-types refuses a file whose real path is under node_modules, so the
// module is loaded through jiti — the loader pi itself uses — rather than by path import.
//
// No pi session, no model, no network: the label helpers take the instant they price.
// Exit 0 = every case matched, 1 = a case failed.
import { createJiti } from "/home/tinoy/.pi/agent/npm/node_modules/jiti/lib/jiti.mjs";

const INSTALLED = "/home/tinoy/.pi/agent/npm/node_modules/@tinoy/pi-deepseek-cost/index.ts";
const jiti = createJiti(import.meta.url, { moduleCache: false });
const mod = await jiti.import(INSTALLED);

/** Beijing wall clock → instant (Asia/Shanghai is a fixed UTC+8, no daylight saving). */
const bjt = (y, mo, d, h, mi, s = 0) => new Date(Date.UTC(y, mo - 1, d, h, mi, s) - 8 * 3_600_000);

// Each instant is chosen relative to a weekday boundary the tariff window ends at:
// 09:00, 12:00, 14:00 or 18:00 Beijing time.
const cases = [
	["day + hours", "valley", bjt(2026, 6, 7, 6, 0), "1d 3h"],
	["hours + minutes under a day", "valley", bjt(2026, 6, 7, 21, 55), "11h 5m"],
	["minutes + seconds", "valley", bjt(2026, 6, 8, 8, 6, 56), "53m 4s"],
	["seconds alone under a minute", "valley", bjt(2026, 6, 8, 8, 59, 22), "38s"],
	["second unit zero (days)", "valley", bjt(2026, 6, 6, 9, 0), "2d"],
	["second unit zero (hours)", "valley", bjt(2026, 6, 8, 4, 0), "5h"],
	["second unit zero (minutes)", "valley", bjt(2026, 6, 8, 8, 59, 0), "1m"],
	["one hour, zero minutes, five seconds", "peak", bjt(2026, 6, 8, 10, 59, 55), "1h 5s"],
];

let failed = 0;
process.stdout.write(`installed module: ${INSTALLED}\n`);
process.stdout.write("loaded through jiti (the loader pi uses)\n\n");
process.stdout.write("result  shape                              window   label       field          expected\n");
for (const [name, window_, at, want] of cases) {
	const label = mod.remainingLabel(at);
	const field = mod.windowLabel(window_, at);
	const ok = label === want;
	if (!ok) failed++;
	process.stdout.write(
		`${ok ? "PASS" : "FAIL"}    ${name.padEnd(35)} ${window_.padEnd(8)} ${JSON.stringify(label).padEnd(11)} ${JSON.stringify(field).padEnd(14)} ${JSON.stringify(want)}\n`,
	);
}
process.stdout.write(
	failed === 0
		? `\nALL ${cases.length} INSTALLED-COPY CASES PASSED\n`
		: `\n${failed} INSTALLED-COPY CASES FAILED\n`,
);
process.exit(failed === 0 ? 0 : 1);
