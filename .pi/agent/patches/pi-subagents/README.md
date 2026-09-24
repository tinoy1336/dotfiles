# pi-subagents display-name patch

Shows a caller-supplied name in the async-agents status rows instead of the child
agent type. The foreman fleet passes its crew name (`alice`, `bob`, …) as the spawn
`label`; without this patch every crew row reads `worker`.

Files touched: `src/extension/schemas.js`, `src/runs/foreground/subagent-executor.js`,
`src/runs/background/async-execution.js`, `src/tui/render.js`. Nothing else in the
package changes.

## What each hunk does

1. `src/extension/schemas.js` — declares the top-level `label` spawn parameter
   (string, display-only). Previously `label` existed only for parallel tasks,
   sequential templates and chain steps, so a plain single spawn had no way to
   name its run.
2. `src/runs/foreground/subagent-executor.js` — declares `label` on
   `SubagentParamsLike` and forwards it from the single async spawn call site
   (`runAsyncPath`) into `executeAsyncSingle`. Without this hop the spawn param
   died at the executor boundary: the fleet sent a label and nothing downstream
   ever saw it.
3. `src/runs/background/async-execution.js` — declares `label` on
   `AsyncSingleParams`, derives `displayLabel` once at the spawn site, and puts it
   on the step of the launch config the child runner is started from as well as on
   the initial status step written to `status.json`. Both are needed: the child
   rebuilds every status step from that launch config (`step.label`, see hunk 4's
   counterpart in `subagent-runner.ts:2038`), so the pre-write alone is overwritten
   by the child's first status write moments later.
4. `src/tui/render.js` — adds `singleChildDisplayLabel(job)` and consults it from
   `widgetJobName` (the row label of the async-agents panel, `render.ts:2935` via
   `appendJob`) and from `singleChildAgentName` (the single-job and child-row
   paths). Only a plain single-mode run with one step is affected; parallel and
   chain rows keep their own `parallel` / `chain` naming.

`step.label` itself is not new: the status types already carry it
(`src/shared/types.ts`, the `steps` array of `AsyncRunSummary` and `AsyncStatus`),
`runStatusStepDisplayName` already prints `label (agent)`, and `job.steps` reach
the widget through `summaryToJob`, which spreads each step
(`src/runs/background/async-job-tracker.ts`). The patch supplies the missing
transfer: spawn parameter → executor → launch step → child status → row label.

## Applied automatically

`apply-patches.sh` in the directory above keeps this patch applied. Its systemd user units
`pi-patch-apply.path` (fires when the npm package tree is rewritten) and
`pi-patch-apply.service` (`WantedBy=default.target`, so it also runs at login) are the
trigger; the entry for this patch is in `../managed-patches.conf` and the mechanism is
described in `../README.md`.

Failure behaviour: the applier never applies anything after a failed dry run. When the
target has moved so the hunks no longer match exactly (`--fuzz=0` is required), it appends
the dry-run output to `../apply.log`, writes `../FAILED`, sends a critical notification and
exits non-zero, which leaves the systemd run as a failed unit. The package is left
byte-identical: a patch is only ever applied to copies in a staging directory, and each
patched copy is renamed over its original afterwards.

## Apply by hand

npm overwrites the package directory, so the patch has to be re-applied:

    patch -p1 -d /home/tinoy/.pi/agent/npm/node_modules/pi-subagents < /home/tinoy/.pi/agent/patches/pi-subagents/label-display-name.patch

`pre-patch/` holds byte-identical copies of the four targets, one set per package version
(`schemas.js.0.71.0`, `subagent-executor.js.0.71.0`, `async-execution.js.0.71.0`,
`render.js.0.71.0` for the installed version, whose sources are compiled `.js`; the
0.68.0 `.ts` copies are kept for the older layout) plus the superseded patch text
(`label-display-name.patch.pre-rebase`). To revert a half-applied patch, either
`patch -p1 -R` with this patch or copy the pre-patch files back over the package
files.

## Is it applied?

    grep -c 'Optional user-facing display name' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/extension/schemas.js
    grep -c 'label: params.label.trim()'       /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/foreground/subagent-executor.js
    grep -c 'displayLabel ? { label: displayLabel }' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/background/async-execution.js
    grep -c 'singleChildDisplayLabel'          /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/tui/render.js

