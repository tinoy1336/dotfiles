# Local package patches

Three npm-managed packages under `~/.pi/agent/npm/node_modules` carry local patches, and a
fourth — `@tinoy/pi-fleet` — carries the tightened foreman discipline section. npm owns
those directories and rewrites them on every install or update, which deletes the patches;
this directory is the source of truth and `apply-patches.sh` restores the patched state
afterwards. The applier does not take ownership of the packages: it re-applies a patch,
under a clean dry run, and leaves a rollback copy behind.

| Patch | Package | Target files | Effect |
|---|---|---|---|
| `rpiv-todo/external-refresh.patch` | `@juicesharp/rpiv-todo` | `index.ts` | a crew worker's todo mutation reaches the parent's live board instead of waiting for its next session start |
| `pi-subagents/label-display-name.patch` | `pi-subagents` | `src/extension/schemas.js`, `src/runs/foreground/subagent-executor.js`, `src/runs/background/async-execution.js`, `src/tui/render.js` | the async-agents rows show the crew name (`alice`) instead of the agent type (`worker`): the spawn `label` is declared, forwarded into the single async run, carried on the launch step the child's own status write rebuilds from, and read back by the row label |
| `pi-subagents/worker-board-name.patch` | `pi-subagents` | `agents/worker.md` | the worker agent's own definition tells it to name every shared-board todo entry it writes (`<name>: <imperative subject>`) |
| `pi-subagents/resume-label-forward.patch` | `pi-subagents` | `src/extension/rpc.js`, `src/runs/foreground/subagent-executor.js` | a warm-reused (resumed) run keeps its crew name: the resume RPC normaliser forwards the caller's `label` and the revive call puts it on the revived step, so the async-agents row reads `carol` after `fleet assign` instead of the bare agent type |
| `pi-subagents/pause-aware-control.patch` | `pi-subagents` | `src/runs/shared/subagent-control.js`, `src/runs/foreground/execution.js`, `src/runs/background/subagent-runner.js` | a machine-wide pause no longer reads as a hang: while the pause library reports an active pause the control watchdog counts its inactivity signals instead of notifying per run, and reports ONE aggregated line per affected run once the pause is over |
| `deepseek-cost/two-unit-countdown.patch` | `@tinoy/pi-deepseek-cost` | `index.ts` | the footer countdown shows up to two units (`1d 3h`, `11h 5m`, `53m 4s`, `38s`) instead of one, dropping the second unit when it is zero, so an interval with hours left no longer loses its minutes |
| `fleet-output-discipline/output-discipline.patch` | `@tinoy/pi-fleet` | `section.ts` | the foreman discipline section requires a landing bullet or no text at all, forbids the placeholder token and the turn that ends on a reasoning block alone, and requires prose whenever the requester asks a question, requests a plan, an explanation or an opinion, or reports a defect |

Each patch directory has its own README (what the patch changes, probes, offline rig) and
`pre-patch/` with byte-identical copies of its targets as packaged, keyed by package version.
A copy must be the packaged bytes of its OWN version: a file that did not change between two
versions may legitimately carry the same bytes, but a copy made by copying the previous
version's — the shortcut for a file assumed unchanged — is a claim `selftest.sh` checks
against the installed tree, so it is written from the tarball the version was installed from
rather than assumed. A stale copy also makes a rollback restore the wrong bytes.

## The applier

`apply-patches.sh` reads `managed-patches.conf` and, per entry:

1. reads the applied state from the **installed** files by grepping the entry's marker
   strings — never from a flag file, so a package rewrite makes the state read as
   "not applied" on its own;
2. if every marker is present: stops there. No patch run, no write to the package, exit 0.
   The run is a no-op safe to repeat on every login;
3. otherwise runs `patch -p1 --batch --fuzz=0 --dry-run` against the package. `--fuzz=0`
   requires an exact context match: a target whose surrounding code moved must fail rather
   than be fuzz-applied. A failure against a package written within the last 90 seconds is
   read as an install still in flight — the trigger fires on the first write of a rewrite,
   while npm is still unpacking the targets — so the entry is retried up to 3 more times,
   15 seconds apart. Only a settled tree can fail;
4. applies the patch to copies of the target files in a staging directory, re-checks the
   markers there, copies the current files to
   `<patch-dir>/pre-patch/<name>.<package-version>` (no-clobber, so the first backup of a
   version is kept), and only then renames each patched copy over its original. A failed
   step leaves the package byte-identical, and a concurrent reader never sees a half-written
   file.
