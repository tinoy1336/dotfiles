# pi extensions — inventory, spec surface, load scope

What this directory is: every local pi extension on this machine, each one a
TypeScript module that registers tools, commands or hooks against pi's
`ExtensionAPI`. It is also the directory pi **auto-discovers**, which is the
reason this document exists: discovery applies to the interactive session and
does **not** apply to subagent children, so the same directory resolves to two
different extension sets. Nothing else on the machine makes that difference
visible, and the difference has already cost real work (see §2, §7).

Read §1 before §4. The per-extension sections state load scope, and the scope
column is meaningless without the mechanism behind it.

---

## 1. How an extension reaches a session

There are two families. **Discovery** applies to the interactive session and
loads whatever it finds. **Explicit path lists** are how a child gets anything at
all, and there are four settings keys that feed them.

### Ambient discovery — the interactive (parent) session

pi scans these locations and loads what it finds (`docs/extensions.md`):

| Location | Scope |
| --- | --- |
| `~/.pi/agent/extensions/*.ts` | global, all projects |
| `~/.pi/agent/extensions/*/index.ts` | global, subdirectory form |
| `.pi/extensions/*.ts` | project-local, only after the project is trusted |
| `.pi/extensions/*/index.ts` | project-local subdirectory form |

Two more sources feed the same list:

- `~/.pi/agent/settings.json` → top-level `extensions[]` — explicit file or
  directory paths. **Currently empty/absent.**
- `~/.pi/agent/settings.json` → top-level `packages[]` — npm packages, each
  contributing its own extensions through a `package.json` `pi.extensions`
  manifest. Third-party entries: `pi-web-access`, `pi-subagents`, `pi-intercom`,
  `@juicesharp/rpiv-ask-user-question`, `context-mode`, `@juicesharp/rpiv-todo`,
  `cc-safety-net`, `pi-markdown-preview`. The `@tinoy/pi-*` entries are this
  machine's own extensions, published from the `pi-extensions` repository and
  installed under `~/.pi/agent/npm/node_modules/` — see §6.

A subdirectory is an extension unit only if it has an `index.ts` (or a
`package.json` declaring `pi.extensions`). That single rule is what makes
`fleet/` and `io-guard/` extensions while `lib/` and `subagent/` are not. Both of
those subdirectory units now come from the `@tinoy/pi-fleet` package, so nothing
under this directory registers through that rule any more.

### The child allowlist — every subagent session

Children do not inherit the parent's extension set. The decision is made in
`pi-subagents` when it builds the child's argv
(`src/runs/shared/pi-args.ts`, `resolvePiLaunchToolPlan`):

```ts
const disableAmbientExtensions =
    capabilityCeiling?.denyExtensions === true ||
    input.extensions !== undefined;
```

Everything follows from that line:

- `input.extensions` is populated from **`subagents.defaultExtensions`** in
  user settings, attached to every agent that does not declare its own
  `extensions` (`src/agents/agents.ts`, `applySubagentDefaultExtensions`).
- When `disableAmbientExtensions` is true, the child is launched with
  `--no-extensions` — *"Disable extension discovery"* — and the only extensions
  it loads are the paths passed on the command line.
- Those paths are, in order: the pi-subagents runtime extensions (prompt
  bridge, fan-out child extension, the permission-system extension when
  installed), then `toolExtensionPaths` (extensions implied by path-like
  `tools` entries), then `defaultExtensions`, then the agent's own
  `extensions` / `subagentOnlyExtensions`.

`subagents.defaultExtensions` therefore has three distinct meanings, which is
the trap. From pi-subagents' own documentation:

| Value | Effect on children |
| --- | --- |
| **absent** | *"preserves Pi's normal ambient extension discovery"* — children load this whole directory |
| `[]` | `extensions: []` for agents that declare none — ambient discovery off, no extensions at all |
| non-empty | an explicit allowlist replaces ambient discovery entirely |

`--no-extensions` removes **`packages[]` too**, not just the directory. A
package-provided extension (`pi-web-access` is the live example) is absent from
a child unless that agent's `subagentOnlyExtensions` names its path explicitly.
That is why `pi-web-access/index.ts` appears in four agents' lists.

Per-agent additions live in `subagents.agentOverrides.<agent>`:

- `subagentOnlyExtensions[]` — child-only extension paths for that agent.
- `extensions[]` — same field the default-merge writes; declaring it suppresses
  the default merge for that agent.
- `capabilityCeiling.denyExtensions` — when true, every configured extension is
  dropped (and ambient discovery was already off).

**A child process carries one of two launch markers, and an extension that needs
to know it is in a child tests both.** `PI_SUBAGENT=1` is exported by
`~/.local/bin/pi-subagent` and inherited by the pi processes it starts;
`PI_SUBAGENT_CHILD=1` is set in `process.env` by the pi-subagents async runner
before the child it hosts loads any extension. Either marker means the session is
a child — testing only one of them misclassifies every session launched by the
other path. The child-side sections below name the markers they read.

### The current split

- `subagents.defaultExtensions` has **eleven** entries and applies to every child
  of every agent: `child-request-dump`, `child-prompt-freeze`,
  `cache-prefix-log`, `image-read`, `nf`, `command-guard`, `no-subagent-fork`,
  `focus-gate`, `orphan-repair`, `cli-keys`, `pause`. Every one of them is an
  installed package path under `~/.pi/agent/npm/node_modules/@tinoy/pi-*/` — the
  list names the package's entry file, never a file in this directory.
- `agentOverrides.worker.subagentOnlyExtensions` adds **eight** more, worker
  children only: the `context-mode` pi adapter, `pi-web-access`,
  `@tinoy/pi-todo-parent/index.ts`, `@tinoy/pi-drift-anchor/index.ts`,
  `sudo-approve` (the one entry still a local file in this directory, because its
  package is not published yet), `@tinoy/pi-fleet/io-guard/index.ts`,
  `@tinoy/pi-build/index.ts`, and the canon
  package's entry file (`~/.pi/agent/npm/node_modules/@tinoy/pi-canon/index.ts` —
  canon is an installed package, never a file in this directory).
  A worker child is therefore the one child that renders a canon block; every
  other agent's child still renders none.
- `oracle`, `scout`, `researcher` and `delegate` list `pi-web-access` only.
  `reviewer` lists nothing, so a `reviewer` child runs with the ten defaults and
  no extension-provided tools of its own.

---

## 2. The canon regression — children used to load this directory

This section is history, and one line of the present belongs before it: the canon
package's entry file is on `agentOverrides.worker.subagentOnlyExtensions` (§1), so
a worker child loads the store today and renders the `subagent`-audience block,
while no other agent's child does. The section names `canon.ts` because canon was
a file in this directory for the whole period it describes. What follows explains
why the extension had been absent from every child
list, and every statement in it is a statement about the period before that entry
existed.

The claim: children once loaded `canon.ts` and stopped when the foreman v2
design landed. The second half of that is not what the evidence shows. What the
surviving artefacts show is:

**The regression is the introduction of `subagents.defaultExtensions` itself,
and it happened on 2026-09-03 — eleven days before the foreman v2 design was
settled.**

Evidence, all from what is on disk:

1. **The `disableAmbientExtensions` flag is derived, never configured.** There is
   no setting for it. It is `true` exactly when a child carries any `extensions`
   array. So nobody switched ambient discovery off for children; populating
   `defaultExtensions` switched it off as a side effect of an additive intent —
   the intent being to make `image_read` and `nf` reachable in children, both of
   which were in agents' `tools` lists without a loaded extension to register
   them.
2. **The first `settings.json` write carrying `defaultExtensions` is
   2026-09-03T04:25:32Z**, in session
   `2026-09-03T04-03-36-974Z_01a0656f`. It was a whole-file `write`, not an
   `edit`, and the list it wrote was
   `["…/extensions/image-read.ts", "…/extensions/nf.ts"]`. Twenty-four seconds
   earlier the same session's `read` of the same file shows **no**
   `defaultExtensions` key.
3. **Fifty writes and edits to `settings.json` survive on disk, spanning
   2026-08-19 to 2026-09-16.** No write before 2026-09-03 contains the key. Every
   read of `settings.json` recorded from 2026-08-01 through 2026-09-01 (the
   2026-08-25, 2026-08-28 and 2026-09-01 dumps included) shows a settings body
   with no `defaultExtensions`. Before that date, ambient discovery was intact
   for children, so the ambient scan that loads this directory in the parent was
   also loading it in every child — `canon.ts` included.
4. **`canon.ts` was never in the list.** Across every surviving dump of the
   list, from `[image-read, nf]` on 2026-09-03 through `+bash-guard` (2026-09-06),
   `+no-subagent-fork` (2026-09-10), `+focus-gate`, `+cache-prefix-log`,
   `+child-prompt-freeze` (2026-09-12), the `bash-guard` → `command-guard` rename
   (2026-09-14), `+orphan-repair`, `+child-request-dump` (2026-09-15) and
   `+cli-keys` (2026-09-16), `canon.ts` never appears. It was never removed,
   because it was never added: the list was built for tool reachability, and
   canon was not a tool anyone needed in a child. It was added to the worker's
   list after those dumps, which is the entry §1 and §3 now record.
