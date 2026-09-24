# fleet — the foreman crew tool

**Scope.** `fleet` is the crew tool for FOREMAN SESSIONS ONLY. Activation puts
the session on the fixed fourteen-tool foreman set, in which `fleet` replaces the
raw `subagent` tool, and it is the only sanctioned way a foreman starts, addresses
or retires a worker. A foreman session is started with the `~/.local/bin/pi-foreman`
launcher, which sets `PI_FOREMAN=1`; the extension arms the mode from that marker at
`session_start`. The behavioural contract — who routes what, when to hire, what to
report — is `section.ts`, the discipline injected into a foreman session; the skill
that used to hold a longer form is retired. This file documents the MACHINERY: what
the tool owns, what it refuses, and what breaks it.

The division is deliberate: the tool owns names, run handles, reuse timing,
ownership claims, non-author review and retirement state. The MODEL owns routing
decisions, task content, artifact choice, arbitration of a refused dispatch,
the fatigue trigger, and everything outside the crew.

## Files

| File | Role |
| --- | --- |
| `index.ts` | The `fleet` tool, the `foreman-off` escape command, lifecycle hooks, the completion handler |
| `items.ts` | The foreman's own item ledger: one file per session, one record per item |
| `mode.ts` | Foreman-mode state (one file per session), the fixed foreman tool set, and the tool-set transition |
| `section.ts` | The injected foreman section: its static text and `SECTION_VERSION` |
| `launch.ts` | The ONLY pi-subagents caller; the fixed launch envelope and the transport |
| `roster.ts` | The per-session crew record, name pool, claims, retention and foreign-file cleanup |
| `release.ts` | The ONE way a worker's claim is released: the roster row goes `retired` AND the guard's claim record is withdrawn by generation, so the two records that state ownership cannot disagree |
| `adopt.ts` | The handoff sheet and the adoption verb: sheet publication, predecessor liveness, the session-identity re-stamp, prefix/ reuse evidence |
| `board.ts` | Closing a retiring worker's open board rows: attribution, the scope match, the branch write and the live-view refresh — and the retire GUARD's read (`openRowsFor`), the worker's own still-open rows |
| `board.probe.ts` | Runnable probe for the board's pure rules and the guard's read: a pending row refuses, an in-progress row refuses, all-completed allows, another worker's open rows do not block, an unattributable row never blocks, and a refusal leaves the branch byte-identical. Loaded through `jiti` (board.ts imports the rpiv-todo package's TypeScript, which plain type-stripping refuses): `node board.probe.ts` |
| `status.ts` | Run-row normalisation, warm-reuse verdict (the window read from the agent directory in use), per-worker usage (spend, the CURRENT context fill read from the run's own transcript, the model window and the high-water mark), the fill's text rendering, failure-cause extraction, and the run-record fallback for runs this process did not start |
| `status.probe.ts` | Runnable probe for the fill/limit figures and the row's rendering: `node --experimental-strip-types status.probe.ts [worker…]` prints one row per worker plus `checked N, failed M` |
| `predicates.ts` | The pure rules: name shapes, glob overlap, claim sentinels, timeout range, review eligibility, retirement disposition, the gone-run evidence bar, the open-board-rows refusal, every refusal string |
| `predicates.probe.ts` | Runnable probe for the claim rules: the gone-run retirement disposition and the evidence bar for releasing a worker whose run is provably gone |
| `release.probe.ts` | Runnable probe for the release against a scratch HOME (`HOME=/tmp/… node --experimental-strip-types release.probe.ts`): the overlap check resolves the released paths, the guard record's generation moves, and a live worker's claim still refuses |
| `../test-rigs/fleet-assign.probe.ts` | Runnable probe for `assign`'s reuse decision, driven through the REAL fleet tool against a fixture crew, run-record root and fake owner under a scratch HOME: an absent record reaches the resume attempt (and its `no-session` answer marks the worker `not-resumable`, its success a `cold-resume`), an unreadable record, a row with no activity stamp and a missing run id each keep their own refusal, and a live row / a warm row are answered as before. `node ~/.pi/agent/test-rigs/fleet-assign.probe.ts` |
| `config.json` | `reuseWindowSeconds` — user-set, single owner |

## Cross-extension state

pi evaluates every extension in its OWN jiti instance (`dist/core/extensions/loader.js`,
`loadExtensionModule`, `moduleCache: false`), so one extension can never reach
another's module state by import: the import returns a different instance and the
write lands in a map nothing renders from, silently. Cross-extension state
therefore travels on the shared per-process event bus (`pi.events`) or the
session manager. `fleet` uses the bus for three things: the `canon:section`
handoff, the `subagents:rpc:v1:*` transport, and the `subagent:async-complete`
subscription.

## Activation and mode

- Entry is the `pi-foreman` launcher (`~/.local/bin/pi-foreman`), which exports
  `PI_FOREMAN=1` and hands pi the brief as its message argument. `session_start`
  reads that marker and arms the mode there, so the tool set and the injected
  section are in place before the session's first request. Typed prose never arms
  the mode, and the mode never self-activates on prompts that merely look like
  multi-step work.
- The marker is inherited by everything a foreman spawns, so the arm also requires
  `PI_SUBAGENT_CHILD !== "1"`: a foreman's worker is not a foreman.
- `/foreman-off` is the only mode command left. It is reserved, takes no argument,
  and does one thing: clear the section and call `mode.deactivate`, restoring the
  pre-activation array. It exists because a session whose mode file says ON re-arms
  on a plain `pi --continue` — the state an aborted handoff leaves behind — so
  without it that session would have no way out. The activation command, its
  `off`/`stand down` vocabulary and its brief forwarding are retired. A
  launcher-started session arms again regardless, because the marker is an
  explicit entry into the mode; the escape holds for plain `pi` sessions.
- State is one file per session, `~/.local/pi/foreman/roster/mode-<sessionId>.json`,
  stamped with its session id, so a second pi session can never disarm this one.
  It also records `restore`: the tool set that was active BEFORE activation.
- The transition is fail-safe ordered. Activate: apply the foreman set, THEN write
  the mode file — on a throw the previous set is put back and the mode forced OFF.
  Deactivate: restore the pre-activation set FIRST, then write OFF.
- `off` restores `restore` (minus `fleet`, plus `subagent`). With no saved set
  there is nothing to restore TO: the registered set is a superset this session
  never had and the active set is the foreman fourteen, so applying either would
  hand a deliberately restricted session a different array and re-bill it. `off`
  then writes OFF and leaves the array alone.
- Activation is refused outright when the `fleet` tool is not registered in this
  process: the session would become a foreman with no crew surface at all.
- The set applied is the intersection of the fixed foreman list with the tools
  actually REGISTERED in this process. An extension that is not loaded cannot
  supply its tool, and naming an absent tool would make the array depend on load
  order rather than on the list. Every tool left out is reported to the user, on
  every activation path.
- Activation does NOT probe the launch transport. The arm has to stay synchronous
  so the first request already carries the section, so a `PI_FOREMAN` launch on a
  machine without pi-subagents arms with the crew tool missing and reports it
  through the `act.missing` notice. `launch.ts` still exports `probeTransport`;
  nothing calls it.
- Every tool call re-reads the mode file, so `off` takes effect immediately.
- `session_start` arms a session whose own mode file says ON, or whose process
  carries `PI_FOREMAN=1` (without `PI_SUBAGENT_CHILD=1`). The section is set from
  the activation RESULT, never ahead of it; a session with neither signal has
  `fleet` removed from its active set and is otherwise untouched.
- `session_shutdown` deliberately does NOT clear the mode file. It fires on a
  plain quit AND on `/reload`, and that file is exactly what makes the
  `session_start` re-arm restore a foreman session after `--continue`; clearing it
  would resume the session on the default tool array, re-billing the whole
  conversation and silently dropping the mode. Retention is `pruneOld`'s job, and
  a mode file for a session that never returns is inert.
- Mode files older than 7 days are pruned; a live session's file always survives.

## The fixed foreman tool set

`mode.FOREMAN_TOOLS` is computed once, at activation, and never recomputed per
turn — the tool array precedes the messages in the cached prefix, so any later
change re-bills the remaining tools AND the whole conversation. Fourteen names,
in this order:

`fleet` · `read` · `image_read` · `todo` · `io_status` · `write` ·
`preview_export` · `ask_user_question` · `set_anchor` · `canon_add` ·
`canon_remove` · `canon_edit` · `subagent_supervisor` · `intercom`

The list is an ALLOWLIST: everything not named in it is absent from the session,
`subagent` and `bash` and `edit` and the `ctx_*` family and the web tools among
them, and so is `bg_wait` — a blocking call would leave the foreman unable to
receive a steer. The foreman routes work rather than performing it: `write` exists
only for its own handoffs and writeoffs, and `read` only to triage a worker that
died without a report. `image_read` is the image half of that triage — a
screenshot or a rendered frame a worker points at is read inline instead of being
described back in prose — and it sits directly after `read` so the two ingestion
tools stay adjacent. `todo` is board awareness first of all: the board belongs
to the workers, who create, complete and reword their own entries. The one
carve-out is tidying, and it happens only when the user asks — close a row whose
owner is retired or has gone cold past the reuse window and can never be woken to
close it, or mark a row superseded when another worker completed the same scope.
Never on the foreman's own initiative, never a row whose worker is still live, and
never a row invented for work about to be dispatched.

No tool in the set may gain or lose `promptSnippet`/`promptGuidelines`
mid-session: those live in the system prompt and would rebuild the frozen prefix.

## The injected section

`section.ts` holds `FOREMAN_SECTION`, the short operational discipline injected
into the system prompt while the mode is on, plus `SECTION_VERSION` — bumped when
the text changes, so a change is attributable in the cache log instead of
appearing as an anonymous miss. The section is the WHOLE of the operational
discipline — the skill and the `/foreman` command are both retired — so it is the
only foreman spec.

The text reaches canon, which owns the system-prompt tail, over the extension
event bus: `pi.events.emit("canon:section", { id: "foreman", text })`, with an
empty `text` clearing the section when the mode goes off. It is NOT appended from
`index.ts`: two normalizers that each strip and append would emit order-dependent
bytes, and one changed byte in the system prompt re-bills the tool array and the
whole conversation behind it.

Two properties the code depends on:

- **Static text.** The section is byte-identical on every request of a session —
  no worker names, counts, timestamps or elapsed times. Live state reaches the
  model through tool results, which sit after the cached prefix.
- **Synchronous handoff.** A bus handler's synchronous part runs before `emit`
  returns, so a section set at activation is already composed into the request
  that follows it.

## The frozen prefix

The provider prefix is `[system, tools, messages]`: the system prompt comes FIRST,
then the tool array, then the whole conversation, and caching is a byte-for-byte
prefix comparison. Any byte that moves inside the system prompt or the tool array
re-bills everything after it, which is why:

- the injected section is static text, present from request 1;
- the tool set is applied at `session_start`, before the session's first request;
- the only mode command left, `/foreman-off`, never applies the set, it only
  restores the pre-activation one;
- a session resumed with `--continue` re-arms through `session_start`, so the same
  bytes are produced on that path too.

An `off` is an accepted one-time re-bill; `/foreman-off` reports how many context
entries will be re-billed rather than leaving the user to find it in the footer.

## Launch transport

`launch.ts` is the only pi-subagents caller and speaks its documented in-process
event-bus RPC (`subagents:rpc:v1:request` / `:reply:<requestId>`). The envelope is
built in one place, `spawnParams`:

```
{ agent: "worker", task, context: "fresh", async: true, timeoutMs, label? }
```

- **Every launch is ASYNC and FRESH.** There is no fork path in the extension and
  no caller can express one.
- **A resume carries the worker's label.** `assign` and `review` send
  `label: <worker name>` on the owner's `resume` RPC, taken from the crew record
  the roster already holds, so a resumed run's envelope matches a hire's instead of
  being named from its task text. The installed owner does not forward a caller
  label on resume: its resume payload is normalised to `id`/`index`/`message` and
  the revived run's name is derived from the revived task, so a resumed row keeps
  the crew name only once the owner forwards the label. That hop is the owner's,
  not this extension's.
- **Async is load-bearing, not a preference.** Background children are separate
  processes that load the configured extensions, which is where `todo_parent`,
  the `ctx_*` tools, `image_read`, `nf` and the web tools come from. A FOREGROUND
  child runs inside the parent's process, loads none of them, and — because the
  `worker` agent's configuration declares those tools — pi refuses the launch
  outright rather than starting the worker without them. Do not "fix" a hang by
  switching launches to foreground: every hire would fail on its first line.
- Transport faults are three-valued and never conflated: `timeout` (nobody
  listening, or an owner that hung), `rejected` (an owner that answered and
  refused), `ok`. A client-side deadline deliberately does not claim to tell the
  first two apart.
- Default `timeoutMs` is 12 h. `predicates.clampTimeout` refuses anything below
  10 minutes (a mid-work kill loses the run) or above 24 hours.

## The fleet tool

One action-style tool, addressed by WORKER NAME. Passing a run id is refused
explicitly (`fleet addresses workers by NAME`). The foreman's item ledger is an
ACTION on this tool (`items`), not a tool of its own, because the tool array is
frozen at activation and a capability added mid-session would re-bill the whole
conversation.

**One crew action per turn.** A second `fleet` call in the same assistant message
is refused (`one fleet action per turn`). The guard counts assistant
`message_start` events, so a wake-delivered turn gets its own budget. Parallel
work is expressed as separate scopes, never as one batched call.

### Actions

- **roster** — reconciles and reports. Cleans up foreign crew files first, then
  flips states from the live rows (`retiring` → `retired` on a terminal row,
  `live`/`idle` → `completed`/`failed`/`stopped` from the run's real outcome),
  retries unresolved post-resume handles, closes the open board rows of every
  worker it settles as `retired`, and reports per worker: state, scope,
  `idleSeconds` (null = unknown), `spentTokens`, `context` (`553k/1.0M (55.3%)` —
  the CURRENT fill), `contextFill`/`contextLimit` (the two numbers behind it),
  `contextHighWater` (the peak), `fatigue`/`fatigueBasis`, claims,
  `authored`, `reportPath`, `failure`, `notResumableReason`, `nextLegalActions`,
  plus two reads a successor lives on: `lastRun` — the worker's LAST run as
  `{runId, state, endedAt, endedAtIso, outputFile, artifactsDir, artifactNote}`, or
  `lastRun: null` with `lastRunUnavailable` naming why no run record resolves — and,
  for a worker this session ADOPTED, `landedSincePublish` (Successor reads below).
- **hire** — needs `scope` (one coherent slice), a claim declaration, valid
  `artifacts` (each must exist as a FILE) and valid task text. Allocates the next
  unused pool name unless one is given. The protocol line is prepended by the
  tool, never written by the caller, and the caller's task shape is validated
  BEFORE the prepend. A caller-supplied `name` is honoured or refused, never
  silently replaced, in two stages: an id-shaped name is refused first (`fleet
  addresses workers by NAME`), then a name that does not satisfy
  `predicates.isNameLike` — lowercase letters, digits and `-`, at most 32
  characters, starting with a letter — is refused with
  `predicates.notANameMessage`, which carries the rule itself. The shape matters
  beyond tidiness: a name is also the worker's handoff filename component
  (`~/.local/pi/foreman/handoffs/<name>.md`), so a `/`, a space, an uppercase
  letter, `..` or a `.md` suffix in a name is a PATH, not an identifier. The
  refusal is a refusal — an invalid name is never silently replaced by a pool
  name. A name the crew already holds is refused too, because ONE name
  addresses ONE worker — two entries under one name leave the second addressable
  only by the accident of which entry `find` reaches first, while reviews,
  steering, claims and the board all key on the name. A retired or handed-off
  record KEEPS its name, so the refusal points at a different name (or at
  omitting `name`) instead of at a retire-then-rehire loop that would refuse
  again. `adopt` enforces the same rule for a sheet member whose name the
  successor already holds.
- **assign** — resumes the SAME worker. Requires `scope` to equal the worker's
  hired scope (a different scope means `hire`). Refuses when the worker is live
  (steer instead), when its run id is missing (the identity cannot be resolved),
  when a run record exists but cannot be read, when the row carries no activity
  stamp, or when it is past the reuse window. A run with NO record is not refused:
  absence is no evidence of a live run, so the resume is attempted and its answer
  decides — the owner replaying the run reports the reuse as `cold-resume`. A
  `no-session` resume failure marks the worker `not-resumable`; a busy or unknown
  refusal is NOT a verdict about the worker and leaves its state untouched. A
  resume revives into a NEW async run, so the
  handle is adopted before anything else can address the dead one. The resume
  request carries `label` = the worker's name, exactly as `hire`'s spawn envelope
  does (see Launch transport for the owner-side limit on that label).
- **steer** — guidance, corrections, priorities. `delivery` is `auto` (default),
  `steer` or `follow_up`. A receipt proves delivery only: the effect is confirmed
  on the next wake. Refuses on a `retiring`/`retired`/`failed`/`stopped` worker.
- **retire** — a state transition, never an instant kill. REFUSES while the
  worker still owns open board rows (the board guard below), then reconciles the
  run: a run that has already finished retires as a plain transition and
  writes NO handoff, because a dead run cannot write one. Otherwise the worker
  goes `retiring` and the clock-out steer is sent; it flips to `retired` on
  `CLOCKED OUT`, on the completion event, or on the next status reconcile. A
  failed steer leaves it `retiring`, and re-running `retire` settles it. Every
  path that settles a worker `retired` also closes that worker's open board rows
  (see The board closure below); a worker still `retiring` has not stopped, so its
  rows are untouched until it settles.
- **review** — independent review. Never spawns a fresh worker; picks a warm,
  SETTLED, non-author crew member. A named reviewer is validated against
  authorship BEFORE any resolve. Authorship is decided by declared scope and
  `owns`, and by a target that merely NAMES the worker (a prose target must not
  smuggle the author past the rule). A live worker is refused as a reviewer: a
  running child is steered, never resumed.
- **items** — the foreman's own ledger, one file per session at
  `~/.local/pi/foreman/items-<sessionId>.json`, ids `itm-<n>`. It is NOT the todo
  board: the board is the workers' own record, rebuilt from the session branch,
  while the ledger is the foreman's working memory and survives a compaction and
  a resume. `op` is `add` (needs `itemText` and `scope`; `owns`/`exclusive` go
  through the same predicates the launch path uses, so the ledger cannot record a
  claim a hire would refuse), `update` (needs `item`; an explicit empty string
  clears `artifact`/`name`), or `list` (optional `state` filter). States are
  `queued` · `live` · `done` · `failed` — `live` means work has started.
- **handoff** — publishes this session's crew so a SUCCESSOR session can take it
  over. Writes one adoption sheet per handoff under `~/.local/pi/foreman/adopt/`
  plus a `current.json` pointer naming the handoff in flight, then flips every
  worker to `handed-off` (withdrawn by publication, not deleted). Nothing is
  signalled, resumed or restarted: each worker keeps running in its own detached
  session and the sheet carries the run ids the successor will address. Refuses
  when there is no crew. Returns `ok: false` when this process's own kernel start
  identity could not be read, because then no successor can prove it left.
- **adopt** — takes a published crew over. `from` is `"current"` (the pointer,
  the default), a predecessor session id, or a sheet file name. See the handoff
  section below for the refusals and what each worker state means.

## Claims and rails

`owns` and `exclusive` are both required at hire and assign, and both accept the
sentinel `["none"]` meaning "this task writes / holds nothing". The sentinel may
stand alone; mixing it with real tokens is refused. `exclusive` tokens are stored
as `exclusive:<token>` and are single-holder.

Overlap is exact match, directory prefix, or a `*` glob on either side. A
conflict is refused with the holder and the claim's age. Claims release when a
worker is `retired`, `completed`, `not-resumable` or `handed-off` — publication is
how the outgoing foreman withdraws a claim, and the successor re-publishes the same
claim under its own session when it adopts. `roster.holdsClaim` is the ONE spelling
of that rule, so a reader deciding whether a worker still owns its paths (the
gone-run pass below) cannot drift from this check.

**Ownership is TWO records, and a release moves both.** This overlap check reads
the ROSTER; the guard authorises a worker's own writes from `io/claims/<worker>.json`
and pins its generation fence there. `io_status reclaim` moves only the second: it
refuses a still-running worker's next write and does NOT free the paths for the next
hire — ownership comes off through `release.ts`, which is what `retire` calls and
what the gone-run pass calls.

**A run the machine destroyed is released automatically.** A reboot kills the
detached crew with it: the process is gone, the run record died with the temp root
it lived in, and the owner answers `No async run found` to every steer. Such a
worker's paths were refused to every hire, and nothing could settle it — the row
reconcile has no row to read, and `retire` could not deliver a clock-out.
`releaseGoneRuns` (`index.ts`) runs before this overlap check at `hire` and `assign`
and inside `roster`, releasing a worker whose run is PROVABLY gone:
`predicates.runProvablyGone` requires no row for its handle lineage, no surviving
run record, a verified handle, and no process holding its identity
(`identity.identityClaimLive`). Ambiguity is never released, and the release is
logged (`source: fleet`, `kind: claim-released-run-gone`).

## The reuse window

`config.json` holds `reuseWindowSeconds` and carries its own note: the value is
user-set and MUST NOT appear as a literal in code, refusal text, tests or a spec.
Read it through `status.loadWindowMs()`.

The file is resolved through the AGENT DIRECTORY IN USE —
`$PI_CODING_AGENT_DIR/extensions/fleet/config.json` when pi was pointed at one,
`$HOME/.pi/agent/extensions/fleet/config.json` otherwise — the same resolution pi
uses for its own agent paths. A session running out of a copied agent directory
therefore reads the config that directory holds rather than the one under `$HOME`.

A config that cannot be read returns 0, which is the fail-closed direction and not
a window any caller can act on: EVERY settled worker measures as outside it, so the
failure is logged instead of swallowed — one hook-log row per config path per
process (`source: fleet`, `kind: reuse-window-unreadable`, carrying the path and
the cause). `retire.ts` reads the same file and refuses outright, naming the file
in its own log; neither module substitutes a window of its own.

`warmCheck` returns one of `warm` (inside the window), `past-window` (outside —
`assign` refuses: the context is no longer warm), `live` (queued/running/pending —
steer, do not resume), `no-record` (no row in any source: the run's record is
absent — `assign` attempts the resume and reports the reuse as `cold-resume`), or
`no-activity` (a row exists with no activity stamp — nothing about the run can be
measured, so it is treated as live and no resume is performed).

The owner's status snapshot is its own in-memory view and covers only the runs THIS
process started, so an adopted crew has no row in it at all. `statusRows()` therefore
falls back to the run's own record (`status.rowFromRunRecord`) for any crew member the
snapshot does not report, and decides liveness from the record's pid rather than from
its word — a record left saying `running` by a process that has died reads as settled.
Without that fallback an adopted worker has no row at all (`no-record`), and the
run's own record is the only thing that can say whether it is still warm.

This window is a SEPARATE clock from the provider's prompt-cache lifetime, and
both clocks are OPERATOR ASSUMPTIONS rather than vendor facts: the window is
`config.json`'s `reuseWindowSeconds`, the floor on the lifetime is `retire.ts`'s
`PROVIDER_CACHE_FLOOR_MS`, and no literal for either is restated here. An
assumption set too generously fails as a resume attempted on a context the
provider has already dropped — paid as a re-read of the whole context at miss
price, not argued away. The two clocks must never be conflated, and no decision
may rest on an assumed TTL for the provider's cache.

## Worker state machine

`live` · `idle` · `retiring` · `retired` · `completed` · `failed` · `stopped` ·
`not-resumable` · `handed-off`.

`handed-off` is terminal for the session that published the worker: `steer`,
`assign` and `retire` refuse, no reconcile rewrites the state, and its completion
event is ignored — the crew belongs to the successor. A successor's roster record
carries `adoptedFrom` naming the sheet it came from, which is how a reader can tell
an adopted worker from a hired one.

`failed` and `stopped` are terminal and DISTINCT from `completed` — the roster
must speak the same word the run's own outcome does, never a rounded-up success.
The transition OUT of a claiming state into `retired` goes through `release.ts`:
`retire`, the row reconcile that settles a finished run, and the gone-run pass all
move the guard's record with the roster row, so paths free to hire are free of the
write fence too.
`handleUnverified` marks a worker whose post-resume run id could not be
reconciled: `steer` and `retire` then REFUSE rather than aim at the dead
pre-resume run, and `roster` retries the reconcile.

`nextLegalActions` is computed from the state: `retired` → roster/hire;
`handed-off` → roster/hire/handoff; `retiring` → retire/roster/hire;
`not-resumable` → retire/roster/hire; `completed`/`failed`/`stopped` →
retire/roster; otherwise assign/steer/retire/roster. Every settled state that
still holds rows lists `retire`, because that is the action which settles it —
but the BOARD GUARD still applies: a settled worker with an open row is refused
until the row is completed (or closed by the foreman), and `retire` is what
closes the rows that remain after that.

## Storage and retention

Crew records live at `~/.local/pi/foreman/roster/<sessionId>.json` (roster
version 2), written atomically (temp + rename). A file whose session stamp does
not match is invisible to reads — another session's crew is unaddressable, not
adoptable — and is removed by `cleanupForeign` unless that session still holds
foreman mode ON. Retention prunes to the newest 20 files and drops anything older
than 7 days, at process start.

`~/.local/pi/foreman/adopt/` is deliberately OUTSIDE both walks: `cleanupForeign`
and `prune` never enter it, so a published crew outlives the predecessor's roster
file (which `cleanupForeign` will remove as soon as that session's mode file goes
OFF). Sheets are never deleted by `fleet`; only the `current.json` pointer is,
last, once a crew has been adopted.

## Crew handoff and adoption (`adopt.ts`)

The roster is per-session on purpose, so a crew crosses sessions as a PUBLISHED
sheet, never as a readable roster. `handoff` writes
`~/.local/pi/foreman/adopt/<iso>-<predecessorSessionId>.json` — the predecessor's
identity (session id, the session FILE path pi-subagents stamps on a run, pid,
kernel start identity, host) plus one record per worker: name, scope, state, run
id, every run id, child index, own/exclusive claims, hire and activity stamps,
report path, failure, the child's session file, the run's `status.json` path, the
worker's prefix fingerprint (`sys`, `tools`, `nTools`, `prefixChars`) from the
house cache log, and `outcome` — the state, end time and artifact locations that
worker's last run had left when the sheet was written (null when its record carried
none). A `current.json` pointer names the handoff in flight.

`adopt` refuses, in this order:

1. no pointer and no `from` → the sheets on disk are listed, so the refusal names
the available handoffs;
2. a sheet that is unreadable, malformed, or from another sheet version;
3. `from` naming no sheet, or matching more than one;
4. the successor being the sheet's own predecessor (a session adopts a crew it did
   not publish);
