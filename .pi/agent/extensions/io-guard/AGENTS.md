# io-guard — per-worker IO coordination

**Scope.** Hooks that make a crew of workers safe on one shared tree, plus one tool
for the foreman. Worker-side code runs inside a crew worker's process; the tool is
registered only in a non-child process. The design it implements is
`~/.pi/agent/skills/foreman/IO-SYNC-PLAN.md`; this file states what the CODE does.

## Identity: which process is the worker

A process is the crew worker when:

- `PI_SUBAGENT_CHILD=1`, and
- `PI_SUBAGENT_EXTENSION_BINDINGS` contains **exactly one** key in the fleet
  namespace (`fleet/<n>`; see `isFleetNamespace`) whose payload has a non-empty
  `worker`. Two fleet keys are ambiguous and resolve to nothing.

`PI_SUBAGENT=1` is NOT part of this test: the async runner is spawned outside the
wrapper that exports it, so it is absent for background children. The crew name
appears in no other environment variable.

**One process owns a worker identity.** The binding is inherited by everything a
worker spawns — build scripts, postinstalls, a bash-launched `pi` — so identity is
claimed through `io/runtime/<worker>.json`, holding a pid and the kernel start time
for that pid (`/proc/<pid>/stat` field 22, so a reused pid cannot pass as the
owner). The claim file is written to a temp path and **hard-linked** into place:
`link` fails with EEXIST instead of overwriting, so no claimant can ever observe a
claim file that exists but is still empty.

- A second process presenting the same binding finds a LIVE owner and resolves to
  NO identity — that is what makes the guard inert inside a descendant.
- An owner that is provably dead is taken over, so a resumed worker is not locked
  out by its predecessor.
- An unparseable record is treated as a live claimant — not as debris — unless it
  is older than a 60 s grace.
- Where `/proc` is unavailable the liveness test falls back to a signal probe,
  deliberately biased toward "held".

`identityClaimLive(root, worker)` is that same liveness question asked BY NAME:
it reads the worker's runtime record and answers whether a process holds the
identity right now, using the identical pid + start-time rule a second claimant
uses before standing down. It is exported for the one caller that must decide a
worker is gone — `fleet`'s release pass — so the rule is stated once.

**Inert on a real worker is refused, not hidden.** Identity is resolved eagerly at
load. A process that carries a crew binding but does not own that identity REFUSES
every write with an explanation and logs an `inert` line, because silently
enforcing nothing is the worst outcome this system can produce.

## Claims: what a worker may write

The binding is a hire-time snapshot; the dispatcher updates a worker's scope and
owned paths on every assign, and a resumed worker keeps its original binding. So
the CURRENT claim is read from `io/claims/<worker>.json` for every write, never
from the binding:

- **generation** — bumped only when a claim is RECLAIMED, never by an ordinary
  assign. The worker pins the generation the first time it SEES the claim (read or
  write) and refuses to write once the record's generation moves past it.
- A missing claim record refuses every write: an unchecked write is exactly what
  this guard exists to prevent.
- The dispatcher publishes the claim at hire and at assign, BEFORE the worker can
  run (`syncClaim` in `fleet/index.ts`).

## Paths a worker may write without a claim

Its own handoff, its own report files, its own scratch directory, and its own
dedicated temp directory (`io/tmp/<worker>`). The `tmpdir` argument must be the
worker's OWN temp directory: allowlisting the ambient `/tmp` would exempt every
path under it and silently disable the guard. Ownership is checked BEFORE the
allowlist, so a reclaimed worker keeps no write surface at all, not even its
handoff.

## Versions: what the worker read

A `read` is bracketed on BOTH sides of the read that produces the hash:
`tool_call` stamps size and mtime before the tool runs, the capture reads the file
once for the hash and body, and `tool_result` stamps it again. All three must agree
for the record to be **trusted**. Comparing only before-and-after would leave the
capture's own read outside the bracket and could pin a stale baseline as trusted.

- An untrusted, absent or evicted record is a REFUSAL for a whole-file write. The
  registry is bounded (LRU 4096) and in memory, so eviction and every restart lose
  baselines; a missing baseline is not evidence of an unchanged file.