5. **The design did not cause it; it recorded it.**
   The foreman design record, since retired, is dated "decisions settled
   2026-09-14" and states, as a constraint to design around, *"Children never
   load canon. Every rule a hired worker must follow has to be spelled out
   verbatim in the dispatch brief, since the brief is the only instruction
   channel a child receives."* The same reading appears in canon itself as
   entry `vofymv`, attributed to the user on 2026-09-13. Both are descriptions
   of a condition that already existed, written after 2026-09-03.

**Why the audience branch exists.** The canon package carries
`type Audience = "all" | "parent" | "foreman" | "subagent"` and selects the
session's own audience set from the process environment (§4.3). The branch was
written for children, and it stopped receiving traffic when the child allowlist
was introduced: the module's extension entry point did not run in a child, so no
child matched an audience scope at all. The store reflects the same intent —
entries scoped `audience: "subagent"` and `audience: "all"` exist to reach
children — and they reach a worker child again now that the canon package is on the
worker's list. A child of any other agent still matches none of them.

Caveat, stated plainly: the evidence establishes the *mechanism* from source and
package documentation, and the *date* from 50 recorded settings writes plus the
preceding reads. It does not contain a recording of a child process that loaded
`canon.ts` before 2026-09-03 — child sessions from that period were not dumping
their extension sets. The inference that they did is the only reading consistent
with "absent → ambient discovery preserved"; it is not a direct observation.

---

## 3. Inventory

`Child` means a subagent child of any agent; `worker child` means a child of the
`worker` agent, which is the only agent carrying extra paths.

Read every file name in the table below as the package's ENTRY FILE, not as a
file in this directory: the set is consumed as nineteen published packages
(`@tinoy/pi-*`, listed in settings `packages[]`) plus `sudo-approve.ts`, which
is still a local file. §6 names the packages and the two data files they read
from this machine.

| Entry | Registers | Parent | Child | Deciding mechanism |
| --- | --- | --- | --- | --- |
| `build.ts` | `build` tool | yes | worker only | ambient + `worker.subagentOnlyExtensions` |
| `cache-prefix-log.ts` | hooks only | yes | yes | `defaultExtensions` |
| `@tinoy/pi-canon` (installed package) | `canon_add/edit/remove/category`, `/canon`, `/canon-dump` | yes | worker only | settings `packages` (`npm:@tinoy/pi-canon`) + `worker.subagentOnlyExtensions` |
| `child-prompt-freeze.ts` | hooks only | yes (no-op) | yes | `defaultExtensions` |
| `child-request-dump.ts` | hooks only | yes (no-op) | yes | `defaultExtensions` |
| `cli-keys.ts` | `/cli-keys` (`refresh`\|`status`) + hooks | yes | yes | `defaultExtensions` |
| `command-guard.ts` | `tool_call` hook | yes | yes | `defaultExtensions` |
| `deepseek-cost.ts` | footer renderer | yes | no | ambient only |
| `desktop-notify.ts` | `desktop_notify` tool | yes | no | ambient only; on no child list, and self-disables on either child marker or `hasUI === false` |
| `drift-anchor.ts` | `set_anchor` tool, `/anchor`, 4 hooks | yes | worker only | ambient + `worker.subagentOnlyExtensions` |
| `fleet/index.ts` | `fleet` tool; foreman arming (`PI_FOREMAN=1` read at `session_start`, the `pi-foreman` launcher's marker) plus the `foreman-off` escape command | yes | no | ambient only |
| `focus-gate.ts` | `tool_call` + `context` + `session_start`/`session_shutdown` hooks, `/focus` | yes | yes | `defaultExtensions` |
| `image-read.ts` | `image_read` tool | yes | yes | `defaultExtensions` |
| `intercom-broadcast.ts` | `broadcast` tool | yes | no | ambient only |
| `io-guard/index.ts` | `io_status` tool + write hooks | yes | worker only | ambient + `worker.subagentOnlyExtensions` |
| `nf.ts` | `nf` tool | yes | yes | `defaultExtensions` |
| `no-subagent-fork.ts` | `tool_call` hook | yes | yes | `defaultExtensions` |
| `orphan-repair.ts` | `before_provider_request` hook | yes | yes | `defaultExtensions` |
| `probe.ts` | `probe` tool | yes | no | ambient only |
| `read-staleness.ts` | `tool_result` hook | yes | no | ambient only |
| `status-metrics.ts` | footer renderer | yes | no | ambient only |
| `sudo-approve.ts` | `sudo_approve` tool | yes | worker only | ambient + `worker.subagentOnlyExtensions` |
| `todo-parent.ts` | `todo_parent` tool | yes | worker only | ambient + `worker.subagentOnlyExtensions` |
| `lib/*.ts` | nothing | n/a | n/a | not an extension unit — see §5 |
| `subagent/config.json` | nothing | n/a | n/a | pi-subagents config, not an extension — see §5 |

Totals: 21 top-level `.ts` units, 2 subdirectory units (`fleet/`, `io-guard/`),
and a child set of 10 (defaults) + 0–8 (agent-specific).

---

## 4. Per-extension detail

### 4.1 Loaded by the parent and by every child

**`cache-prefix-log.ts`** — permanent prompt-cache prefix logger.
One JSONL row per session baseline and per prefix change, on
`before_provider_request`: `systemHash` / `toolsHash`, the run-start path that
built the request (`origin: prompt | injected`), and which tool names entered or
left the provider `tools` array. The fingerprint is computed one macrotask after
the hook because later handlers may canonicalise the system prompt in place, so a
row always describes the bytes that actually left the process. Observation-only
by contract: registers no tool, never calls `setActiveTools`, stores hashes and
sizes rather than content, and swallows its own faults so a logger can never
break a request. A row's `sess` field is the FULL session id, never a truncation
of it: a session id begins with the high 32 bits of its millisecond timestamp, so
a short key is shared by every session started inside the same ~65 s window and a
row could not be attributed to exactly one session. The log answers PREFIX
questions only — which bytes moved, by how much, and on which run-start path — and
never token questions: its rows are written where only the outgoing payload exists,
so no token or cache figure is observable at that seam. Those numbers live at the
`message_end` seam (`message.usage`, which `deepseek-cost.ts` reads), and a row that
needs them belongs there rather than widened here.
*Spec:* log `$XDG_STATE_HOME/pi/cache-prefix-log.jsonl`, capped 256 KiB with one
rotated sibling `cache-prefix-log.1.jsonl`; `PI_CACHE_PREFIX_LOG` overrides the
path (test/debug only); reads `XDG_STATE_HOME`.
*Attribution:* a consumer attributes a row to a run by that full session id, read
from the run's OWN transcript header (a subagent transcript is always
`…/<childRunId>/run-0/session.jsonl`, so a name-derived key is one constant for
every run), with the run's pid as the second arm. Matching is exact: a legacy row
carrying only a truncated id is not read as a prefix match — a truncation cannot
distinguish the sessions it is shared by — so such rows stay attributable through
the pid arm.

**`child-prompt-freeze.ts`** — prompt-cache invariance for child sessions.
A child's system prompt is built by the launch/resume `prompt()` path, where
pi-subagents rewrites it; a run started by an injected message never fires that
path and would otherwise carry the unrewritten base prompt, re-billing every
token after the divergence. This pins the bytes observed on a rewritten request
and restores them on any request arriving without them. Adopt-only: it does not
reimplement the rewrite, so a pi-subagents update cannot make the repair wrong.
Idempotent, one memoized string per process.
*Spec:* registers nothing unless a child marker is set — one guard tests both
(`PI_SUBAGENT` and `PI_SUBAGENT_CHILD`), so its ambient load into the parent is a
deliberate no-op; logs `child-prompt` lines to the shared hook log.
*Hazard:* it imports `systemPromptSlot` from `@tinoy/pi-ext-lib` — see §7.

**`child-request-dump.ts`** — structure-only record of every outbound provider
request in a child. One JSONL row per request holding the message roles in
order, the tool-call ids each assistant message declares, and the id each result
answers. It exists to make the `400 … role 'tool' must be a response to a
preceding message with 'tool_calls'` class diagnosable, so it records the shape
that triggers it and never the content: no prompt text, no message text, no tool
names, no arguments.
*Spec:* log `$XDG_STATE_HOME/pi/child-request-dump.jsonl`, capped 256 KiB with
one rotated sibling; `PI_CHILD_REQUEST_DUMP` overrides the path; a child marker
(`PI_SUBAGENT` or `PI_SUBAGENT_CHILD` — §1) is what it registers on, and it
registers nothing unless one of them is set.
*Interaction:* rows are built before `orphan-repair.ts` rewrites
`payload.messages` later in the handler order, so a row shows the sequence pi's
converter produced — which is the sequence the provider sees when no repair is
loaded.

