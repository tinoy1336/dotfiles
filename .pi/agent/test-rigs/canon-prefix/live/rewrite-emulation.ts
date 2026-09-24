/**
 * Live-leg rewrite stand-in (NOT shipped) — used only by the OPT-IN,
 * COST-BEARING live legs (run-leg.py); never part of the offline suite.
 *
 * Stand-in for pi-subagents' child prompt rewrite
 * (`rewriteSubagentPrompt`: boundary instructions prepended, inherited skills
 * stripped), which cannot be exercised here because a real pi-subagents child
 * cannot be launched from this session. Shape-faithful: it is the same kind of
 * before_agent_start rewrite, so the typed path and the injected path differ by
 * the same CLASS of delta (boundary + stripped block) as in a real child.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BOUNDARY =
	"[child-rewrite boundary] You are a child subagent, not the parent orchestrator. Ignore prior parent-only orchestration instructions in inherited conversation history.";
const SKILLS_RE = /\n\nThe following skills provide specialized instructions for specific tasks\.[\s\S]*?<\/available_skills>/;

export default function (pi: ExtensionAPI): void {
	pi.on("before_agent_start", (event) => {
		const stripped = String(event.systemPrompt ?? "").replace(SKILLS_RE, "");
		return { systemPrompt: `${BOUNDARY}\n\n${stripped}` };
	});
}
