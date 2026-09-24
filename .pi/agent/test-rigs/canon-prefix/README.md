# canon-prefix offline rig

Guards ONE invariant: an installed extension must produce **byte-identical
system prompts whether a run starts from a typed prompt or from an injected
message** (a wake), so the provider prefix `[system, tools, messages]` never
moves and a wake cannot re-bill the cached prefix.

Layout rationale: rigs live under `~/.pi/agent/test-rigs/<name>/` — a sibling of
`~/.pi/agent/extensions/`, which pi scans and loads into real sessions. Nothing
here is ambient; each rig is self-contained and named for the invariant it
guards.

## Offline (default, no provider tokens)

| file | what it drives |
| --- | --- |
| `harness.ts` | the seam package's pure helpers (`canonicalSystemPrompt`, `systemPromptSlot`) over every provider payload shape, then the real logger's miss/guard rows |
| `harness-hooks.ts` | canon's REAL `before_provider_request` hook wiring (typed, wake, anomaly, foreign shapes) |
| `freeze-harness.ts` | child-prompt-freeze's REAL child path + the real logger in one chain; also the launch-marker classification cases |
| `harness-chain.ts` | the composed seam: REAL canon hook **and** REAL prefix logger on one fake pi, in both handler orders |

All four import the **installed** modules from `~/.pi/agent/extensions/` (never a
copy) and derive the canon block at run time by firing the real
`before_agent_start` hook over the live store `~/.pi/agent/canon/canon.json`.
Canon itself is no longer a file in that directory: `loadCanon()` resolves the
installed package's entry under the agent dir's npm tree
(`<agent dir>/npm/node_modules/@tinoy/pi-canon/index.ts` — the file the settings
entry `npm:@tinoy/pi-canon` loads), and `loadSeam()` resolves the shared package
that owns the prompt seam (`canonicalSystemPrompt`, `systemPromptSlot`,
`PROMPT_APPEND_SEP`). A bare specifier cannot be used here: bare specifiers
resolve by walking up from the rig's own directory, and the agent's package tree
is reached through a sibling link, not an ancestor. There is no recorded fixture
to age — if the store cannot render a canon block, the rig aborts (exit 2) naming
the store instead of testing stale bytes.

## Session shape is declared, never inherited

Every case declares the launch shape it tests through `setSessionShape()`
(`rig.ts`), which clears all three session markers first: `PI_SUBAGENT` (the
pi-subagent wrapper), `PI_SUBAGENT_CHILD` (the pi-subagents async runner — every
crew worker's shape) and `PI_FOREMAN`. A crew worker shell exports
`PI_SUBAGENT_CHILD=1`, so without this a rig run from inside the crew was
classified as a child and silently tested a different subject than the same rig
in a plain shell; `freeze-harness.ts`'s parent case failed outright, because it
neutralised only `PI_SUBAGENT`.

`harness.ts`, `harness-hooks.ts` and `harness-chain.ts` declare `parent`.
`freeze-harness.ts` declares it per case: `parent` (nothing registered),
`wrapper-child` (`PI_SUBAGENT=1`) and `async-child` (`PI_SUBAGENT_CHILD=1`), then
runs its child path in the `async-child` shape that a crew worker arrives
through.

A run needs no live pi and writes nothing under the real agent dir: the hook log
is resolve-hooked to the recorder (both the tree's `lib/hook-log.ts` and the
package copy the canon package imports), the cache-prefix log goes to this run's
own dir, and the store is read-only. To point the rig at a scratch agent
directory anyway, give that directory `extensions/`, `npm/` and `canon/`
(symlinks are enough) and run with `PI_CODING_AGENT_DIR=<scratch>`.

Run (from anywhere; paths resolve from the harness):

```sh
node --experimental-strip-types ~/.pi/agent/test-rigs/canon-prefix/harness.ts
node --experimental-strip-types ~/.pi/agent/test-rigs/canon-prefix/harness-hooks.ts
node --experimental-strip-types ~/.pi/agent/test-rigs/canon-prefix/freeze-harness.ts
node --experimental-strip-types ~/.pi/agent/test-rigs/canon-prefix/harness-chain.ts
```

PASS = exit **0** and a final `ALL … CHECKS PASSED` line. Each run writes its
own stamped artifact dir `runs/<ISO-stamp>-<pid>/` (logger rows, hook-log,
`result.txt`), so a re-run is never confused with the previous run. The rig
never writes the user's real hook log or cache-prefix log.

Negative controls: every harness should be able to FAIL. Add `RIG_MUTATE=<name>`:
`harness.ts` `no-append`, `harness-hooks.ts` `stale-block`,
`freeze-harness.ts` `no-restore`, `harness-chain.ts` `no-canon`. A mutated run
must exit non-zero.

```sh
RIG_MUTATE=no-canon node --experimental-strip-types ~/.pi/agent/test-rigs/canon-prefix/harness-chain.ts   # exit 1
```

## Cost-bearing (opt-in only): `live/`

`live/run-leg.py` launches a real pi process and makes real provider requests.
`live/wake-probe.ts` and `live/rewrite-emulation.ts` are extensions that driver
loads. These are **never** run by the offline suite; run them only when the true
process path needs re-proving. Prior live-leg output is kept under
`live/evidence/` so a re-proof starts from a known baseline instead of a rebuild.

```sh
python3 ~/.pi/agent/test-rigs/canon-prefix/live/run-leg.py parent 2 \
  ~/.pi/agent/npm/node_modules/@tinoy/pi-canon/index.ts \
  ~/.pi/agent/npm/node_modules/@tinoy/pi-cache-prefix-log/index.ts \
  ~/.pi/agent/test-rigs/canon-prefix/live/wake-probe.ts
```

Every leg clears the inherited session markers before launching pi, so a leg
started from a crew worker shell is not read as a child by accident. `LEG_CHILD=1`
launches the child leg, and it sets `PI_SUBAGENT_CHILD=1` — the marker the
pi-subagents async runner sets — rather than the wrapper's `PI_SUBAGENT`.

## Residual limits

- The dispatcher is a fake pi: it approximates pi's real (unsorted) handler
  order and does not exercise pi's payload construction, session/branch,
  compaction, or provider serialization. The chain harness runs both orders to
  bound the ordering risk.
- `@earendil-works/pi-coding-agent` is bundled inside the pi binary (no
  importable dist), so it is resolve-shimmed to `pi-sdk-shim.mjs` (`defineTool`).
  Divergence from the bundled module is unverified. `lib/hook-log.ts`
  (observability only) is redirected to `hook-log-recorder.mjs`.
- The derived block reflects the shape the rig declares (see above) plus
  `PI_MODEL`/ctx.model. Canon renders its block once per process, so one rig run
  covers one audience only; a fork rendered for another model is covered by the
  stale/doubled `canonicalSystemPrompt` cases.
- A store that parses into a different but well-formed render still passes: the
  fixture is derived from the store at run time, so the rig rejects only a store
  that renders no `## Canon` block at all, not one whose entries changed.
- The live legs remain the authority for the real process path.

Extensions, `settings.json` and the canon store are read-only inputs; the rig
never edits them.