- A body is spooled only when the record is trusted, the read was full (no window
  AND the tool reported no truncation), the path is inside the claim, and the file
  is under `SIZE_CAP` (2 MB). Hash and body come from ONE read, and the spool
  refuses bytes that do not hash to the key they are filed under.
- Storing an already-present body refreshes its timestamp, so a last-use reaper
  ages an entry by when it was last READ, not when it was first stored.
- **The baseline is only re-based on a write the guard ALLOWED and the tool
  reported as successful.** Recording after a failed or blocked call would re-base
  the worker on content it never wrote, and its next write would clobber whatever
  landed in between.

## The per-write lock

One writer per path, held for the duration of a single write:

```
flock -n -E 9 <lockfile> -c 'echo HELD; timeout 120 cat >/dev/null'
```

- The helper holds the kernel lock while this process keeps its stdin open.
- **Success is decided by the helper printing `HELD`** — never by a timer. A timer
  was wrong in a way that mattered: under load the helper could still be starting
  when it expired, so a REFUSED acquisition was recorded as a success, the caller
  wrote a holder sidecar for a lock it did not own, and two writers could both
  believe they were exclusive.
- Exclusivity is then VERIFIED with a probe: if a probe can take the lock, this
  process does not hold it, and the acquisition is reported as failed.
- Closing the pipe ends the helper and the kernel drops the lock. If this process
  dies the pipe closes with it, so the lock is released with no cleanup pass.
- The helper's TTL bounds a hold leaked by a handler that never reaches release.
- The sidecar holding the holder's name and start time is unlinked only when it is
  still OURS: it is per-path, so a late release for an expired hold would otherwise
  delete the current holder's record.
- A hold found expired at release time is logged.

## The write path

Every write must clear, in order: identity (refusing if the environment says crew
but another process owns it), the claim's existence, the generation fence, scope or
allowlist, then the version rule below. An error anywhere in the guard REFUSES the
write.

- **Whole-file `write`** — the file must still hash to the version the worker read.
- **Anchored `edit`** — allowed when its anchors apply to the CURRENT content, even
  if the rest of the file moved, because that is the common two-writer case and the
  reason anchors exist. Anchors must be present exactly once.
- The lock is taken non-blocking, and held ACROSS execution, not merely checked at
  preflight (pi preflights a batch sequentially and then executes concurrently, so
  a check-then-allow would race its own message).
- **If the lock is held, the write is PARKED**, not dropped and not waited on: the
  proposal and the version it was based on are stored, and the refusal names the
  holder, the age, the parked id, and what to do next.

## Park and merge

When a lock is released, parked proposals for that path are drained in arrival
order. The drain is itself a WRITER, so it takes the same lock: applying a merge
under someone else's lock is exactly the interleaving the lock prevents, and it
takes the lock with a bounded retry because a release is asynchronous (the kernel
drops the lock when the helper actually exits, a tenth of a second or so later).

- **No base → no merge.** A proposal without a spooled base is kept and reported.
- **No target → no merge.** A deleted file is not mergeable context: diffing
  against an empty "ours" reads as "we deleted everything", and a clean merge would
  resurrect a file that was deliberately removed.
- `git merge-file` returns 0 for clean, the NUMBER of conflicts when it conflicts,
  and a negative code on error — "nonzero means conflict" would misclassify an
  error.
- A conflicted proposal is KEPT and reported; conflict markers are never written
  into a live shared file.
- After a merge the file is recorded as **untrusted** for the merging worker: it
  did not write that content and has not seen it, so its next write must re-read
  first rather than overwrite a peer's merged change.
- Attempts are bounded; past the bound a proposal is reported as escalated.

## Residue

At the end of a run the worker compares its recorded versions against disk and logs
what changed. This is the ONLY backstop for writes made through bash, which the
guard does not see by decision. It cannot attribute a change to a worker, and an
unread file leaves no trace at all. It runs once, at task end, by decision.

## io_status — the foreman's one tool