5. verifies the markers again in the installed files;
6. runs `doctor.sh` and folds its verdict into the run — the doctor covers what the patch
   step cannot see (a package rewrite that leaves every patch applied and the async runner
   dead at import), stays silent while healthy, and a non-zero verdict makes the run exit 1
   and records the doctor in `FAILED`.

The entries re-applied by one run are announced together, in a single notification: an
update rewrites several packages at once, and a popup per patch buries the ones that matter.

Exit status is 0 when every entry is applied (or was already) and the doctor is healthy, 1
when any entry or the doctor failed.

### Failure behaviour

A patch that cannot apply against a settled tree is never forced:
- the exact dry-run output is appended to `apply.log`;
- `FAILED` is written with the entry name, the reason and the log path;
- a critical desktop notification is sent (`notify-send`, app name `pi-patches`);
- the run exits non-zero, so under systemd the service is a **failed unit** — visible in
  `systemctl --user --failed` and in `journalctl --user -u pi-patch-apply.service`;
- the package files are untouched, and the log names the rollback copies for the entries
  that were already applied.

`FAILED` exists only while a failure stands: a later clean run removes it.

The doctor's own failure path is separate: it prints the failing check, sends ONE critical
notification (app name `pi-doctor`) naming that check and the single command that fixes it,
and exits non-zero. It sends no notification for its advisory peer-range line, and the
applier tells it to stay silent when the run already has a patch failure to announce, so one
run produces one notification.

### Paths

| Path | Role |
|---|---|
| `apply-patches.sh` | the applier |
| `managed-patches.conf` | which patches to keep applied, and their marker specs |
| `selftest.sh` | self-test: a moved target must fail safely, and every entry the manifest registers for the mirrored packages (`@juicesharp/rpiv-todo`, `pi-subagents`, `@tinoy/pi-deepseek-cost`, `@tinoy/pi-fleet`) must patch a pristine mirror to the installed bytes (the mirror's manifest is built from `managed-patches.conf`, the mirror is seeded from the installed version's pre-patch copies, a missing seed stops the test and names the version, and a guard fails when a registered entry is not mirrored); and every package directory the manifest names must appear in the watch list the user manager reports for `pi-patch-apply.path` (`systemctl --user show pi-patch-apply.path -p Paths`), so a package registered without a watch entry fails here and names the package instead of being rewritten unpatched |
| `doctor.sh` | the pi toolchain check the applier ends every run with, so the existing trigger also covers it: `HOST` (the `pi` on PATH resolved to the package that owns it, with that package's version — two installs with two owners is the failure class), `RUNNER` (the async runner's module graph imported in Node through the same preload the spawned child uses, which fails on a peer export the installed `@earendil-works/pi-ai` no longer provides) and `PATCHES` (every manifest marker re-grepped against the installed files). Silent and exit 0 while healthy; a failure prints the check, notifies once with the fix command and exits 1. `-v` prints the whole report for a hand run |
| `apply.log` | append-only record of every run, with dry-run output on failure (trimmed to the last 1000 lines past 2000) |
| `FAILED` | present only while the last run had a failure |
| `.apply.lock` | `flock` target, so overlapping runs cannot interleave |
| `<patch>/pre-patch/<name>.<version>` | per-version rollback copy of each target file |

### Environment overrides

`PI_PATCH_MANIFEST`, `PI_PATCH_LOG`, `PI_PATCH_FAILED` relocate the manifest and the records,
`PI_PATCH_NO_NOTIFY=1` silences notifications, `PI_PATCH_RETRY_WINDOW`,
`PI_PATCH_RETRY_ATTEMPTS` and `PI_PATCH_RETRY_WAIT` retune the install-in-flight retry (a
window of 0 turns it off, which is how `selftest.sh` keeps a deliberate failure immediate),
and `PI_PATCH_DOCTOR` relocates the doctor the
run ends with. `selftest.sh` uses those to keep its run out of the real records. The
doctor takes `PI_DOCTOR_MANIFEST`, `PI_DOCTOR_SUB_PKG` and `PI_DOCTOR_PI_BIN` to relocate its
inputs, and `PI_DOCTOR_NO_NOTIFY=1` to silence (and print) its notification — the applier sets
that last one when it already has a failure of its own to announce.