**`cli-keys.ts`** — provider API-key hydration.
`~/.local/bin/cli-keys` fetches provider keys from the Proton Pass vault into a
mode-600 cache under the XDG state directory (`~/.local/state/cli-keys/cache.json`
by default); this hook copies that cache into `process.env`, which is the command's
first branch and the environment every spawned tool child inherits. The path is
**state, not runtime state** — `$XDG_RUNTIME_DIR` is a tmpfs and loses the file at
every boot — and it has exactly ONE definition: the script owns it and answers
`cli-keys cache-path`, which this hook and `pi-foreman` both read instead of a
literal of their own. Hydration deliberately does **not** decide a launch:
pi builds the model runtime before any extension exists, so the hook only warms a
later refresh. What keeps providers listed is the command form in `models.json`
(`"apiKey": "!<path>/cli-keys key <NAME>"`), which pi counts as configured
without running it. Because that command is never run to decide availability, the
hook checks it when hydration writes nothing, and speaks exactly once — one UI
notice where there is a UI, one stderr line where there is not — if none of them
can produce a value. It never prints a credential or cache content.
*Operating surface:* `/cli-keys refresh` runs the script's `ensure --json --force` and
re-hydrates this process; `/cli-keys status` (the no-argument default) reports the cache's
state against this process's own copy of it, naming the keys whose environment value
differs from the cache. Neither prints a value. `--force` skips the cache's freshness short-circuit
ONLY — the offline gate stays, so an offline machine is reported `offline` with its
cache untouched — and the command reports whether a fetch actually LANDED: a script
that does not honour the flag answers `fresh`, which a forced run can never be, and the
command then says no fetch ran instead of reporting a refresh that never happened.
*Generation following:* the environment holds the generation this process hydrated at
load, and a fetch by ANOTHER writer (the refresh service, an operator's own `cli-keys`,
a forced refresh in another process) cannot reach it — `cli-keys key NAME` prints the
environment's value first, so that stale copy is what every tool child of the process
receives. The hook therefore watches the cache's DIRECTORY (the fetch commits by
rename, which ends a watch on the replaced inode) and re-reads on every write by any
writer; that path never fetches, because its writer just produced the generation being
read.
*Serving rule:* the cache's own expiry decides only WHEN TO REFRESH. An expired
cache is still served — an hours-old credential resolves a request and an absent one
does not — so an offline boot keeps the credential it had, and no failure path
truncates, rewrites or removes a cache a fetch could not replace.
*Refresh without a session:* `cli-keys-refresh.service` (user unit, enabled) runs
`cli-keys watch`, which holds `nmcli monitor` open and reconciles on every
connectivity transition, with a sweep between transitions; it is what refreshes a
machine that came back online, instead of waiting for the next pi session. The hook
still refreshes opportunistically when it loads or a session starts, and reports the
script's own outcome (`refreshed` / `fresh` / `offline` / `failed`) in its hook-log row. A
session the vault no longer accepts is rebuilt from the staged token: `pass-cli login`
refuses while a local session record exists (`Already authenticated`), so the bootstrap
drops that record with `logout --force` and logs in once more — without that step a VALID
token cannot heal a lapsed session, and every sweep fails silently because the failure
class sits outside the notice pattern.
*Vault session:* the vault client (`pass-cli`) keeps its session in a database
encrypted by a LOCAL key, and where that key is stored decides whether the session
outlives a reboot. The Linux default is the KERNEL keyring, which is cleared at boot —
pass-cli then finds local data with no key and forces a logout, which is the state that
answers every vault call with `This operation requires an authenticated client`. The
script therefore exports `PROTON_PASS_KEY_PROVIDER=fs`, keeping the key in
`~/.local/share/proton-pass-cli/.session/local.key` (mode 600); an explicit value in
the environment wins. EVERY pass-cli invocation for this credential needs the SAME
store: another backend cannot decrypt the existing session database and forces that
same logout, so a shell or unit that runs `pass-cli` itself must carry the variable
too.
*Credential rejection notice:* a fetch that fails because the vault REFUSED the
credential (no active session, `requires an authenticated client`, a `401`, a local key
that no longer opens the session database) is a different event from a network failure
or a missing vault item, and it raises ONE desktop notification through `notify-send -u
critical` naming the failure and the login command that fixes it — the token goes in
`PROTON_PASS_PERSONAL_ACCESS_TOKEN`, never on a command line. It fires from the script
(inside `cli-keys-refresh.service`, and from a hook-triggered `ensure`), carries no
fragment of the credential, and is rate-limited by a state file (`<state
dir>/cli-keys/rejection.json`): one notice per state change, at most one per 12h, and
re-armed by any refresh the vault accepted. The RETRY decision reads a WIDER predicate than
the notice: a session the vault no longer knows (`non-existent session`, `failed to
authenticate`) is re-logged-in from the token and, being healable, raises no notice — the
notice is reserved for a refusal the operator has to fix.
*A rejected credential is the ONLY renewal signal:* there is NO client-side expiry
tracking — nothing watches the credential's age, schedules a renewal or warns ahead of
it, and no expiry timer belongs on this path. The token is a year credential and the
watcher reacts only to a real rejection; the cache's own `expires_epoch` governs the
CACHE (when to refetch), never the token.
*Spec:* runs `cli-keys` (`cache-path`, `ensure --json [--force]`, `key`); registers
`/cli-keys refresh|status`; watches the cache directory for a new generation; reads
`models.json`, `HOME`, `PI_CODING_AGENT_DIR`; logs `cli-keys` lines to the shared hook log.

**`command-guard.ts`** — R1/R2 + RAW-INPUT enforcement hook.
A `tool_call` hook with two rule families. **RAW-INPUT** covers `bash` and the
three `ctx_*` sandbox tools: raw synthetic-input invocations are blocked and
redirected to the `inject` wrapper, because the harm is a *held* button, not the
injection — `ydotool click 0x40` presses BTN_LEFT with no release, and every real
left click on the machine is ignored until the release lands. The rule reads
whatever text the tool would execute (bash `command`; ctx `code` /
`commands[].command`) because an `execSync` inside sandboxed code reaches the
same binary without passing through bash. An invocation means the name in command
position followed by one of its subcommands, so `command -v ydotool`,
`pkill -f ydotool` and prose naming it pass, while `… ; ydotool click …` and
`execSync('ydotool click 0x40')` block. `ydotoold` is never matched, so daemon
management stays available, and the marker `raw-ydotool-ok` is the deliberate
escape hatch. The sanctioned path is `~/.local/bin/inject`, which releases
anything already held before acting, pairs each press with its release, releases
again from an EXIT/INT/TERM trap, and refuses an unbalanced `key` sequence;
`inject status` probes, `inject release` repairs, `--require-focus CLASS`
aborts unless that window class is active, `--dry-run` prints the plan.
**R1/R2** (bash only) block file-content bypasses (`cat`, `sed -n 'a,bp'`,
`head`/`tail` on files, `grep <pat> <file>`) and raw build/checker commands
(`tsc`, `npx tsc`, `makepkg`, `npm run|test|build`, `ags bundle`, `go|cargo
build`, `make`), returning one-line redirect guidance. It skips segments with
pipes/redirects/heredocs/`$`vars/globs and allows `tail -f`.
*Spec:* blocks are logged to `~/.local/share/pi-hooks/log.jsonl` under source
`command-guard` (rows predating the RAW-INPUT family carry `bash-guard`;
`status-metrics.ts` counts both) and read back by the pi-tool-burn report.
Redirect contracts name a tool the calling session actually has: file content →
`read`; search → `ctx_execute` or the `grep` tool — **the `grep` tool exists in
subagent sessions but not in the interactive session**; build/checker → the
`build` tool. The transform-pipeline exception never applies to grep/rg, whose
explicit-path and `-r` forms are rejected before the transform gate, so
`grep -rn x . | sort` is blocked too; `rg --files` is allowed because it lists
names. Wrapper prefixes are unwrapped with their operands (`timeout [opts] DUR
cmd`, `env [opts] VAR=value cmd`) — skipping only the wrapper word made the
operand the command name and let a 48 KB build dump through. `sudo`'s own option
operands are still not skipped.
*Regression fixtures:* `~/.local/bin/pi-guard-probe` runs two fixture tables
against the real extension through `inspect()` and `inspectInjection()`, reports
any verdict change in either direction, and flags accepted holes marked
`known: true`. Run it after every edit to this file.