`1` / `1` / `2` / `3` = applied (the render count is the definition plus two call
sites, the async-execution count is the launch step and the initial status step).
A dry run confirms it, and the two directions read differently:

    patch -p1 --dry-run    -d <pkg> < <patch>   # "Reversed (or previously applied) patch detected!" = applied
    patch -p1 --dry-run -R -d <pkg> < <patch>   # "Unreversed patch detected!" = not applied

## Offline check (no pi session, no model)

    cd /home/tinoy/.pi/agent/npm/node_modules/pi-subagents && node /home/tinoy/.pi/agent/patches/pi-subagents/verify-offline.mjs

Loads the patched source through jiti (the loader pi uses) and drives the real
widget line builder with synthetic job states: a labelled single run must be
labelled by its crew name, an unlabelled run must still show the agent type
(control), a parallel run must stay named `parallel`, and the spawn schema must
declare `label`. It also drives the fleet's own `spawnParams` (the envelope the
foreman's `hire`/`assign` sends) and asserts the crew name is on it, and asserts
on the shipped bytes that the executor's single-spawn call site forwards the
label — that hop cannot be driven offline without launching a real child runner.
Exit code 0 = pass. Unset `PI_SUBAGENT_CHILD` when running this from inside a
subagent.

    node /home/tinoy/.pi/agent/patches/pi-subagents/verify-hire-injection.mjs

Drives the fleet tool's real `hire` path with a stub pi host (no model, no child
run) and asserts the task text the worker receives: the protocol line naming the
crew member and its scope, then the board-entry form carrying that same name.
The stub redirects HOME to a scratch directory first, because the mode file, the
roster and the claim roots are derived from HOME at module load — the real
foreman state is never touched. Exit code 0 = pass.

## When it takes effect

pi loads the package at session start, so the change appears in a NEW pi session.
The fleet side (`extensions/fleet/launch.ts` passes `label: binding.worker`) needs
no change.

## If a package update moves the code

Hunks 2 to 4 apply with offsets (a moved-context rebase, no edit needed). If
`schemas.ts`, `subagent-executor.ts` or `render.ts` changes shape, rebase rather
than hand-edit the package: copy the four files into a scratch `a/` and `b/` tree,
edit only the `b/` copies, regenerate with `diff -u --label a/<path> --label b/<path>
a/<path> b/<path>`, then `patch -p1 --dry-run` against the installed package,
update the probes above, and apply.

# pi-subagents worker-board-name patch

Gives the worker agent a standing instruction to attribute what it writes to the
shared todo board: every entry it creates or updates carries its own name first,
`<name>: <imperative subject>` — `delphine: extract the shared divider into
common/media`. The foreman crew writes one board from several workers, so an
unlabelled row says nothing about who owns it.

Files touched: `agents/worker.md`, in the `Working rules` list. That file is the
worker agent's definition (`systemPromptMode: replace`), so the rule is in the
agent's own prompt for every run, and the hire-time task line the `fleet` tool
prepends (`extensions/fleet/index.ts`, `prependProtocol`) spells the same form
out with the name the worker was actually hired under.

## Is it applied?

    grep -c '<name>: <imperative subject>' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/agents/worker.md

`1` = applied. `pre-patch/worker.md.0.68.0` is the packaged copy for rollback.

## If a package update moves the code

Rebase the same way as the display-name patch: put the pristine file in a scratch
`a/agents` tree and the edited copy in `b/agents`, regenerate with the same
`diff -u --label` form, dry-run it against the installed package, then apply.

# pi-subagents resume-label-forward patch

A warm-resumed crew member keeps its name in the async-agents rows. `fleet assign` and
`fleet review` resume a settled worker and send that worker's name as the resume `label`
(the spawn hop that puts a crew name on a row is the display-name patch). Two hops dropped it:

1. `src/extension/rpc.js` — the resume normaliser copied only `action`, `id|runId|dir`,
   `index`, `message` and `output` onto the executor params, so a resume request carrying
   `label: "carol"` reached the executor as `{action, id, index, message}`: the key was gone
   without a word, and the row fell back to the child agent type.
