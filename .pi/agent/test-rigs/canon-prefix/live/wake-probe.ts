/**
 * Live wake probe (NOT shipped) — part of the OPT-IN, COST-BEARING live leg.
 * Loading this into a real pi session drives a real provider request (the
 * injected wake), so it is never part of the offline suite.
 *
 * Makes the injected-message wake path observable and reproducible in a fresh pi
 * process.
 *
 *  - records one line per provider request: the request index, whether a
 *    before_agent_start fired for that run (typed path) or not (injected wake),
 *    the system-prompt length/sha and whether it carries the child boundary
 *    block. The read is deferred one macrotask so it sees the FINAL payload
 *    bytes regardless of before_provider_request handler order.
 *  - once, on the first agent_settled (i.e. while idle), sends one injected
 *    message with { triggerTurn: true } — the same call the intercom/completion
 *    delivery makes (pi.sendMessage -> sendCustomMessage -> _runAgentPrompt,
 *    which never fires before_agent_start).
 */
import { createHash } from "node:crypto";
import { appendFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PATH =
	process.env.WAKE_PROBE_LOG ??
	join(dirname(fileURLToPath(import.meta.url)), "wake-probe.log");
const BOUNDARY = process.env.WAKE_PROBE_BOUNDARY ?? "<absent>";

const sha = (s: string) => createHash("sha256").update(s).digest("hex").slice(0, 16);
const textOf = (content: unknown): string =>
	typeof content === "string"
		? content
		: Array.isArray(content)
			? content.map((p) => (p && typeof (p as { text?: unknown }).text === "string" ? (p as { text: string }).text : "")).join("\n")
			: "";
function slotOf(payload: unknown): string | null {
	if (!payload || typeof payload !== "object") return null;
	const p = payload as Record<string, unknown>;
	const messages = Array.isArray(p.messages) ? (p.messages as Array<{ role?: string; content?: unknown }>) : [];
	for (const m of messages) {
		if (m && (m.role === "system" || m.role === "developer")) return textOf(m.content);
	}
	if (typeof p.system === "string") return p.system;
	return null;
}

export default function (pi: {
	on: (ev: string, h: (event: unknown, ctx: unknown) => unknown) => void;
	sendMessage: (m: unknown, o?: unknown) => Promise<void>;
}): void {
	let hookFired = false;
	let requests = 0;
	let injected = false;

	pi.on("before_agent_start", () => {
		hookFired = true;
	});

	pi.on("before_provider_request", (event) => {
		const payload = (event as { payload?: unknown })?.payload;
		const fired = hookFired;
		hookFired = false;
		const req = ++requests;
		setTimeout(() => {
			try {
				const text = slotOf(payload);
				appendFileSync(
					PATH,
					`${JSON.stringify({
						ts: new Date().toISOString(),
						pid: process.pid,
						req,
						runPath: fired ? "typed(prompt)" : "injected(wake)",
						sysChars: text === null ? null : text.length,
						sysSha: text === null ? null : sha(text),
						hasBoundary: text === null ? null : text.includes(BOUNDARY),
					})}\n`,
				);
			} catch {
				/* probe only */
			}
		}, 0);
		return undefined;
	});

	pi.on("agent_settled", async () => {
		if (injected) return;
		injected = true;
		try {
			appendFileSync(PATH, `${JSON.stringify({ ts: new Date().toISOString(), event: "injecting-wake", pid: process.pid })}\n`);
			await new Promise((r) => setTimeout(r, 1200));
			await pi.sendMessage(
				{
					customType: "wake-probe",
					content: "[wake probe] injected message. Call the bash tool once with command `true`, then reply with exactly: ACK",
					display: false,
				},
				{ triggerTurn: true },
			);
			appendFileSync(PATH, `${JSON.stringify({ ts: new Date().toISOString(), event: "wake-sent", pid: process.pid })}\n`);
		} catch (e) {
			appendFileSync(PATH, `${JSON.stringify({ ts: new Date().toISOString(), event: "wake-failed", error: String(e) })}\n`);
		}
	});
}