**`focus-gate.ts`** — desktop-intrusion gate and focus footer.
Two states, `on` and `off` (the earlier quiet/locked split enforced the identical
deny-list, so it was collapsed; a legacy state file still reads correctly, both
old gated names mapping to `on`). State is re-read fresh from
`$XDG_RUNTIME_DIR/pi-focus.json` on every tool call, so a toggle gates every
running session from its next call; a session already streaming finishes its
preflighted batch.
*Footer:* the segment carries ONE glyph (`\uf256` fa-hand) while the mode is on,
and is CLEARED while it is off — OFF passes `undefined` to `setStatus`, never an
empty string, which would reserve the segment and render a gap. Every render path
(the toggle handler, the per-turn `context` re-sync, the state-file watcher and
`session_start`) goes through `syncFooter`, and `session_shutdown` clears
unconditionally.
*Gated tools:* `bash`, `ctx_execute`, `ctx_execute_file`, `ctx_batch_execute`
(its `commands[].command` entries — there is no top-level `command`, so a flat
read gated nothing) and `probe` with `hyprctl: true`. Every deny-list entry is
tested against each text the call carries.
*Blocked:* every `hyprctl dispatch` (on 0.56 the working form is Lua, so
argument-shape patterns match almost nothing), `hyprctl keyword`, screenshot
tools (`grim`, `grimblast`, `hyprshot`, …), input injection — the raw tools
**and** the `~/.local/bin/inject` wrapper, which is the sanctioned front end —
`gtk-launch`, terminal emulators (`kitty`/`alacritty`/`foot`/`wezterm`/`ghostty`,
matched at command position so `find kitty -type f && …` is not a false
positive), `run.sh <app>` (the `AGS_BUNDLE_WARM=1` build-only form passes through
the entry's `unless` regex), `ags run`, and `ags`/`ags-route.sh` open/toggle
requests. Notifications are never gated.
*Propagation:* the state file carries the mode, and every session process also
WATCHES that file (`watchFocusState` in `lib/focus-state.ts`): on a change it
re-syncs its own footer from the file and ALERTS itself with the toggle notice,
which WAKES an idle session — the flip is known the moment it happens, not at
the next user prompt. The watch survives a replace of the state file (the
directory is watched and every event is
re-read, never interpreted), coalesces two quick writes into one re-read, and is
stopped at `session_shutdown`. The pi-intercom `focus` channel is the FALLBACK for
the peer notice, not the mechanism the sync depends on: a broker that is down, or
a publish failure, costs only that notice — the file still gates everything and
each session still re-syncs itself (`hookLog` source `focus-gate`, kinds
`broadcast-failed`/`broadcast-skipped`/`notice-failed`/`state-change`/
`ledgers-cleared`). The `context` handler re-syncs its own footer per turn as
well, so a session whose watch cannot start still tracks the file instead of
showing a stale indicator. The toggle never STEERS: delivery is `sendMessage`
with `triggerTurn: true` and `deliverAs: "followUp"`, so an idle session STARTS A
TURN on the notice while a streaming session takes it on the agent's follow-up
queue — never on the STEERING queue, the one the user's own typing occupies. Both
directions alert — ON is no longer silent — and both roads (the state watch and
the channel) announce through one `<mode>|<since>` key in `announceMode`, so one
toggle is one notice per session however it arrived. Accepted cost of the alert:
one turn per open session per toggle, which is why the notice opens by naming
itself a MODE CHANGE and not user work. The mode is restated as a `[focus]`
**tail message** on the `context`
event, never in the system prompt, because replacing the system prompt re-encodes
the cached prefix from its first token. Its "already stated" guard is mode-aware,
so an off→on flip is always restated, and the ON notice carries the rule text so
the guard suppresses the duplicate tail statement in that turn.
*Spec:* state `$XDG_RUNTIME_DIR/pi-focus.json`; deferred actions ledger — ONE PER
SESSION PROCESS, `$XDG_RUNTIME_DIR/pi-focus.<session id>-<pid>.ledger.jsonl`, named
by `focusLedgerPathFor`. The pid is in the name because `PI_SESSION_ID` is
inherited by a pi launched from inside a pi session, so the id alone could not
keep two session processes apart. A session appends only to its own ledger and
reads back only its own: the gate writes the file it blocks into, `/focus status`
reports that session's count, and the footer's queued counter reads the same file
— a peer's blocked attempts are never visible here. A ledger row carries no
session id: its file name names the session, and the paired hook-log row carries
the `proc` that attributes it to a child. The `/focus` repertoire is
`[on|off|status]`, no args toggles, `quiet`/`locked` accepted as legacy aliases
for `on`. The release summary of `/focus off` reports THIS session's own attempts
and prints before anything is cleared; the clear itself is all-at-once —
`clearFocusLedgers` enumerates the runtime dir and removes every ledger it finds,
so no session is left rendering a stale count and a session that already exited
leaves nothing behind.
*Load note:* reachable by children only through `subagents.defaultExtensions`,
which makes enforcement hang on that one settings entry — see §7.

**`image-read.ts`** — vision-token-aware image ingestion.
Returns a prepped image inline as tool-result content, so no second read call is
needed: downscale the long edge to `max` px (default 1024, `0` passes through),
optional crop `"WxH+X+Y"` (tokens track area, so cropping beats resizing), auto
re-encode of huge opaque PNGs to JPEG q85, content+args cache, and a token
estimate of pixels/784 (GLM-V 14px patches, 2x2 merge).
*Spec:* registers for every session and is **active by default** — the tool is
registered active, so the vision gate only ever NARROWS: a `session_start`
handler removes it in sessions whose model cannot read images
(`VISION_MODEL_IDS`), and only a real CHANGE of model may add it back
(`model_select`, gated on `event.previousModel`, so the selection a session
starts with — a restored one included — never widens a set another extension has
already settled). An absent `image_read` at session start therefore means another
owner set that session's tools and is left alone: re-adding it would rebuild the
base system prompt for a tool that carries a `promptSnippet` and a
`promptGuideline`, after that set had already gone out with request 1, and the
owner's own enforcement — fleet's foreman mode, the only other
`setActiveTools` caller in this directory — removes it again at the first tool
call. Two rebuilds of a frozen prefix, the later one re-billing everything from
the top. Cache under `$TMPDIR/pi-img-cache`; reads `HOME`.
*Why it is on the child list:* vision models in child roles needed the tool and
its absence is what motivated introducing `defaultExtensions` at all — the change
that caused §2.

**`nf.ts`** — Nerd Font glyph reference tool.
`search <kw>` returns name rows from the dataset (names are the only key; there
are no upstream tags); `sheet <code|name>…` renders a PIL contact sheet with
in-pixel labels and is **vision-gated**, with a text-only fallback for non-vision
models; `audit [dir]` scans `.ts`/`.tsx` for `\uXXXX` escapes, validates them
against the dataset and flags PUA codepoints (0xE000–0xF8FF) that are unassigned,
catching f3e2-class dead glyphs. The dataset lives outside the ags repo
deliberately, to keep the 290 KB / 10,995-glyph table out of app bundles.
*Spec:* dataset `~/.pi/agent/data/nf/nf.json`; reads `HOME`.

**`no-subagent-fork.ts`** — makes `context: "fork"` impossible for subagent
spawns, in two layers because a fork can be requested two ways. Implicitly, an
absent `context` resolves through `defaultSubagentContext`, which falls back to
fork whenever the parent is persisted and leaf-capable — killed at the source by
`extensions/subagent/config.json` (`"fresh"`). Explicitly, `context: "fork"` on
the call or inside a `workflowScript` is rewritten to `"fresh"`, since
`event.input` is mutable and the spawn still succeeds. A `workflowScriptPath` is
read (never mutated) and blocked, because the caller's source is not ours to
edit. Nothing is ever blocked that could have been rewritten.
*Spec:* audit trail `~/.local/share/pi-no-subagent-fork/log.jsonl`.
*Gap:* `action: "resume"` replays a stored run's own context, so a run created
while forking was allowed still continues its fork; new runs cannot.

**`orphan-repair.ts`** — drops an orphaned tool result from the outbound
request. The defect is established, not suspected: the stored history is clean
(0 orphans in 23/23 dead run histories) yet providers reject with `400: Messages
with role 'tool' must be a response to a preceding message with 'tool_calls'`, so
the orphan is introduced while the request is assembled. `pi-ai`'s
`transformMessages` drops any assistant message whose `stopReason` is `"error"`
or `"aborted"` — taking its tool calls with it — while the `toolResult` branch
appends results unconditionally. A dangling result that duplicates an answer
already inside the run replaces that answer in place, so the repair never trades
a real tool result for pi's synthesised placeholder; anything else is dropped and
one line is logged.
*Spec:* logs `orphan-repair` lines to the shared hook log. Observation point is
`before_provider_request`.
*Interaction:* this is the mitigation for the `drift-anchor.ts` defect in §7, and
the reason `child-request-dump.ts` is useful — it captures the sequence this hook
repairs.

### 4.2 Loaded by the parent only

**`deepseek-cost.ts`** — session cost in USD and CNY, peak/valley aware.
pi prices a model with one flat `cost` object and prints it with a hardcoded `$`,
so neither the second currency nor DeepSeek's peak/valley tariff can be expressed
there; this extension owns the authoritative numbers. It prices every assistant
message at the tariff in force **at that message's own timestamp**, so a session
crossing window boundaries accumulates correctly instead of re-pricing history,
and shows the running total in the footer as `$x.xxxx ¥x.xxxx peak|valley`.
Tariffs come from `extensions/tariff.json`, as data: one row per price window and
one column per currency, read by `lib/tariff.ts`, with the real rates in no source
file at all. Peak doubles every figure in both currencies, and peak is Beijing
time Mon–Fri 09:00–12:00 and 14:00–18:00; weekends and everything else are valley.
It prices on the message's own model when that model declares one, so a foreign
model's message in a batch is never priced as Flash.
*Spec:* reads the tariff table from `lib/tariff.ts` (which owns the file read, the
`PI_TARIFF_CONFIG` override and the refusal: an unconfigured or unreadable table
prints no figure rather than a wrong one); `models.json` carries a
**zeroed** `cost` row for Flash so pi's own static `$` figure does not compete
with the tariff-aware one (restoring the original USD numbers is a one-line
change); regression probe `~/.local/bin/pi-cost-probe` covers window boundaries,
both currencies' unit prices, a crossing session and foreign-model exclusion.

**`desktop-notify.ts`** — the `desktop_notify` tool plus automatic
notifications. It pings when a response settles and when `ask_user_question` is
invoked, so the agent need not call the tool at the end of every round; it is
skipped when the agent already sent a manual notify during the run, in
subagent/headless sessions, and when another run is queued behind the settled
one. A manual call is for what the automatic pings cannot cover — a
pre-intrusive-action heads-up, a failure or error needing the user's action, or
anything needing attention mid-turn. Body-only by user policy: the message
alone, never a title or a `Pi — ` prefix, which means `notify-send` receives an
empty summary — the only form that renders no title line. A manual mid-stream
interrupt settles the run without a real response and is not pinged. Urgency is
`critical` only for things demanding immediate action; routine completions are
`low`, input requests `normal`. Notifications are deliberately not gated by
focus mode, because the user still wants the ask-for-eyes ping; only the routine
per-response ping is suppressed.
*Spec:* self-disables in a child session and in a session with no UI — the guard
is `PI_SUBAGENT === "1" || PI_SUBAGENT_CHILD === "1" || !ctx.hasUI` — reads
`lib/focus-state.ts`; debug log `/tmp/pi-notify-debug.log`.
*Load scope:* parent only, and not by accident. The file appears in no child list,
so no child loads it at all, and the `!ctx.hasUI` clause covers the second route
anyway: a child session binds extensions with no UI context, so `hasUI` is false
there as well.

**`intercom-broadcast.ts`** — adds a `broadcast` tool that sends one message to
every connected pi-intercom session on this machine (skipping the current one),
delivered over pi-intercom's extension bus on namespace `broadcast`; each
recipient with this extension loaded injects it into its own stream through
`pi.sendMessage`, the same path a normal intercom send uses.
*Spec:* requires `pi-intercom` installed and its broker running
(`intercom({action: "status"})` ok), and a session (re)start after installing the
file.

**`probe.ts`** — bounded status probe; one call replaces the systemctl +
journalctl + pgrep bash clusters. A **unit** (`foo.service|target|timer|socket|
path|scope`) gets `systemctl --user is-active` plus the last N journal lines
(default 10, max 40) and a pgrep match count; a **process** gets a capped
`pgrep -af` (≤20 lines); `hyprctl: true` runs `hyprctl <args>` capped at ≤40
lines / 4 KB.
*Spec:* all output hard-capped at 4 KB, read-only, no sudo, 10 s timeout per
subcommand; `hyprctl: true` is one of the focus gate's gated call shapes.

**`read-staleness.ts`** — repeat-read elision hook. A `tool_result` hook that can
modify: when a **full** read (no offset/limit) targets a path already read this
session with the same size and mtime, the body is replaced by a one-line stub
naming size, mtime and age. Slice reads are always answered in full. Guards:
`read` only, never errors, `MIN_BYTES` 4000, at most 2 stubs per path per
session, state cleared on `session_start` and `session_compact` (a
post-compaction stub would withhold content no longer in context), LRU cap 64
paths. It observes results rather than wrapping or patching the `read` tool.
*Spec:* stubs logged to the shared hook log under source `read-staleness`.

**`status-metrics.ts`** — footer counters in pi's own idiom (symbol + value, no
labels), read from the shared hook log, tailed incrementally and filtered to the
process that wrote each row (`proc`, the identity `lib/hook-log.ts` stamps)
because subagents and other pi windows share the file and an unfiltered count
would be meaningless. A `sid` match is never a fallback: `PI_SESSION_ID` is an
INHERITED env var, so a pi launched from inside a pi session carries its parent's
value and the id cannot separate two session processes. Legend:
`\uf05e` fa-ban = blocked tool calls (command-guard + focus-gate) ·
`\uf13d` fa-anchor = drift-anchor injections · `\uf1b8` fa-recycle = bytes kept
out of context by repeat-read elision ·
`\uf04c` fa-pause = desktop actions focus mode has queued in THIS session. Values
render only when non-zero; cosmetic by contract, with every path wrapped. Glyphs
need a Nerd Font.
*Spec:* reads `~/.local/share/pi-hooks/log.jsonl`, matching each row's `proc`
against this process's own pid, and this session's own focus ledger through
`focusLedgerPathFor` (`lib/focus-state.ts`);
it re-renders on the `focus:state-changed` event, so the queued counter follows a
release clear made in any session, and it counts a blocked call only for a row
whose `kind` is `block` (the same source also logs diagnostics that block
nothing).