5. **the predecessor being still alive**, and equally a predecessor that cannot be
   proved gone (different host, or no pid / start identity on the sheet). Liveness
   is the same proof the session lease uses — same host, pid present, kernel start
   ticks matching — so a stopped-but-present predecessor is ALIVE. An `alive` verdict
   is WAITED ON first: `adopt.waitForPredecessor` re-reads the proof at a 1 s first
   interval with a 1.5× backoff capped at 8 s, for `WAIT_CEILING_MS` (105 s) or
   `WAIT_MAX_POLLS` reads (200 — the bound that holds when a sleep does not advance
   the clock), then refuses. A successor is normally opened while the predecessor is
   finishing its last reply, so this is what turns an early arrival into a working
   adoption; the ceiling is deliberately far below the predecessor's own run
   timeouts, because the wait exists to make an early arrival productive, not to
   outlast a working foreman. Parking there is safe by construction: the liveness
   test is one `/proc/<pid>/stat` read and EVERY mutation of the lifecycle — the
   sheet stamp, the roster write, the claim re-bind, the pointer deletion — is after
   the verdict, so the wait writes nothing, signals no worker, restarts nothing and
   resumes nothing. An `unknown` verdict is never waited on: it fails closed at once.
   The refusal names the wait and its result. Refusals 1-5 leave the sheet and the
   pointer untouched.