Registered only in a non-child process. `inspect` lists claims with their
generations, lock holders judged alive or dead, and parked proposals with their
attempts. `reclaim` withdraws the **guard's side** of a claim by generation: a
process still running under that name has its next write refused.

`reclaim` is NOT an ownership release. Ownership is stated in two records — the
roster entry (`~/.local/pi/foreman/roster/<sessionId>.json`), which is what the
fleet hire-time overlap check reads, and this record, which is what a worker's own
writes are authorised against. Moving only this one leaves the paths owned for the
hire check, so a worker whose run is gone is released through `fleet` instead
(`fleet/release.ts` — the `retire` action, the reconcile that settles a finished
run, and the pass that releases a run a reboot destroyed all go through it).

## Layout

```
io/runtime/<worker>.json      the one process claiming that identity
io/claims/<worker>.json       the dispatcher's statement of what that worker owns
io/locks/<hash>.lock|.json    the flock target and its holder sidecar
io/base/<sha256>              spooled read bodies (merge bases)
io/pending/<pathhash>/        parked proposals
io/scratch/<worker>/          the worker's own scratch, claim-free
io/tmp/<worker>/              the worker's own temp, claim-free
io/build/<worker>/{out,cache,tmp}   build isolation roots (see build.ts)
io/builds.jsonl               one line per build
```

Every recorded read appends one line to the house hook log
(`~/.local/share/pi-hooks/log.jsonl`, source `io-guard`).

## Reaper

`reap(root, maxAgeMs)` reclaims spool bodies, per-worker build roots and parked
proposals by LAST USE, and scratch dirs by a shorter window. Build roots are aged
by the newest mtime anywhere inside them, because a root's own mtime is set when it
is created and never updated — ageing by that would delete a warm root in constant
use. Nothing is reclaimed because a worker is merely idle: warm reuse is why
per-worker roots exist. Reaching it: `io_status` with `action: "reap"`.

## Testing

The modules import cleanly and are side-effect-free at load, so rigs drive the
extension with a fake `ExtensionAPI` and fake events. **Erasable-only TypeScript is
required** — node's type stripping cannot compile parameter properties, enums or
namespaces — which keeps the rigs honest: they load the same source pi loads, with
no build step. Each rig REFUSES to run unless `HOME` is a scratch tree.

- `/tmp/io-rig/p1.ts` — the read side, identity, and an inert process.
- `/tmp/io-rig/p2.ts` — the write path's rules: refusals, the lock's lifecycle,
  the allowlist, anchors, and reclaim.
- `/tmp/io-rig/p3.ts` — park and merge against a REAL external holder.

## Obligations and known-open items

- **A missing or untrusted record is a REFUSAL** — implemented for whole-file
  writes; the LRU bound means a long session can evict baselines, which costs
  spurious refusals rather than false passes.
- **No heartbeat exists.** `ClaimRecord.updatedAt` is written by the dispatcher
  only; a liveness-based heartbeat is not implemented, so reclaim relies on the
  FOREMAN deciding a worker is dead.
- **Reclaim is a read-check-write, not a true compare-and-set**, and `io_status`
  defaults the generation to the current value when the caller omits it. Nothing
  here checks that the reclaimed worker is provably dead, because that proof
  belongs to the RELEASE path rather than to the write fence: `fleet`'s gone-run
  pass requires no row for the worker's handle lineage, no surviving run record, a
  verified handle and no process holding the identity
  (`identity.identityClaimLive`) before it releases the roster row and withdraws
  the claim record together.
- **Residue cannot attribute a peer's guarded write**; it reports any change to a
  path it recorded as unexplained, including a legitimate peer edit.
- **Conflict and escalation outcomes are logged but not surfaced to the foreman**
  beyond `io_status`'s parked-proposal line.
- **`syncClaim` swallows its failures**, so an unwritable io root produces
  claim-missing refusals on the worker side while the foreman sees nothing.
- Deferred: the per-worker build roots are exported by the build tool only, so a
  build typed straight into bash is not isolated (a user decision, recorded in the
  plan as a known limit).