**`fleet/index.ts`** — the foreman crew tool, for foreman sessions only.
One action-style tool that **replaces** the raw `subagent` tool while foreman
mode is on: every crew action is addressed by worker name (the tool owns the
name → async-run-id map), idle time is measured and the warm-reuse decision is
made here rather than by the model, task text is serialised by the tool, claim
ownership is checked, retirement is a state transition GUARDED by the worker's own
board rows (`retire` refuses while any row attributed to that worker is still
`pending` or `in_progress`, and reconciles the board only once every one of them
is `completed`), reviews go to a warm
non-author crew member, and `handoff` / `adopt` publish a crew so a successor
session can take it over. `adopt` waits for a predecessor that is still alive to
exit before it refuses (bounded: 1 s first interval, 1.5× backoff capped at 8 s, a
105 s ceiling), because a successor is normally opened while its predecessor is
finishing its last reply; the wait only re-reads the liveness proof, and every
mutation of the adoption happens after that verdict. Its roster and adopt rows also
report, per worker, what that worker's LAST run left behind — state, end time and
the artifact locations the run's own record carries, never a report the worker
authored — and everything that settled after the publishing sheet's stamp, which is
a RE-RUNNABLE read: the roster answers "what landed since I took over?" on any later
call, not only at adoption. Every launch is async and `context: "fresh"` —
`launch.ts` is the only caller and carries no fork path. A non-foreman session
does have its tool set touched: the tool is registered in every session, and
`session_start` removes `fleet` from the active set unless that session's own
mode file says ON or the session arrived with `PI_FOREMAN=1`; a session that
qualifies either way re-arms the fixed foreman set. A failed activation leaves
the previous tool set in place and the mode OFF.

