# Local patch: `rpiv-todo` external-refresh subscriber

**One file, three hunks.** `external-refresh.patch` patches
`@juicesharp/rpiv-todo/index.ts` only.

## What it fixes

`todo_parent` (the crew todo proxy at `~/.pi/agent/npm/node_modules/@tinoy/pi-todo-parent/index.ts`) records a
worker's mutation by appending a replay-compatible `todo` `toolResult` row to the spawning
session's **branch**, then emitting `pi.events.emit("rpiv-todo:external-refresh", { sid })`.

The packaged extension reads its live state from a module-private per-session `Map`
(`state/store.ts`), written only by `replaceState`/`commitState` from its own lifecycle
handlers (`session_start` / `session_compact` / `session_tree`) and its own tool execute.
With no subscriber the crew entry never reaches the tool or the overlay the user reads, and
the next parent-side todo write appends a row from that **stale** view — which then wins
replay's last-write-wins and deletes the crew entry (no tombstone, id freed for reuse).

No extension could fix this from outside: each extension is loaded in its own jiti registry
(`dist/core/extensions/loader.js`, `moduleCache: false`), so that `Map` is unreachable by
import; `ExtensionAPI` exposes no tool invocation (`getAllTools()` returns
name/description/parameters only); and core lifecycle events cannot be emitted by an
extension. The subscriber therefore has to live in the package. The user sanctioned this
narrow patch (2026-09-14) instead of vendoring a fork or a wrapper package.

The patch is a `pi.events.on("rpiv-todo:external-refresh", …)` subscriber that replays the
branch into the store the tool/overlay read, plus the one line of plumbing it needs
(stashing the `session_start` ctx). The rationale is recorded in a comment next to it.

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

```
patch -p1 -d /home/tinoy/.pi/agent/npm/node_modules/@juicesharp/rpiv-todo < /home/tinoy/.pi/agent/patches/rpiv-todo/external-refresh.patch
```

Prefer letting `apply-patches.sh` do this: it reads the applied state from the installed
file, requires a clean `--dry-run` before writing, keeps the per-version rollback copy and
records what it did. Running the patch by hand is only for a machine without the units.

## Is it applied?

```
grep -c 'rpiv-todo:external-refresh' /home/tinoy/.pi/agent/npm/node_modules/@juicesharp/rpiv-todo/index.ts
```

`2` = applied (the comment line + the `pi.events.on` line) · `0` = not applied (or an
update replaced the file). A dry run confirms it, and the two directions read
differently:

```
patch -p1 --dry-run    -d <pkg> < <patch>   # "Reversed (or previously applied) patch detected!" = applied
patch -p1 --dry-run -R -d <pkg> < <patch>   # "Unreversed patch detected!" = not applied
```

`pre-patch/index.ts.<version>` holds a byte-identical copy of the file as packaged,
for a full revert if a half-applied state ever needs undoing.

## When it takes effect

At the **next pi session start**. A running session keeps the module it loaded, so a patch
applied mid-session does not change that session's behaviour.

## Offline check (no pi session, no model)

```
cd /home/tinoy/.pi/agent/npm/node_modules/@juicesharp/rpiv-todo && node /home/tinoy/.pi/agent/patches/rpiv-todo/verify-offline.mjs
```

Loads the patched package through jiti (the loader pi uses) with a fake `ExtensionAPI` and
asserts that the subscriber replays branch truth into the store the `todo` tool reads, that
the registered tool then reports the crew entry, and that the real pi `EventBus` delivers
the emit. 14 assertions; exit code 0 = pass. **Launch a pi process from a normal shell, not
from inside a subagent** — an inherited `PI_SUBAGENT_CHILD=1` makes `todo-parent.ts` take its
child branch, so no watcher runs and nothing answers.