### Rollback

Per entry: `patch -p1 -R -d <package-dir> < <patch>` removes the patch, or copy
`pre-patch/<name>.<version>` back over the target file. Both leave the package exactly as
npm unpacked it.

An entry covers every file its patch names, so restoring one target of a multi-file entry
does not make the entry readable as "not applied" in a useful way: the applier then dry-runs
clean, stages a copy of every target, and refuses (the staged run reports a marker absent)
because the targets that are still patched reverse instead of applying. That refusal is safe
and leaves the package byte-identical, but it is not a repair — restore ALL targets of the
entry (or none of them) from their pre-patch copies, then run the applier once to re-apply it.

## The trigger

Two systemd user units, in `~/.config/systemd/user/`:

- `pi-patch-apply.path` — watches `~/.pi/agent/npm/node_modules`, each scope directory
  whose packages carry a patch, and every one of those package directories
  (`PathModified`): `@juicesharp`, `@juicesharp/rpiv-todo`, `pi-subagents`, `@tinoy`,
  `@tinoy/pi-deepseek-cost` and `@tinoy/pi-fleet`. npm rewriting a package changes those
  directory mtimes, which fires the service. The list has to name every package directory
  in `managed-patches.conf`: a patched package whose directory is not watched is rewritten
  with nothing to fire the service, and is restored only by a hand run of
  `apply-patches.sh`. `selftest.sh` cross-checks the two — it reads the package directories
  out of the manifest and the watch list out of the running unit
  (`systemctl --user show pi-patch-apply.path -p Paths`), so it fails and names the package
  when the two disagree. Registering a patch is therefore two edits in one change: the
  manifest line, and a `PathModified=` line for that package's directory in the unit,
  followed by `systemctl --user daemon-reload` and a run of `selftest.sh`. The scope
  directories (`@juicesharp`, `@tinoy`, `node_modules`) do not cover a package: a watch on
  the parent sees the package directory be created or replaced, not the file writes npm
  makes inside it.
- `pi-patch-apply.service` — `Type=oneshot`, `ExecStart=apply-patches.sh`,
  `WantedBy=default.target` so it also runs at login/boot, `TimeoutStartSec=240` so a run
  has room for the install-in-flight retries and the doctor while still being unable to
  hang a boot, `PrivateNetwork=yes` (the applier needs no network), `NoNewPrivileges=yes`,
  `Restart=no`, and `StartLimitBurst=20`/`StartLimitIntervalSec=120` so a trigger storm ends
  as a failed unit rather than a loop while still being wide enough that a normal update
  cannot leave the last trigger refused. It depends on `basic.target` only — no graphical
  session is required, and it runs with the user manager (`loginctl show-user tinoy -p
  Linger` → `yes`), so it also fires without an interactive login.

Chosen over the alternatives because it survives a package update, needs no shell profile,
and needs nothing remembered by hand. A session-start hook was rejected: pi loads extension
modules at startup, so a restore that lands during that startup cannot be guaranteed to be
seen by the session that triggered it, and a new extension file would add a second mechanism
to maintain. `pi-patch-apply.path` also covers installs that happen outside pi entirely (a
manual `npm update`).

The doctor rides this same unit — it is the last step of `apply-patches.sh`, not a unit, a
trigger or a daemon of its own, so a package rewrite and a login both reach the runner and
host checks with nothing extra to install or reload.

Enablement and checks:

```
systemctl --user enable --now pi-patch-apply.path pi-patch-apply.service
systemctl --user is-enabled pi-patch-apply.path pi-patch-apply.service
systemctl --user is-active  pi-patch-apply.path pi-patch-apply.service
journalctl --user -u pi-patch-apply.service -n 20 -o cat
```

Applying a patch writes into the watched directories, which fires at most one further run;
that run is a no-op because the markers are present again, so the trigger settles.

## Manual use

```
/home/tinoy/.pi/agent/patches/apply-patches.sh      # apply whatever is missing, then the doctor
/home/tinoy/.pi/agent/patches/doctor.sh -v          # the toolchain report, healthy or not
/home/tinoy/.pi/agent/patches/selftest.sh           # verify the applier itself
```

## When a patch takes effect

pi loads both packages at session start, so a restore is visible in the next pi session. A
running session keeps the module it loaded: if pi reinstalls a package during startup, that
same session may still run the unpatched module even though the restore lands moments later.
