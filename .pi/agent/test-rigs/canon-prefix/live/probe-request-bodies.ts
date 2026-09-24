/**
 * Live request-body probe (NOT shipped) — part of the OPT-IN, COST-BEARING live leg.
 * Loading this into a real pi session drives a real provider request, so it is never
 * part of the offline suite.
 *
 * Where `wake-probe.ts` records one line per request (length + hash + which run shape
 * produced it), this probe keeps the BYTES: every outgoing request body is written to
 * its own file, so two runs can be diffed rather than only compared by size. That is
 * what proves a claim like "the only difference is the `- subagents_enable:` line at
 * offset 1022" instead of inferring it from a length delta.
 *
 * Usage (from the parent README of this directory):
 *   PI_FOREMAN=1 pi --mode rpc --model <model> --thinking off \
 *     -e <this file>   # driven through a FIFO; see the section in README.md
 *
 *   BODY_PROBE_DIR=<dir>   where the bodies land (default: ./body-probe/)
 *
 * The bodies are SESSION DATA — they contain the whole system prompt, meaning the
 * canon block and any project context. Keep them on the machine; record lengths and
 * hashes in `evidence/`, never the bodies themselves.
 */
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = process.env.BODY_PROBE_DIR ?? join(dirname(fileURLToPath(import.meta.url)), "body-probe");

export default function (pi: any) {
	void pi;
	mkdirSync(DIR, { recursive: true });
	const original = globalThis.fetch;
	let n = 0;
	globalThis.fetch = async (input: any, init: any) => {
		try {
			const body = typeof init?.body === "string" ? init.body : null;
			if (body) {
				n += 1;
				writeFileSync(`${DIR}/req-${process.pid}-${String(n).padStart(2, "0")}.json`, body);
				let images = 0;
				let sysLen = -1;
				try {
					const parsed = JSON.parse(body);
					for (const m of parsed.messages ?? []) {
						const content = m?.content;
						if (Array.isArray(content)) {
							for (const part of content) {
								if (part?.type === "image" || part?.type === "image_url") images += 1;
							}
						}
					}
					const head = parsed.messages?.[0];
					const text =
						typeof head?.content === "string"
							? head.content
							: Array.isArray(head?.content)
								? head.content.map((p: { text?: string }) => p?.text ?? "").join("")
								: "";
					sysLen = text.length;
				} catch {
					/* observation only */
				}
				appendFileSync(
					`${DIR}/index.txt`,
					`${process.pid} req${n} bytes=${body.length} system=${sysLen} images=${images} ${new Date().toISOString()}\n`,
				);
			}
		} catch {
			/* observation only */
		}
		return original(input, init);
	};
}