Then, per worker:

- **no run record at the sheet's run id** → refused individually with the path it
  looked for ("the fleet cannot resolve this run"); the other crew members are
  still adopted, and the refusal is reported under `unresolved`.
- **a name that is not name-shaped** (`predicates.isNameLike`) → refused
  individually with `predicates.notANameMessage`, for the same reason `hire`
  refuses one: a sheet is evidence read from disk and may be hand-edited, and the
  member's name is the handoff filename component this session will key on;
- a name this session already holds → refused individually rather than merging two
  identities under one name;
- **live** (running / queued / pending) → adopted BY POINTER. It is not resumed, not
  restarted and not duplicated, and its status record is not written, because the
  running process owns that file. The successor addresses the same run id; a live
  worker is steered.
- **settled** → the parent-session identity is re-stamped on the run's record from
  the predecessor's string to the successor's. The re-stamp is guarded: it applies
  only when the record still carries the identity the sheet names, so it can never
  become a blanket rewrite of a run that belongs to another handoff, and a partial
  stamp (status present, result record different) is refused rather than half
  applied. `adopt.ts` is the ONE writer of a run record and writes exactly one
  field: `sessionId` — the field every pi-subagents cross-session guard compares.
  It also patches the run's staged result record and its run-index entry when they
  carry the field, because the resume path checks the result record's `sessionId`
  too.