2. `src/runs/foreground/subagent-executor.js` — the revive call site (the `executeAsyncSingle`
   call built from the resolved resume target) forwarded no label, while the single-spawn call
   site forwards one. Without a label on the revived launch step the child derives its session
   name from the revived task text (`worker: [Read from: …] You are reviving a previous
   subagent conversation.…`) and the revived run renders bare.

Files touched: `src/extension/rpc.js`, `src/runs/foreground/subagent-executor.js`.

## Why the value comes from the caller and not from the resume target

`resolveAsyncResumeTarget` carries the source step's `sessionName`, agent, model, thinking,
runner and externalJob, but has no label of its own — the status row reads the step's `label`,
not its `sessionName`. Carrying the source step's label would therefore mean a new
`AsyncResumeTarget` field plus resolver plumbing, more than the hop that is missing. The
caller's label is also the current name for the revived run, and the fleet re-sends it on every
resume, so it is threaded through the same `executeAsyncSingle` parameter the spawn path uses.

## Apply by hand

npm overwrites the package directory, so the patch has to be re-applied:

    patch -p1 -d /home/tinoy/.pi/agent/npm/node_modules/pi-subagents < /home/tinoy/.pi/agent/patches/pi-subagents/resume-label-forward.patch

`pre-patch/rpc.js.0.71.0` and `pre-patch/subagent-executor.js.0.71.0` are byte-identical
copies of the two targets as packaged in the installed version (`pre-patch/rpc.ts.0.68.0`
and `pre-patch/subagent-executor.ts.0.68.0` cover the older `.ts` layout). The hunks sit far
from the display-name
patch's hunks and apply against both the packaged tree and the tree with the display patch
already applied (`--fuzz=0`, at most a line offset), so manifest order is not load-bearing.

## Is it applied?

    grep -c 'label: input.label.trim()'        /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/extension/rpc.js
    grep -c 'label: input.params.label.trim()' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/foreground/subagent-executor.js

`1` / `1` = applied — the normaliser hop and the revive hop.

## Offline check (no pi session, no model)

    cd /home/tinoy/.pi/agent/npm/node_modules/pi-subagents && node /home/tinoy/.pi/agent/patches/pi-subagents/verify-resume-label.mjs

Reads the resume envelopes out of the fleet extension, drives the installed RPC bridge through
jiti (the loader pi uses) with the envelope they build, and asserts the label comes back on the
executor params, with controls: an unlabelled resume stays unlabelled, a blank label is dropped,
and the revived run's params carry nothing beyond `action,id,index,label,message`. The hop after
the bridge starts a real child runner, so it is asserted on the shipped bytes instead — the
revive call site forwards the label. `PI_SUBAGENTS_PKG=<dir>` drives the same envelope through
another package tree; against a pre-patch tree it comes back without the label. Exit code 0 =
pass. Unset `PI_SUBAGENT_CHILD` when running this from inside a subagent.

## Self-test coverage

`../selftest.sh` scenario 2 mirrors every entry the manifest registers for the two managed
packages, so this patch's two targets are covered: the mirror's manifest is built from
`../managed-patches.conf` by redirecting only the package directory, its tree is seeded from the
`pre-patch/` copies, and the comparison covers `src/extension/rpc.js` and
`src/runs/foreground/subagent-executor.js` as well. A guard in that scenario fails, naming the
entry, when a registered patch is not mirrored — registering a patch for a package the scenario
does not mirror needs `MIRROR_ENTRIES`, the mirror tree and the comparison list extended there.

## When it takes effect

pi loads the package at session start, so the change appears in a NEW pi session. This patch is
registered in `../managed-patches.conf`, so `apply-patches.sh` restores it after a package
rewrite.

# pi-subagents pause-aware-control patch

A machine-wide pause stops being reported as several hung runs. `pause.ts` parks every
session's agent loop through the shared pause library (`$XDG_RUNTIME_DIR/pi-pause.json`,
`extensions/lib/pause-state.ts`), so a child that is running when the pause is set produces no
activity at all until the pause ends. The control watchdog measures inactivity, so every parked
run crossed `needsAttentionAfterMs` and emitted its own
`<agent> needs attention (no observed activity for N s)` — several at once — and a supervising
session read one deliberate pause as three stuck workers.

