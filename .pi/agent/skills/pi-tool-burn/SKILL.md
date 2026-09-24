---
name: pi-tool-burn
description: Analyzes pi session tool-result burn (bytes tools return into context = token cost) by week — repeat file reads, bash file-read bypasses, raw build dumps, ctx-tool adoption, command-guard enforcement. Use when the user asks about tool token usage, context burn, tool efficiency, or to verify optimization rules are working.
---

# pi Tool-Burn Report

Measures how many raw bytes pi tools returned into the conversation over a
period, finds waste patterns, and tracks whether the R1/R2 canon rules and
the `probe`/`build`/command-guard tooling are bending the curve.

## Run

```bash
pi-tool-burn-report          # last 30 days
pi-tool-burn-report 7        # last 7 days
```

Output is ~50 lines of tables — safe to run via bash directly.

## Interpretation

- **MB/day** is the headline. Baseline: 3.9 (peak W4 Aug 2026) → 1.3 (post-fix, Sep 2026).
- **readMB**: should stay low; a big number means repeat whole-file reads returned (check top files).
- **bashMB + bash>5KB**: should shrink as R1/R2 hold; growth means new bypass habits.
- **ctxCalls**: healthy and growing — ctx tools doing raw-byte work in the sandbox.
- **top repeat-read files**: anything >200 KB cumulative is a candidate for `ctx_index` (spec docs) or a staleness-cache rule.
- **command-guard blocks**: R1/R2 + RAW-INPUT hook enforcement counts (per rule prefix) — nonzero = rules catching real attempts.
- **subagent results**: should stay ~0.1 MB/week; growth means reviewers are dumping inline again.

## Scope

This skill REPORTS and RECOMMENDS — it never autonomously changes model behaviour, canon rules, extensions, or hooking. The only actions taken are: running the report, optionally sampling session logs for detail, and writing the dated report file.

## Follow-ups

These are findings to LIST as recommended steps in the report for the user to decide on — never execute them autonomously (no canon_add, no extension edits, no command-guard changes, no ctx_index-ing):

1. If bash burn grew: sample that period's bash commands (the report's first-words list shows what); recommend extending `~/.pi/agent/npm/node_modules/@tinoy/pi-command-guard/index.ts` segment rules if a pattern emerges.
2. If read burn grew: check repeat files; recommend `ctx_index` for them, or reviving the read-staleness-cache proposal (`~/pi-tool-optimization-report.md` T1).
3. Write findings to a dated report file (`~/pi-tool-burn-<date>.md`), render via preview_export, report key beats inline.
4. If a NEW durable waste pattern appears: describe it in the report with evidence and a proposed rule text — the USER decides whether it becomes a canon rule.