- the successor's roster gains the worker with `adoptedFrom` naming the sheet, the
  claim record is re-published under the successor's session, and a settled worker
  gets its reuse report: the window verdict measured from the sheet's activity
  stamp against `config.json`'s `reuseWindowSeconds`, and the fingerprint evidence —
  a prior RESUMED run of that worker whose logged baseline matches the sheet's
  bytes (`match`), differs from it (`mismatch`: a resume rebuilds the prefix, so
  reuse is COLD and the successor reads the report file instead), or cannot witness
  the resume at all (`unmeasured`: the sheet's own run is the only row on record).

**A resume rebuilds the child's system prompt, and those bytes are stable only while
nothing the child inherits has changed.** Measured on this machine's scratch rig: a
resumed worker in an unchanged tree logged the SAME `sys` hash and the same
`prefixChars` as its original run, while the same worker resumed after a 73-byte project
context file was added to its cwd logged a DIFFERENT `sys` hash and 247 more prefix chars
(the `tools` hash unchanged — the divergence is inside the system segment, which
precedes the tools array and the whole conversation in the cached prefix). So an idle
resume is warm only by evidence, never by assumption: `adopt` itself resumes nothing and
promises no warmth, and `assign` remains the only resume path, governed by the reuse
window.

`adopt` resumes nothing, in any state. An idle worker is transferred with its reuse
verdict stated; the resume itself stays where it belongs — `assign`, which applies
the fleet's own reuse-window rule and refuses a cold one. When a crew was adopted,
the sheet is stamped (`adoptedAt` / `adoptedBy`) and only then is the pointer
deleted, so a crash mid-adoption is re-runnable and never double-claims.

**Every adopted entry reports the worker's last run and what landed since the
publish**, from the same two reads `roster` makes (Successor reads below): `lastRun`
and `landedSincePublish`. The adopt result also names the pointer it acted on as
`{path, cleared, reason}` — the path is named with its lifecycle, because a
successful adoption DELETES it (only when it still names the consumed sheet) and a
reader finding it absent afterwards would otherwise see a broken handoff where the
working path left no trace.

The canonical-session lease is NOT the blocker for any of this: it is held only by
a RESUMED child, and it is released when that child's run terminates.

### What a successor can read, and when

A successor inherits runs, not events. A worker can settle minutes after an
adoption, and its completion notice is delivered to the session that OWNS the run —
the predecessor, which by then has exited — so the NOTICE is lost while the OUTCOME
is on disk. Three reads therefore exist, all re-runnable at any point in the
successor's life, so "what landed since I took over?" can be asked on any later
`roster` as well as at `adopt`:

- **`lastRun`** — the worker's last run: `state`, `endedAt`/`endedAtIso`, and the two
  artifact locations its own record carries. The record is the source
  (`async-subagent-runs/<runId>/status.json`, read by `status.readRunRecord`, shaped
  once by `status.runOutcome`); both paths are existence-checked at read time, and a
  FAILED run carries neither field, so its row states "no artifact recorded" instead
  of rendering an empty path. `outputFile` is the run's own output log
  (`<runId>/output-0.log`) and `artifactsDir` the directory holding its composed
  output artifact (`<runId>_worker_output.md`). NEITHER is a report the worker
authored: the path a worker names in its final message appears in no record
  anywhere, so it is never promised, never invented and never reported as if it were
  the run's outcome. `artifactNote` says exactly that.
- **`landedSincePublish`** — the worker's runs that settled AFTER the publishing
  sheet's `writtenAt`, newest first, from `status.landingsSince`. The publish time is
  read from the sheet the worker's `adoptedFrom` names (`adopt.publishedAt`), never
  stamped once at adoption, which is what keeps the answer true for a worker that
  settles later; a worker hired by this session has no publish to compare against and
  no field. An unreadable or unstamped sheet yields `publishedAt: null` with a note —
  an unknown publish time is never compared against a zero, and an empty `runs` array
  is the measured answer "nothing landed".

**The cache-prefix read attributes by the CHILD SESSION ID, read from the run's own
transcript head** (`sessionFile` is the child's `<runId>/run-0/session.jsonl`, whose
first line records the id), with the run's pid as the second arm. It is never derived
from the transcript's file NAME: a subagent transcript is always
`…/run-0/session.jsonl`, so a name-derived key is one constant for every run and
attributes nothing. Rows are matched exactly — the log's `sess` is the full session
id, and a legacy row carrying only its first 8 characters is NOT read as a prefix
match, because a session id starts with the high 32 bits of its millisecond
timestamp, so every session started inside the same ~65 s window shares those eight
characters. Such rows stay readable through the pid arm, which is how the fingerprint
verdicts have in fact been working.

The cache-prefix log answers PREFIX questions only and never token questions: a row
is written on `before_provider_request`, where only the outgoing payload exists, and
no token or cache figure is reachable at that seam (`after_provider_response` carries
status and headers, not usage). Usage numbers live at the `message_end` seam
(`message.usage`, read by `deepseek-cost.ts`); a row that needs them belongs there,
not widened here. The fleet makes no pre-spawn prediction from the log: the run
descriptor's system prompt is constant while the bytes actually sent move with the
request-time block, so a prediction would turn an honest `unmeasured` into a false
`match` or `mismatch`.

### The successor's launch environment

`skills/handoff/launch-successor.sh` starts the successor with the crew identity
stripped, by ENUMERATED NAME: `PI_SUBAGENT`, `PI_SUBAGENT_CHILD`,
`PI_SUBAGENT_PARENT_SESSION`, `PI_SUBAGENT_EXTENSION_BINDINGS` and
`PI_INTERCOM_SESSION_ID`. Never by prefix: `PI_SUBAGENT_PI_BINARY` and
`PI_SUBAGENT_CACHE_RETENTION` are configuration, not identity, and dropping them
silently stops a nested launch from using the wrapper. A successor born holding a
live worker's binding resolves to an identity another process owns, and io-guard
then refuses every write and edit for its whole life.

That strip list does NOT cover `PI_FOREMAN`, which a worker's shell inherits: a
fleet-spawned worker runs under the foreman's environment, so a successor launched
from a worker's shell through this script comes up ARMED as a foreman. The arm is
`fleet`'s own `session_start` test — `mode.isOn(session) ||
(process.env.PI_FOREMAN === "1" && process.env.PI_SUBAGENT_CHILD !== "1")` — and
the script unsets `PI_SUBAGENT_CHILD`, so nothing in that clause is false once it
has run. `pi-foreman` is unaffected (it sets the marker itself); the gap is the
launcher for a successor that must NOT be a foreman, whose arm has to be cleared by
the same enumerated strip.

## Completion and failures

`index.ts` subscribes to `subagent:async-complete`. On a failed or stopped run it
records the cause from the run's OWN record — provider error on the final
assistant turn, else the last error tool result, else the last tool call — plus
exit code and process signal, stores it on the worker, and sends the foreman a
`fleet-failure` message carrying the cause the owner's own notice drops.

That message uses `triggerTurn: false` deliberately: the owner already wakes the
foreman for a non-completed run, and calling `prompt()` from inside the handler
re-enters the agent (`already processing a prompt`) and aborts the session.

A terminal worker is never resurrected by a late event, and a `retiring` worker's
own clock-out is its transition — the completion handler does not touch it.

## Usage, context fill and fatigue

`status.workerUsage` unions the figures across EVERY run a worker has used, so a
resume never resets its fatigue evidence, and the three figures answer three
different questions — none of them interchangeable:

- **`spentTokens`** — cumulative SPEND: uncached input + output summed over every
  assistant turn of every run that identity has used (cache reads excluded). It
  scales with turns, so it is a burn figure and never a context size.
- **`context` / `contextFill` / `contextLimit`** — what the worker is carrying
  NOW: `contextFill` is the NEWEST request's prompt size (`input + cacheRead` —
  system prompt, tools and the transcript up to that point) and `contextLimit`
  is the model window its newest run was launched with (`steps[].contextLimit`).
  `context` is those two rendered the way the parent session's own header reads
  (`553k/1.0M (55.3%)`), and is null unless both halves are known.
- **`contextHighWater`** — the largest single request the worker EVER sent
  (`windowPeak`). A high-water mark cannot fall, so a compacted worker stays
  peaked: it bounds the fill, it is not the fill.

`status.runUsage` reads the fill from the run's OWN artifacts — the run record's
`sessionFile` (its newest `session.jsonl`), last usage entry, `input + cacheRead`
— with the record's own `window` as the fallback when that transcript is gone.
The read is per run because several runs of ONE worker identity append to the
SAME lineage transcript: summing the per-run figures multiplies one turn's usage
by the number of runs (bob's seven runs each report a fill of 300k…553k off one
585-line transcript, so a per-run sum says 3.2M where the worker is carrying
553k). `workerUsage` therefore takes the newest run that reports a fill, never a
sum.

`FATIGUE_TOKENS = 800_000` (user-set) keys on the SPEND figure, and the roster
states that basis in the row (`fatigueBasis: "spentTokens >= 800000"`) so the
flag is never read as a context rule; an unknown spent-token count reports
`fatigue: null`, because an unmeasured worker cannot be called non-fatigued.
Re-basing the threshold onto the fill is the user's call, not a silent rescope.

## Clock-out

`retire` sends `clockOutMessage(contextK)`: `context at <N>k — clock out now:
read ~/.local/pi/foreman/clockout.md and follow it exactly`. The worker's own
context figure is substituted, so the fact the message exists to carry is never a
literal placeholder. The worker then writes
`~/.local/pi/foreman/handoffs/<name>.md` and reports `CLOCKED OUT <name>`;
retirement is worker-executed and foreman-triggered, and a retired name receives
no further tasks.

The reason for a clock-out is the foreman's, and one reason needs no handoff at
all: a retirement for a change of scope discards the old scope instead of handing
it over, which is what `~/.local/pi/foreman/clockout.md` states to the worker.

A clock-out steer is not always deliverable, and how a refusal is read decides
whether a claim ever comes off. `retireDisposition` settles the worker `retired`
when its run is already FINISHED **or when the owner refuses the steer in the
gone-run vocabulary** — `No async run found for '<id>'` and `No async run status
found for '<id>'` are what an owner that came back after a reboot answers, since
the detached run is not there to steer. Before that vocabulary was recognised the
refusal matched nothing, the worker stayed `retiring` for ever, and its paths
stayed refused to every hire. A transient steer fault still leaves it `retiring`
and the next `retire` retries it.

## The board: the retire guard and the closure (`board.ts`)

The board is the crew's at-a-glance state, and `board.ts` reads it in one
direction and writes it in the other. The READ is a precondition of retirement:
a worker is not retirable while it still owns an open row. The WRITE closes the
rows a retirement leaves behind.

### The guard (a precondition of `retire`)

`fleet retire` REFUSES when the worker still owns open rows (`openRowsFor` →
`openRowsOf`, over the same branch replay the closure writes through). The
refusal names each row — id, subject, status — and the tool result carries them
as `openRows`, so the caller can deal with them: get them completed (steer the
worker), or close a row itself when its work was dropped.

- **Why it comes FIRST.** The closure below closes exactly those rows
  (`[abandoned: …]` or `[superseded by …]`), which would MASK the state the
  guard exists to surface — a worker clocked out with work outstanding. The
  guard therefore runs ahead of the reconciliation, the state write, the claim
  release and the closure, and it is a pure READ: a refusal leaves the board,
  the roster and the claim exactly as it found them (no row closed, nothing
  appended, `w.state` untouched, no clock-out steer sent).
- **Eligibility is the closure's own rule.** A row blocks only when it is OPEN
  (`pending` / `in_progress`) and its SUBJECT attributes it to the retiring
  worker. A completed row never blocks; another worker's open row never blocks;
  a row with no `<name>:` prefix, or one naming somebody else, never blocks.
  Refusing on a row the board does not attribute would block a legitimate
  retirement, which is the failure this guard is not allowed to have.
- **Attribution reads the subject, never the `activeForm`.** The board's rows
  carry `<name>: <imperative subject>` in the SUBJECT because that is the field
  the naming rule and the closure both key on; the `activeForm` field is free
  prose (under half the live rows carry a prefix there), so reading it would
  attribute rows by accident.
- **What the guard does NOT cover, deliberately.** The roster reconcile that
  settles an already-`retiring` worker and the gone-run pass over a worker a
  reboot destroyed keep closing rows: no caller can be refused there (the
  settle is automatic), and in the gone-run case the worker that owns the row no
  longer exists to close it. The guard closes the front door, not the exit a
  destroyed worker needs.
- **No override.** There is no flag that retires a worker past the guard. The
  escape is the board write itself — the foreman closes or completes the row it
  judges dead — which is loud and leaves evidence on the board the user reads. A
  parameter would be a way past the guard in silence.
- **When the board cannot be read** (no session manager on this process) the
  guard stands down rather than refusing every retirement for a reason that says
  nothing about the worker, and logs one `board-guard-unavailable` row
  (`source: fleet`) so an unchecked retirement is visible rather than silent.

### The closure

A retired worker can no longer close its own board rows, and an open row left
behind is not harmless: the board is the at-a-glance state of the crew, so a row
that stays pending for ever makes it lie. Every path that settles a worker
`retired` — the `retire` action, the `roster` reconcile that settles a
`retiring` worker, and the gone-run pass that clears a worker a reboot destroyed —
closes that worker's OPEN rows on this session's branch. On the `retire` path the
guard has already cleared the board, so what the closure finds there is only rows
the worker opened AFTER the guard passed (it is still running until it clocks
out); those, and the rows of a worker no caller can be refused for, are the ones
it closes.

- **The channel is the crew's own, never a second one.** `board.ts` replays this
  session's branch with `@juicesharp/rpiv-todo`'s `replayFromBranch`, closes the
  rows through its PURE `applyTaskMutation`, appends the accumulated board as ONE
  replay-compatible `todo` toolResult (the same row shape `todo_parent.ts`
  appends) and emits `rpiv-todo:external-refresh`, so the view the foreman's tool
  and the user's overlay read moves with it. One append per retirement, so the
  live view moves once, and a closure survives replay exactly as a worker's own
  row does. Only the package's pure reducer and replay are imported — never its
  store, which is module-private to the package's own extension instance.
- **Eligibility is narrow.** Only the RETIRING worker's rows, and only OPEN ones
  (`pending` / `in_progress`). A completed row is never touched, and a row
  belonging to another worker is never touched, whatever it says. Attribution is
  the crew's own `<name>:` subject prefix, and it must also name a worker on THIS
  session's crew: a row with no prefix, or one naming something that is not a
  crew member, is left alone and reported. Guessing there would write a false
  owner onto the board the user reads.
- **SUPERSEDED is a scope-level claim.** A row is closed as
  `[superseded by <worker>]` when another crew member covers the SAME SCOPE — the
  declared scope strings are identical, or a declared claim of one overlaps a
  claim of the other under the same `predicates.globOverlap` rule the claim
  guards use — and that member has a completed board row, which the note names as
  the evidence. Otherwise the row closes as `[abandoned: <worker> retired]`:
  "someone else did it" and "it was dropped" are different facts and the board
  says which. An empty declaration matches nothing.
- **Ambiguity closes; it never claims supersession.** More than one crew member on
  the scope, or a same-scope member with no completed row, yields the abandoned
  closure. A wrong "superseded" is a false statement about who did what, so doubt
  resolves to the weaker claim.
- **Idempotent, and the row is closed rather than rewritten.** Only open rows are
  eligible and a subject already carrying a marker is skipped, so a row reopened
  by hand never collects a second one; the worker's own description is kept and
  the closure note is APPENDED to it. The tool result carries every closed row,
  every row left as-is with its reason, and whether the branch write and the live
  refresh landed.
- **What does NOT close rows.** `handoff` and `adopt` transfer a crew rather than
  end it: a `handed-off` worker's rows stay open for the successor, which
  reconciles its own board. `/foreman-off` and `session_shutdown` leave a running
  crew running. A worker marked `not-resumable` by a failed resume keeps its rows
  — it has not been retired — and `fleet retire` remains the one action that
  retires it and closes them there.
- **The foreman's own tidy is discipline, not machinery.** `section.ts` lets the
  foreman close a row itself, and only when the user asks: the owner is retired or
  has gone cold past the reuse window, or another worker completed the same scope.
  `board.ts` implements none of that — it closes rows only along a retirement — so
  a tidy the foreman performs carries no `board` key in any tool result. That tidy
  is also the ONE way past the retire guard: the guard refuses on open rows, and
  closing or completing the row the foreman judges dead is what clears it.
- **The refresh is a patch, not a guarantee.** The durable branch write always
  lands; the emit reaches the live view only through the `rpiv-todo`
  external-refresh subscriber (`~/.pi/agent/patches/rpiv-todo/`). Without that
  patch the closure is durable but the board does not move, and the tool result
  says so.

## Gotchas

- A foreground launch declaring an extension-provided tool fails at launch —
  see the transport section. Keep launches async.
- `subagent` is replaced, not shadowed: the foreman set does not contain it, so
  the only way back to the session's pre-activation array is `/foreman-off`.
- Nothing may change the tool array or a tool's prompt metadata mid-session
  except the two mode transitions (`session_start` arm, `/foreman-off`): any other
  change re-bills the remaining tools and the whole conversation behind them.
- The tool never writes a report or a handoff on a worker's behalf, and the
  foreman must not do so either. Its one board write is the closure of a settled
  worker's own rows (see The board closure) — it never creates a row on anyone's
  behalf, and never a row for work nobody did.
- A tool that is not registered in this process is left out of the applied set —
  `fleet` itself is the one exception, whose absence refuses activation.
- `fleet` reads the mode file on every call, so a stale in-memory belief about
  the mode is never authoritative.

## Spec rule

This file is the contract for the crew's machinery. When the code changes, this
file changes in the SAME edit — a spec that lags its code is a false statement
that the next session will act on.

## The item ledger (`items.ts`)

The foreman's own working memory, one file per session at
`~/.local/pi/foreman/items-<sessionId>.json`, reached through the `fleet` tool's
`items` action (op `add` | `update` | `list`) rather than a tool of its own: the
foreman's tool array is applied once and frozen, so a fifteenth tool would
re-bill the whole conversation the moment it appeared.

It is deliberately NOT the todo board. The board is the workers' own record,
rebuilt from the session branch; the ledger survives a compaction and a resume,
which is the whole point of it.

- An item is the smallest unit with exactly ONE owner and ONE write claim. Two
  owners is two items; no write claim is `exclusive: ["none"]`. `add` refuses an
  item with no declared claim at all, through the same `declared()` helper
  `hire`/`assign` use, so the ledger cannot record a claim the launch path
  would refuse.
- States are `queued` (on add, never pre-marked live) → `live` once work has
  actually started → `done` or `failed`, with the artifact path when it lands.
- `update` patches HALF the claims when half is supplied: omitting `owns` must
  not erase it, exactly as omitting `artifact` does not clear it. An explicit
  empty string clears.
- Writes are atomic (temp file + rename): a half-written ledger is a ledger that
  lost items.
- Retention is `pruneOldLedgers` (30 days by mtime), called beside
  `mode.pruneOld()`. Durable is not immortal.

## The retirement signal (`retire.ts`)

Advisory only: it never retires anything, and `fleet retire` remains the single
way a worker is clocked out. It answers one question — is replacing a warm worker
cheaper than keeping it — as `X = (B − F0) + q·m + eta·(r·B + q·obar)`,
`MULT = (1 − r)/r`, `K* = ceil(MARGIN · MULT · X / (W − B))`, firing when the
projected remaining requests K̂ exceed K*.

- Prices come from `../lib/tariff.ts` (see the note there on why the registry's
  row is not the source), and the crew's reuse window from `config.json`. No
  ratio, multiple or window is a literal.
- The arithmetic is PURE (`replacementCost`, `breakEvenRequests`,
  `projectRemainingRequests`, `assessRetirement`); only `readPrice`,
  `loadReuseWindowMs`, `appendRetireLog` and `checkRetirement` touch the disk.
- Two backstops are deliberately NOT economic, because a rule whose payoff is
  measured in cents cannot be the only trigger: a correctness cap at 75% of the
  context limit and a deep-in-the-money cap at 250k stale tokens each force a
  reset at the next step boundary. The lifetime-token rule is an ALARM at 900k and
  never retires.
- Every assessment appends one line to `~/.local/pi/foreman/retire-log.jsonl`,
  including REFUSALS. A rule that cannot fire and stays silent is
  indistinguishable from a rule that finds nothing.
- DELIVERED from `fleet/index.ts` on the same `subagent:async-complete` seam the
  completion notice uses: appended without forcing a turn, EXCEPT for the two hard
  backstops, which force one — that worker is about to be reset whatever the
  foreman decides.

**Every input is now SOURCED, not assumed.** B is the smallest window from a run
after the worker's first (never the fresh first run). F0 is the median prefix size
recorded in the house cache log, converted at four characters per token — an
estimate, and named as one, because overestimating F0 would subtract away the cost
of replacing and tilt every decision toward retiring. `m` is the worker's own
handoff file at the same conversion. The context limit comes from the registry,
which still carries `contextWindow` for a model whose COST row was zeroed. K̂'s
per-item requests are STAMPED by the ledger at the `live` and `done` transitions
rather than inferred from runs. The fleet-wide rate cap reads the retirement times
this module has already logged — a cap assumed empty is not a cap. `midStep`,
`familyShift`, `handoffCurrent`, `itemsSinceHire` and `pendingItems` are read
from the worker's state, the queued items' scopes, the handoff file's mtime and the
ledger.

**The two unmeasurable guards REFUSE rather than assume.** `lineageDepth` now has
a source — the roster counts workers on this scope already retired, so the lineage
cap is real. `nonHandoffableState` has none: nothing reports whether a worker
holds uncommitted work or a running subprocess (a live run is already caught by
`midStep`). It is passed as UNKNOWN and an uncheckable guard SILENCES the
economic path, with the reason recorded, because a bad handoff costs a deliverable
while a false positive costs cents. The two hard backstops are NOT affected — they
return before any guard is read — so the safety resets fire through every unknown
and every guard. Lifting this needs a source for that one fact; the decision to
lift it is not this document's to take.



## What the first live flight changed

Five behaviours changed because the first flight exposed them, not because they were
theorised:

- **A successful completion now updates the roster.** Only failures used to notify
  the fleet, so a finished worker stayed marked `live` until some later call
  happened to reconcile it — observed live with five workers at once. The roster is
  what the foreman reads between calls, so it must not lag reality.
- **`node_modules` is refused as a claim** (in `predicates.ts`, so the ledger, hire
  and assign all inherit it). That tree is npm-managed: an install prunes an
  undeclared link there and DELETES what it points at, so a worker told it owns such
  a path is pointed at a directory that can vanish mid-task. The refusal names the
  source path to claim instead.
- **An item cannot go `live` or `done` without naming its worker.** The first flight
  recorded all thirteen items as `unassigned`, which left a takeover with no way to
  get from an item to the run that produced the evidence for it. The owner IS that
  link, so `items update` refuses the transition when neither the patch nor the
  stored item names one. `items add` stays permissive: an item is usually recorded
  before it has an owner.
- **The `["none"]` sentinel survives into the ledger** as `claims.exclusiveDeclared`.
  The normalised token list is empty either way, so without it the record cannot
  distinguish "declared nothing exclusive" from "said nothing at all" — and §7
  requires every item to declare. It renders as `exclusive=none (declared)`.
- **The injected discipline carries two new rules** (section v4): ask the user only
  when the answer changes the next action, and reconcile and dispatch the moment it
  lands — one unanswered question sat for forty minutes while five workers finished
  behind it. And scope COARSELY on a list of small edits: one worker per tiny item
  means no worker ever receives a second task, so none is ever warm again.

## The frozen tool set is ENFORCED, not merely applied

Activation applies the fourteen once. That is not enough, and a live session proved
it: context-mode registers its eleven `ctx_*` tools LAZILY, from inside its own
`before_agent_start` handler (its adapter says so; the hook fires only on the
interactive prompt path). A foreman started by an injected message therefore never
ran that registration and held the whole set for 74 requests — until a typed prompt
fired it, pi APPENDED the new tools to the active set, and the tool array went
13 -> 24 mid-session. The array sits BEFORE the messages in the byte-compared
prefix, so that single event re-sent 821,272 characters, roughly 205k tokens.

Two handlers in `index.ts` now make the set an invariant:

- `before_provider_request` filters `payload.tools` down to the applied set,
  keeping the order the tools already had. Filtering the PAYLOAD rather than only
  re-applying the set is deliberate: the payload is the bytes, so this holds for a
  request already in flight, and the kept order is what makes the array
  byte-identical to the requests made before the intrusion.
- `tool_call` compares the harness's active set against the applied one and
  re-applies it when it has drifted, so the registry cannot keep re-growing behind
  the filter.

Both are gated on the mode being ON for that session, so a session that has run
`/foreman-off` — whose tool set `deactivate` has already restored — is untouched.
Both swallow their own faults: an enforcement error must never break a request.

**The DEFINITION is frozen, not the activation snapshot.** Re-opening the first
foreman session exposed why that distinction matters: in the new process,
activation left one name out, because `subagent_supervisor` had not registered
yet at activation time — the same lazy-registration pattern as the
`ctx_*` family, but for a tool that BELONGS in the set. A snapshot-freezing filter
would have made that permanent and silently cost the foreman the reply channel for
its own workers. So the payload filter admits any tool in `FOREMAN_TOOLS`, whether
it was present at activation or arrived afterwards, and drops only what is outside
that list; the drift handler removes strays only, never a legitimate late arrival —
with one deliberate exception, the loader tools (`*_enable`). A loader is re-added by
its owning extension on every typed run, and pi renders one prompt bullet per selected
tool at the head of the system prompt: taking a loader out of the active set makes the
next run render something the typed path would not, because `before_agent_start` runs
only there — and that hook either pushes the loader into the run's
`systemPromptOptions.selectedTools` (pi-subagents) or re-adds it to the live set that pi
then copies into `selectedTools` (pi-web-access) — while a wake runs neither and renders
the set as it stands, one bullet fewer, recorded as a shrink in the `tools` section. A
head that moves can re-bill the conversation behind it: a foreman session paid 86,470
miss tokens on the request after `web_enable` first arrived mid-session, and 100,999 on
the request after that. Loaders therefore stay selected, and activation admits registered
ones before the first run, so the tool section cannot change under a session for any
loader registered when that session starts; one that registers LATER still moves the head
once. The payload filter, not the drift handler, is what keeps loaders uncallable.

**The wiring is rig-covered.** `p5-wiring` drives a REAL completion event through
the whole path — mode gate, roster lookup, usage read, B sampling, facts assembly,
`checkRetirement`, the log — and asserts the silence cases too: an unknown run id,
a non-foreman session, and a missing model id each do nothing or refuse. It found
two defects worth remembering, both of which would have been invisible in a live
test. `workerUsage` can return NULL, and an unguarded dereference throws straight
into the handler's own catch — the silent failure this whole mechanism exists to
avoid. And this seam has no `before_agent_start` context to inherit a model from,
so `crewModelId` falls back to `PI_MODEL`; without that every assessment would
refuse for want of a model the session does in fact run.