Files touched: `src/runs/shared/subagent-control.js`, `src/runs/foreground/execution.js`,
`src/runs/background/subagent-runner.js`.

## What each hunk does

1. `src/runs/shared/subagent-control.js` — the pause gate itself, plus the ONE gate in
   `shouldNotifyControlEvent`. That function is already the single decision every control
   signal passes in both processes: `execution.js`'s `emitControlEvent` calls it first, and the
   runner's `appendControlEvent` reaches it through `claimControlNotification`, so a suppressed
   signal is neither delivered to the parent nor written to a run's `events.jsonl`. While a
   pause is active the gate returns false — for the inactivity signal and for
   `active_long_running`, which a pause inflates for the same reason — and counts the signal per
   run instead. The pause is read THROUGH its owner, never re-parsed: `readPauseState()`,
   `isPauseActive()` and `formatDuration()` are the pause library's own, loaded lazily through
   `createRequire` and failing open (an unreachable library or an unreadable state file reads as
   "not paused", so a failure can only under-suppress, never hide a real hang).
2. `src/runs/foreground/execution.js` — the foreground execution loop takes the counts once the
   pause is over and emits ONE aggregated `needs_attention` event per affected run through its
   own `emitControlEvent`, so the notice and the intercom message come out of the same channel
   as before.
3. `src/runs/background/subagent-runner.js` — the detached runner does the same through
   `appendControlEvent`, which writes the aggregate into that run's own `events.jsonl`. The
   record carries `reason: "paused"` and a message naming the count and the held time, so the
   run's own state log says why it went quiet and the parent's tracker relays it to the
   supervising session through the normal control-notice path.

Both flush points sit in the activity tick the two loops already run
(`updateActivityState` / `updateRunnerActivityState`, 1 s interval), so a pause that ENDS is
noticed on the next tick of the process that owns the run. A pause that BEGINS needs no
watcher: every signal decision reads the state file, so the first signal of a paused run is
suppressed as soon as the pause exists.

## Is it applied?

    grep -cF 'suppressControlNotifyWhilePaused(event)' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/shared/subagent-control.js
    grep -cF 'was parked by a machine pause, not hung'  /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/shared/subagent-control.js
    grep -cF 'reportPauseSuppressedControlEvents = (now) =>' /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/foreground/execution.js
    grep -cF 'reason: PAUSE_SUPPRESSION_REASON'        /home/tinoy/.pi/agent/npm/node_modules/pi-subagents/src/runs/background/subagent-runner.js

`2` / `1` / `1` / `1` = applied (the first marker counts the gate and its call site).

## Offline check (no pi session, no model, no real pause)

    cd /home/tinoy/.pi/agent/npm/node_modules/pi-subagents && node /home/tinoy/.pi/agent/patches/pi-subagents/verify-pause-aware-control.mjs

Loads the patched source through jiti (the loader pi uses) and drives the real
`shouldNotifyControlEvent` with synthetic quiet-run events while a SCRATCH pause state file is
active, released and absent (`PI_PAUSE_STATE`), driven through the pause library's own
`setPause`/`clearPause` — no machine-wide pause is started and no live session is parked. It
asserts: every signal of three parked runs is held back (0 of 6 notify) and nothing is reported
while the pause still holds; after release the normal signal returns and the held signals come
back as ONE record per run, each carrying the count and the held time; with no state file the
behaviour is exactly as before. The two flush call sites cannot be driven offline (one needs a
live child run, the other a detached runner), so they are asserted on the shipped bytes.

`PI_SUBAGENTS_PKG=<dir>` drives a pristine package tree: there the same events against the same
active pause notify 3 of 3 runs, which is the behaviour this patch replaces. Unset
`PI_SUBAGENT_CHILD` when running it from inside a subagent.

## When it takes effect

pi loads the package at session start, so the change appears in a NEW pi session; a session
already running keeps the module it loaded. This patch is registered in
`../managed-patches.conf`, so `apply-patches.sh` restores it after a package rewrite — its
markers name three files that the package already ships, so the applier needs no special case.