*Entry point.* `~/.local/bin/pi-foreman` is the launcher, and it is the only way
in: it sets `PI_FOREMAN=1` (the literal `1`, overwriting any
inherited value), strips the five inherited crew-identity markers (`PI_SUBAGENT`,
`PI_SUBAGENT_CHILD`, `PI_SUBAGENT_PARENT_SESSION`,
`PI_SUBAGENT_EXTENSION_BINDINGS`, `PI_INTERCOM_SESSION_ID`), keeps
`PI_SUBAGENT_PI_BINARY` and `PI_SUBAGENT_CACHE_RETENTION` — the strip is
ENUMERATED, never a prefix — seeds the provider keys from the cli-keys cache
(the path cli-keys reports, expired entries included), and
execs pi with the caller's arguments plus the brief as the first message (`--brief
<file>` reads it from a file, `--dry-run` prints the argv and the environment
changes without exec'ing). It arms nothing itself: `session_start` reads the
marker and, unless `PI_SUBAGENT_CHILD=1` marks the process as a crew worker,
arms the mode in one transaction — writing the mode file, swapping the tool set
and emitting the canon section stay the extension's job, which a shell cannot
reach. The same branch re-arms a session whose own mode file still says ON, which
is the state an aborted handoff leaves behind.
*Escaping.* `/foreman` is retired: the command is unregistered, so its `off` /
`stand down` vocabulary went with it, and the one registered command is
`foreman-off` — argument-free, it clears the injected section and calls
`mode.deactivate`, the escape for a session that re-armed from a mode file without
meaning to be a foreman.
*Not yet exercised* (each needs an interactive session to observe, so all three
are reasoned, not measured): the TUI's command listing for `foreman-off`, whose
dispatch alone was proven headless; the escape's mid-session cost, which is a tool
array change and therefore re-bills the remaining conversation once, never checked
against a live billing footer; and a launcher-armed session that escapes and then
`--continue`s inside the SAME launcher-started process, which re-arms from the
marker by design.
*Roster context figures.* The `roster` row reports the worker's CURRENT context
fill, not just its spend: `context` renders `553k/1.0M (55.3%)` — the newest
request's prompt size (`input + cacheRead`) over the model window the newest run
was launched with — with `contextFill` and `contextLimit` as the raw pair,
`contextHighWater` as the peak that must never be read as current usage, and
`spentTokens` as the cumulative figure the fatigue flag keys on
(`fatigueBasis: "spentTokens >= 800000"`). The fill is read from the run's OWN
artifacts — the run record's `sessionFile`, last usage entry — never summed
across runs, because every run of one worker identity appends to the same lineage
transcript. Reasoning, arithmetic and the run-record fallback: `fleet/AGENTS.md`
§Usage, context fill and fatigue.
*Spec:* entry `fleet/index.ts` plus 12 modules (`adopt`, `board`, `items`, `launch`, `mode`,
`predicates`, `release`, `retire`, `roster`, `section`, `status`, `config.json`) and four
runnable probes (`status.probe.ts` beside `status.ts`, `predicates.probe.ts`,
`release.probe.ts`, `board.probe.ts` — loaded by neither pi nor
any session, run by hand; `board.probe.ts` is the one that loads `board.ts` through
`jiti`, because that module imports the rpiv-todo package's TypeScript and plain
type-stripping refuses node_modules); command
`foreman-off` (argument-free escape; `/foreman` is retired and unregistered);
config `fleet/config.json` →
`reuseWindowSeconds` (the user-set prompt-cache reuse window, whose value exists in
no other file: not in code, refusal text, tests or a spec); reads `HOME`,
`PI_MODEL`; imports `../lib/tool-header.ts`, `../io-guard/claims.ts`.
*Detail:* `fleet/AGENTS.md` is the long-form spec for this subsystem.

### 4.3 Loaded by the parent and by worker children only

**`@tinoy/pi-canon`** — the canon store, an installed package named by the
`packages` list in `settings.json` (`npm:@tinoy/pi-canon`, entry file
`~/.pi/agent/npm/node_modules/@tinoy/pi-canon/index.ts`): tool-managed binding
system-prompt lines (rules
and learned facts), scoped by model (`global` or a model id) and audience
(`all` | `parent` | `foreman` | `subagent`). Audience is matched as **membership
of a set**, not as a session kind: each session's set is fixed at process start
from the environment — either child marker (`PI_SUBAGENT=1` from the pi-subagent
wrapper, `PI_SUBAGENT_CHILD=1` from the pi-subagents async runner, §1) gives
`{subagent}`; otherwise `{parent}`, plus `{foreman}` when `PI_FOREMAN=1` (the
value the pi-foreman launcher exports for the session it execs), with `all`
matching every set. So a foreman session renders every `parent` entry **and**
every `foreman` entry, while a non-foreman session renders none of the `foreman`
ones. A subagent is reduced to `{subagent}` even though it inherits `PI_FOREMAN`
from its foreman parent — a foreman's worker is not a foreman. The set is read
once and never re-read, and the environment cannot change within a session: the
block sits in the system-prompt prefix, so a set that varied mid-session would
re-bill the tools array and the whole conversation. Injected at session start
through `before_agent_start` and guaranteed on every provider request by the
normalisation in `before_provider_request` (idempotent strip-then-append across
five payload shapes). The injected block is a **session-start snapshot**: the
system prompt is prompt-cache-frozen, so runtime edits never change a running
session's block; new sessions get the current list and running sessions learn of
changes through canon notices and `/canon-dump`. It replaced `APPEND_SYSTEM.md`
and `FLASH.md`. The prompt seam it composes the tail through
(`canonicalSystemPrompt`, `systemPromptSlot`) belongs to `@tinoy/pi-ext-lib`; the
section registry the foreman's section composes into (`setTailSection` /
`registeredSectionIds`) is canon's own.
*Spec:* tools `canon_add`, `canon_edit`, `canon_remove`, `canon_category`;
commands `/canon`, `/canon-dump`; hooks `before_agent_start`,
`before_provider_request`, `model_select`; store
`~/.pi/agent/canon/canon.json` as
`{entries: [{id, text, model, audience, reason?, category?}], categories: […]}`
with `audience` one of `all | parent | foreman | subagent`;
env `PI_CODING_AGENT_DIR`, `PI_MODEL`, `PI_SUBAGENT`, `PI_SUBAGENT_CHILD`,
`PI_FOREMAN`; peers notified over the pi-intercom bus on namespace `canon`; logs
`canon` lines to the shared hook log.
*Load scope:* the parent, plus worker children — `worker.subagentOnlyExtensions`
names the package's entry file, so in a worker child the factory runs and the
`{subagent}` block is injected exactly as the parent's block is. No other agent's
child loads it.
This is §2 and §7.
*Worker-child surface:* the whole surface registers there (tools, both commands,
hooks), while the worker's `tools` list in `settings.json` names none of the canon
tools — for a worker child the loaded store IS the block, not `canon_add`.

**`build.ts`** — bounded build/checker runner (canon R2 enforcement).
Runs a command through `bash -c` (with cwd, `timeoutMs` 5 s–900 s, default
300 s), sends full output to a log file so it never enters the conversation, and
returns exit code, duration, line count, error/warning lines (regex
`error|warning|fail|fatal|exception|✗|✖|cannot find|not found|E:`; first 30, else
last 15 raw lines) and the log path. Extra detail is retrieved from the log with
`read` offset/limit rather than by re-running the command.
*Spec:* logs to `/tmp/pi-build-logs/<ts>-<slug>.log`; strips `PI_SUBAGENT`,
`PI_SUBAGENTS`, `PI_SESSION` and `PI_INTERCOM` prefixed variables from the child
environment (`ENV_STRIP_PREFIXES`); imports `io-guard/identity.ts`,
`io-guard/claims.ts` and `lib/tool-header.ts`, so it pulls io-guard modules into
any session that loads it.

**`drift-anchor.ts`** — reasoning-register anchor: drift, cadence and hooks.
RULE A is that every reasoning block opens with the literal line
`Caveman mode.`; RULE B is that the user-facing reply stays clean explanatory
prose. RULE A decays in long autonomous sessions by self-reinforcement — every
call re-reads its own prior reasoning, so one verbose unmarked block inverts the
in-context prior — and the system prompt is prompt-cache-frozen, so the only
cache-safe lever is the `context` event, which fires before every model call and
accepts a message mutation. `message_end` detects drift read-only; `context`
re-anchors by appending a single line to the **tail** of the message array
(cache-safe: it sits in the uncached suffix) with a 3→6→12 backoff ladder under
persistent same-signal drift, plus a jittered periodic maintenance dose
(`PERIODIC_EVERY` 48 ± 12, i.e. a 36–60-turn window) deferred while drift
anchoring is active, and `[nudge]` lines for canon attention, tool churn, context
pressure and repeated blocked tools. Phrasing rotates so it never becomes
wallpaper. Hard rule: the model's own
drift verdict is never injected, because telling a model it was verbose triggers
the self-referential prose loop.
*Spec:* tool `set_anchor` (configures the session-specific phrase, which
must carry risk canon does not already state; a REPEAT call is accepted and
treats the anchor as a realignment — it replaces the phrase, replaces the hook
keys it passes while an unmentioned hook key keeps its configured value, and
restarts the line rotation and both jittered cadences from that call, while the
hook fire bookkeeping carries over so no capped hook gains a firing; nothing
gates a repeat — no counter, no turn threshold — and the tool description is the
discouragement); command `/anchor status|on|off`,
user-facing only, with stats never entering the model stream; hooks `context`,
`message_end`, `session_start`, `tool_execution_end`; injections
logged to the **shared hook log** under source `drift-anchor`, kinds
`anchor`/`nudge`/`set-anchor` — the only after-the-fact measure, since injected
lines live solely in the outgoing array, never in the session jsonl.
The periodic dose and canon cadence run in **every** session, with or without
`set_anchor`.
*Stale comment:* the header names `~/.local/share/pi-anchor/log.jsonl` as the
injection log. Nothing writes it any more — it is a 0-byte leftover; the live
route is the shared hook log.
*Hazard:* §7 — this is the file that produced the child-run provider 400s.

**`io-guard/index.ts`** — per-worker coordination for a crew sharing one tree.
Worker side is hooks only: it records what the worker read and guards what it
writes. A write is allowed only when the path is inside the worker's **current**
claim (read from the claim record, not the hire-time binding, which a resume
leaves stale), the claim has not been reclaimed underneath it (generation check),
a trusted version of the path was recorded and the file still hashes to it so the
worker is not overwriting changes it never saw, and the per-write lock is free. A
write refused because the lock is held is **parked**, not dropped: the proposal
and the version it was based on are stored and merged on the holder's release.
Every refusal fails closed — an unreadable claim, a missing version record or a
guard error all refuse rather than allow. The foreman side, in the same file,
provides inspection and the atomic reclaim of a claim — the guard's side of it
only: it moves the generation so a still-running worker's next write is refused,
and ownership comes off through `fleet` (`fleet/release.ts`), because the hire-time
overlap check reads the roster rather than this record.
*Spec:* tool `io_status`; entry `io-guard/index.ts` plus 7 modules (`claims`,
`identity`, `locks`, `pend`, `predicates`, `reap`, `versions`); reads
`PI_SUBAGENT_CHILD`, `PI_SUBAGENT_EXTENSION_BINDINGS`; logs `io-guard` and
`io-guard-lock` lines to the shared hook log.
*Detail:* `io-guard/AGENTS.md` is the long-form spec for this subsystem.

**`sudo-approve.ts`** — user-approved root command execution.
The agent passes one or more commands with per-command and/or collective
justifications. Primary path: `ags/promptd` shows one centred window with the
commands, justifications and a masked password field; the password is validated
**inside** promptd (`sudo -S -v`, the window stays open on wrong attempts with
red text, max 3), and on success promptd writes it to a 0600 temp file and
returns only that path; the commands then run via `sudo -A` with `SUDO_ASKPASS`
pointing at a cat-the-file script, and the temp file is deleted afterwards — the
password never enters pi. There is deliberately no timeout on the promptd
request, because a timeout firing while the window was legitimately up caused the
double-prompt. Fallback, on promptd **invocation errors only**, is the TUI
confirm dialog with the `yad` askpass bridge.
*Spec:* tool `sudo_approve`; audit `~/.local/share/sudo-approve/audit.log` as
JSONL per attempt (approve/deny/result); env `SUDO_APPROVE_INSTANCES`,
`SUDO_APPROVE_ROUTE`; commands run non-interactively, so anything normally
prompting must carry its own flags (`pacman --noconfirm`).

**`todo-parent.ts`** — crew todo proxy. Subagent sessions carry no local todo
tool (the agent allowlists exclude it, with `excludeTools` as belt and
suspenders), so this gives children a `todo_parent` tool whose mutations land in
the **parent** session's rpiv-todo list silently: the parent's model is never
woken, notified or asked to act. The child writes a request file into a
supervisor channel directory under the root the parent-side watcher polls (the
inherited `PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR` when a release still exports it,
otherwise a directory of its own under that root, which the parent's full-root
scan finds) and polls for the reply. The parent side, in the same file, polls the
pi-subagents supervisor-channels root for `todo.parent.*` requests and applies
them through rpiv-todo's pure reducer plus replay: authoritative state is
reconstructed from the session branch, the mutation applied, and a
replay-compatible `todo` toolResult appended to the branch so the change is both
durable and re-derivable.
*Spec:* tool `todo_parent`; reads `PI_SUBAGENTS_TEMP_ROOT`, `PI_SUBAGENT_CHILD`,
`PI_SUBAGENT_CHILD_AGENT`, `PI_SUBAGENT_CHILD_INDEX`,
`PI_SUBAGENT_ORCHESTRATOR_SESSION_ID`, `PI_SUBAGENT_PARENT_SESSION`,
`PI_SUBAGENT_RUN_ID`, `PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR`; imports
`lib/tool-header.ts`.
*Live-view gap:* the durable branch write is accompanied by an
`rpiv-todo:external-refresh` event, but nothing in the installed
`@juicesharp/rpiv-todo` subscribes to it. The package is patched on this machine
— `~/.pi/agent/patches/rpiv-todo/external-refresh.patch` installs an
external-refresh subscriber that replays branch truth into the view the foreman
and the user's overlay read. **If that patch is not applied, the write is durable
but the board does not move.**

---

## 5. Entries that are not extensions

**`lib/`** — five shared modules, none of them an extension:
`hook-log.ts` (the shared diagnostics envelope — `hookLog(source, kind, detail)`
appends `{ts, source, kind, detail}` to `~/.local/share/pi-hooks/log.jsonl`;
observability only, nothing reads it back to make a decision, and a logging
failure never breaks the emitting call; reads `PI_SESSION_ID`),
`focus-state.ts` (owns `$XDG_RUNTIME_DIR/pi-focus.json` and every ledger path
convention — `focusLedgerPathFor` names one session's own ledger,
`focusLedgerFiles` lists the ledgers in the runtime dir, `clearFocusLedgers` is
the all-at-once release clear, and `watchFocusState` is the coalescing state-file
watch; fail-open, so an unreadable file reads as `off`), `tariff.ts` (the house
price table, UNREAD now that its consumers are the `@tinoy/pi-tariff` dependency,
whose table lives at `~/.pi/agent/tariff.json` — see §6) and
`tool-header.ts` (the shared `renderCall` header builder — pi does not expose
`@earendil-works/pi-tui` to extensions, so a header must be a duck-typed
component with `render(width)` and `invalidate()`).
They are not discovered: discovery matches `*.ts` at the top level and
`*/index.ts` in a subdirectory, and `lib/` has neither. They load only as
imported dependencies of an extension that does load. `lib/hook-log.ts` and
`lib/tool-header.ts` run in children — the first through `command-guard`,
`focus-gate`, `orphan-repair`, `child-prompt-freeze` and others, the second
through `image-read`, `nf`, `build` and others. `lib/focus-state.ts` reaches
children too, through `focus-gate.ts` (on `defaultExtensions`), not through
`desktop-notify.ts` (parent-only). `lib/pause-state.ts` is reached by `pause.ts`.
The local copies of `hook-log.ts`, `focus-state.ts`, `tariff.ts` and
`pause-state.ts` are unreferenced now that their importers are packages; the one
local file still imported from here is `tool-header.ts`, by `sudo-approve.ts`.
`hook-log.ts` and `tool-header.ts` are published too in `@tinoy/pi-ext-lib`
(`src/hook-log.ts`, `src/tool-header.ts`), beside the system-prompt seam
(`src/system-prompt.ts`), which has no local counterpart: canon composes its tail
through it and `child-prompt-freeze.ts` imports it directly. The seam has one
implementation, and it is the package's.

**`subagent/config.json`** — pi-subagents' own extension config, not a local
extension. The package resolves it as
`path.join(getAgentDir(), "extensions", "subagent", "config.json")`
(`src/extension/config.ts`, `getConfigPath`), which is why it sits inside this
directory. Its single key is `defaultSubagentContext: "fresh"`, which is the
source-side kill for the implicit fork path in `no-subagent-fork.ts`. Pi does not
discover this directory as an extension because it has no `index.ts`.

**`node_modules`** — a symlink to `../npm/node_modules`, present so relative
imports from extension files resolve. It is not an extension entry.

**`AGENTS.md`** (this file), `fleet/AGENTS.md`, `io-guard/AGENTS.md`,
`fleet/config.json` — documentation and configuration, not load units.

---

## 6. Packages versus local files

The set this directory describes is consumed as published packages. Each
`@tinoy/pi-<name>` package declares its entry file in `package.json`
(`pi.extensions`), is installed under `~/.pi/agent/npm/node_modules/`, and is
named in settings `packages[]` for the parent. A child gets it only through an
explicit path in a child list (§1) — `--no-extensions` removes `packages[]` too.

Installed set (0.1.0 unless noted): `pi-build`, `pi-cache-prefix-log`,
`pi-canon` (0.2.0), `pi-child-prompt-freeze`, `pi-child-request-dump`,
`pi-cli-keys`, `pi-command-guard`, `pi-deepseek-cost`, `pi-desktop-notify`,
`pi-drift-anchor`, `pi-fleet` (also provides `io-guard/index.ts`),
`pi-focus-gate`, `pi-image-read`, `pi-intercom-broadcast`, `pi-nf`,
`pi-no-subagent-fork`, `pi-orphan-repair`, `pi-pause`, `pi-probe`,
`pi-read-staleness`, `pi-status-metrics`, `pi-todo-parent`. Library packages that
ship no extension entry — `pi-ext-lib`, `pi-focus-state`, `pi-tariff` — are
plain dependencies of those packages, installed beside them and never named in
settings.

**`@tinoy/pi-ext-lib` must be 0.2.0 or newer.** `pi-build`, `pi-fleet` and
`pi-todo-parent` import `optionalNeighbour` from it; ext-lib 0.1.0 lacks that
export, and the failure is quiet — `pi-todo-parent` logs a `register-failed` row
to the hook log and registers nothing, so its tool is simply absent.

Two data files are read from this machine's own tree, never from a package:
`tariff.json` (the price table — the packages resolve it at
`$PI_CODING_AGENT_DIR/tariff.json`, i.e. `~/.pi/agent/tariff.json`, or the path
`PI_TARIFF_CONFIG` names) and `fleet/config.json` (the crew's reuse window, read
from `~/.pi/agent/extensions/fleet/config.json`).

Two kinds of path appear in the settings extension lists, and they behave
differently:

- **Local files in this directory** — `/home/tinoy/.pi/agent/extensions/*.ts`
  and `/home/tinoy/.pi/agent/extensions/*/index.ts`. Loaded by the parent through
  ambient discovery, and by a child only when the path appears in a child list.
  One extension is still in this category: `sudo-approve.ts`, whose package is
  not published yet.
- **Package entries under `~/.pi/agent/npm/node_modules/`** — resolved from
  `settings.json`'s `packages[]` for the parent, and reachable by a child **only
  if the path is named in that agent's `subagentOnlyExtensions`**. Current
  examples: `pi-web-access/index.ts` (oracle, scout, researcher, delegate,
  worker), and `context-mode/build/adapters/pi/extension.js` (worker only).
- The **pi-subagents runtime extensions** are added to every child by the
  package itself, not from settings: the prompt bridge, the fan-out child
  extension when fan-out is authorised, and the permission-system extension when
  installed and not denied. They appear in no settings list.

A consequence worth stating: a name in a settings list is a **path**, not a
module name. Deleting or renaming a local file silently drops the extension for
every child that named it, with no error — the child simply comes up without it.

---

## 7. Hazards and non-obvious interactions

**7.1 The anchor nudge without the rule store — the worked example.** A child
loads `drift-anchor.ts` (worker children, through
`worker.subagentOnlyExtensions`) and, for every agent except `worker`, no
canon at all. That asymmetry is what made the failure below a child-side
failure: the worker child was told to open every reasoning block with `Caveman
mode.` while the canon entry stating that rule was out of its reach. The canon
package's entry file is on the worker list now, so a worker child does render the
store and its
`subagent`-audience entries; a child of any other agent still has no channel for a
standing rule, which is why those briefs must carry every rule verbatim. The
invariant that actually broke is the message-array one below, and it holds
whatever the rule store reaches.

The concrete cost, established by investigation and repaired on the night of
this writing: `drift-anchor.ts`'s `pushHookLine` injects action nudges
(`blocked`, `churn`, `pressure`) **second-to-last** in the outgoing message
array, which is correct only when the last message is the real user turn. In an
unattended child tool loop the last message is almost always a `toolResult`, so
the splice landed *inside* a tool run:

```
[user]
[assistant(tool_calls=[A,B])]
[tool(A)]
[user: "[nudge] …blocked…"]   <-- injected at messages.length - 1
[tool(B)]                      <-- now invalid
```

A provider rejects any `tool` message that is not part of the run answering the
nearest preceding assistant, so the run died on its next call — a `400 … role
'tool' must be a response to a preceding message with 'tool_calls'`. In the
recorded crash the injection is one millisecond before the fatal request; 12–13
of 15 firings ended in a dead child. Parents break through this mechanism far
more rarely, because a parent's nudge usually fires on a request that follows a
human turn, where the splice lands harmlessly before the real user message. The
live code now requires a user turn at the tail (`tailIsUser`) before taking the
second-to-last position and otherwise appends at the tail, and
`orphan-repair.ts` carries a run-adjacency predicate rather than the id-membership
check that missed this shape.

Read the two halves precisely. `drift-anchor.ts` was the author of the defect and
the fix is in that file; the missing rule store is why a child had no way to learn
the register rule, and why session kind — not the rule text — decided who died.
Any future change to the message array must respect the same invariant: **never
insert inside a run that still owes results.**

**7.2 `child-prompt-freeze.ts` takes the prompt seam from `@tinoy/pi-ext-lib`,
so a non-worker child evaluates a library without arming canon.**
`child-prompt-freeze.ts` does
`import { systemPromptSlot } from "@tinoy/pi-ext-lib"`. pi evaluates every
extension in its own jiti instance with `moduleCache: false`
(`dist/core/extensions/loader.js`), so that import resolves to the importing
extension's OWN copy of the seam: for a non-worker child that is the whole story
— the seam's module body is evaluated to supply `systemPromptSlot`, while nothing
of canon runs: no block, no
`canon_add`/`canon_edit`/`canon_remove`/`canon_category`, no `/canon`. A worker
child is the exception, because the canon package's entry file is on
`worker.subagentOnlyExtensions`: there canon's `export default function (pi)`
factory runs, the block is injected, and the module-instance split means only that
the injecting copy and the seam `child-prompt-freeze.ts` reads are separate
instances. So the precise statement is not "canon's code is absent from a child"
but "the extension entry point registers only where a child list names the file,
while the seam is imported as a library wherever `child-prompt-freeze.ts` loads".
Two consequences: the module-instance split means a value written through one
instance's registry is invisible to the other (the reason the foreman section
travels over the extension event bus instead of a direct call), and any future
refactor that moves state into the seam's module scope will behave differently in
a child than in the parent.

**7.3 Focus-gate enforcement hangs on one settings entry.** Children are gated
only because `focus-gate.ts` is in `subagents.defaultExtensions`. Any of the
following leaves that child ungated: an agent defined with its own `extensions`
field (which suppresses the default merge), a project `.pi/settings.json`
overriding `defaultExtensions`, `defaultExtensions: []`, or a launch under
`capabilityCeiling.denyExtensions`. The gate's own blocking is sound — a gated
child call is hard-blocked with a verbatim refusal and the attempt is logged —
but the coverage is not self-evident from the extension's code, only from
settings.

**7.4 `--no-extensions` also removes `packages[]`.** A child does not inherit
`settings.json`'s `packages` list. Each package-provided extension an agent needs
must be listed as an explicit path in that agent's `subagentOnlyExtensions`,
which is why `pi-web-access/index.ts` is repeated across four agent definitions.

**7.5 `build.ts` pulls io-guard modules, and `fleet/index.ts` pulls io-guard
claims.** Both import from `io-guard/`, so loading either evaluates io-guard's
`identity.ts` and `claims.ts` modules even in sessions where the io-guard
extension entry point would not otherwise register. In a worker child both
`build.ts` and `io-guard/index.ts` are on the list, so this is currently benign;
it stops being benign if `io-guard/index.ts` is ever removed from the worker's
list while `build.ts` stays.

**7.6 Handler order is the extension directory's order, and it is unspecified.**
Two extensions that normalise the same `before_provider_request` payload can
produce order-dependent bytes, and order-dependent bytes on the frozen prefix
means a silent cache miss on every request. This is why canon is the single owner
of the system-prompt tail and why `cache-prefix-log.ts` reads the payload one
macrotask late rather than inside its own handler.

**7.7 An edited extension does not reload in a running session.** New tools
appear at the next session start or on `/reload-runtime`, and a running session
keeps the module it loaded — a block message seen in-session may be the pre-edit
text.

---

## 8. Canon for children — what is live, and what is still open

The worker half of this question is settled: the canon package's entry file is on
`agentOverrides.worker.subagentOnlyExtensions` (§1), so a worker child loads the
store and renders the block its `{subagent}` audience set matches, exactly as
the parent renders its own (§4.3). No other agent's child loads canon.

**Still open: every other agent's children.** `oracle`, `scout`, `researcher`,
`reviewer` and `delegate` children run the ten defaults, so the standing rules
those roles need — the input-injection rule, one-writer-per-file,
`context: "fresh"`, spec-in-the-same-change — have to be restated verbatim in
each dispatch brief. `subagents.defaultExtensions` is the only list that reaches
them all.

**Sizes are not stated here.** The store is under a multi-pass migration: entries
are merged, moved and deleted between passes, so its size and the size of any
audience bucket move without any behaviour moving with them. When a figure
matters, measure the store — count the `~/.pi/agent/canon/canon.json` entries
whose `model` is `global` or the session's own model and whose `audience` is
`all` or is in that session's audience set.

**What a wider scope would cost.**
- **A real byte change on a cached path.** A child's system prompt would grow by
  the entries its audience set matches. Because the block is a session-start
  snapshot held byte-stable for the session's life, this is a one-time prefix
  change per *new* child, not a per-turn one — but it moves the prefix for every
  child launched afterwards. Children are the sessions the cache-prefix work was
  tuned around, and `child-prompt-freeze.ts` pins the child prompt precisely
  because a prefix that moves re-bills the tools array plus the whole
  conversation. Any measurement must be taken as a fresh baseline, not compared
  against existing `cache-prefix-log` rows.
- **Byte-stability must hold from the child's first request.** The entry set
  must not depend on anything that varies per run (the clock, the parent's
  model, the brief), or the prefix moves between children for no reason.
- **Scope discipline.** Only entries whose scope matches are rendered: `parent`
  and `foreman` entries stay out of a child, so the growth is the `subagent` plus
  `all` subset rather than the whole store.
- **Review obligation.** The remaining hazard is not size but relevance: a rule
  written for the parent may be false or noisy in a child, and canon's own tool
  descriptions already warn that an over-broad scope pushes a rule into sessions
  where it does not apply.

**The options are:** add the canon package to `subagents.defaultExtensions` (every
agent's children); keep it on the worker list (worker children only — the live
state); or leave the store to adults and keep every rule in briefs.

---

## 9. Conventions

- Extensions are TypeScript with `export default function (pi: ExtensionAPI)`,
  using typebox `Type` schemas.
- Verify edits with `node --experimental-strip-types --check <file>` — not
  `node --check`. An extension that value-imports
  `@earendil-works/pi-coding-agent` cannot be import-tested standalone; strip
  that import line into a `/tmp` copy to exercise its exported helpers.
- Shared code lives in `lib/`; it is imported, never registered, and never
  discovered.
- A new extension that children must have needs an explicit entry in a child
  list — `subagents.defaultExtensions` for every child, or the agent's
  `subagentOnlyExtensions` for one agent. Dropping a file into this directory
  reaches the parent only.
- A new extension is written in the `pi-extensions` repository and installed as
  a package (`pi install npm:@tinoy/pi-<name>`), not left as a file here. The
  entry and the removal of the local file are ONE step: a package entry and a
  local file providing the same extension both load, and the symptom is a tool
  registered twice — duplicated behaviour in a new session, never an error.
  Publish `pi-ext-lib` before the packages that import it; a consumer tree pins
  the range in its own `package.json`, so ext-lib 0.1.0 stays installed under a
  `*` requirement until that range is raised.
- Keep the inventory table in §3 in step with the directory. A file with no row
  is a file whose load scope nobody has stated.
