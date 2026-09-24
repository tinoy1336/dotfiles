---
name: handoff
description: Write a pickup handoff markdown so a fresh session can continue efficiently (state, what shipped/changed, open threads, the next actionable step, capability + machine notes). Use when the user asks to write/hand off, an end-of-session summary, a "pick up next session" doc, or when the session cannot finish and should delegate continuity to a new one. In the same flow the skill opens the rendered HTML preview AND spawns a fresh pi TUI session with the requested model pointed at the handoff — only when the user asks — and then the CURRENT session clocks out (kills its own window). A foreman session ALSO publishes its crew first (crew-preserving handoff), so the successor can adopt the workers instead of rebuilding them.
---

# Handoff

A handoff is a **cold-start-complete** markdown doc: a fresh session reads it and
resumes without re-discovering context or re-deriving conventions. It exists for
cost/efficiency — skip re-reading everything by capturing the essential state.

## Where it goes — ALWAYS

`~/handoffs/<YYYY-MM-DD>-<topic>.md` (e.g. `~/handoffs/2026-09-02-capabilities-and-opendesign-handoff.md`).
Never anywhere else. Same dir every time.

## Workflow

1. **Write** the handoff md to the location above (template below).
2. **Open HTML preview** — render it with `preview_export` (source: file, format: html, open: true) so the user reviews the rendered doc, not raw markdown. Always, no exceptions. The tool is not part of pi itself: it ships in the `pi-markdown-preview` extension (`npm:pi-markdown-preview`, installed at 0.16.0).
3. **Publish the crew** (foreman sessions that hold one) — see "Handing off a crew" below. Do this BEFORE spawning the successor, so the successor's very first `fleet adopt` has a sheet to read.
4. **Spawn a fresh pi TUI session** (ONLY when the user explicitly asks) pointed at the handoff with the requested model, to save the user opening it manually:
   ```
   setsid --fork nohup kitty --class handoff -e "$HOME/.pi/agent/skills/handoff/launch-successor.sh" \
     "$MODEL" "$HANDOFF" "$CWD" >>"${TMPDIR:-/tmp}/handoff-spawn.log" 2>&1 </dev/null
   ```
   - **Never put `timeout` in front of it, and never run it under a foreground waiter.**
     `timeout` runs its child in its own process group and signals that group, so a
     `timeout N` that fires kills the window's process, the pty and pi with it. The
     signature is a successor that dies exactly N seconds in with its session file frozen
     at the ceiling — which reads like a successor bug, not like a spawn that was capped.
   - **The command must detach AND return.** `setsid` without `--fork` execs its program
     in place whenever `setsid(2)` succeeds, so the invoking shell waits for the
     successor's whole life and the call that ran it hangs until a guard kills it;
     `--fork` always starts a new process and returns at once. A trailing `&` on the same
     line does the same job; `--fork` is the deterministic one.
   - `setsid` is the part that survives a process-group kill — `nohup` alone does not.
     The redirect keeps the caller's stdout/stderr pipe out of the successor's stdio, so
     a call that spawned it is not held open by the successor's lifetime. kitty's own
     `--detach` (with `--detached-log`, or its log is lost) is the alternative that removes
     the foreground parent at the source; it is untested here.
   - `launch-successor.sh` does NOT detach itself and must not: it strips the five
     identity names and `exec`s pi. A detach inside it cannot save a successor whose
     window's pty died, and `setsid` on the pi invocation would additionally take pi out
     of the pty's session (no terminal Ctrl-C, no kernel SIGWINCH on a resize). The spawn
     form is the fix; a launcher-side detach is belt-and-braces at most.
   - `PI_FOREMAN` is unset by this launcher: a successor launched from a worker's shell
     inherits `PI_FOREMAN=1` from the session above it, and the fleet arms foreman mode
     from that variable, so the successor would come up armed for the wrong role —
     `PI_SUBAGENT_CHILD` is stripped and does not cover it. A crew handoff launches through
     `~/.local/bin/pi-foreman`, which arms foreman mode explicitly (it exports
     `PI_FOREMAN=1` after its own strip), so the inherited value must never decide it.
     The five identity names are one list shared with `pi-foreman`; `PI_FOREMAN` is unset
     by this launcher only.
   - A spawn that did die young is re-issued in this same detached form, with the log
     file read first — the successor's frozen session file is the tell.
   - `$CWD` = the project dir the handoff is about (e.g. `~/.config/ags`).
   - `$MODEL` = the requested model as `provider/id` (e.g. `deepseek/deepseek-flash`; take it from `pi --list-models` if unsure).
   - `$HANDOFF` = the absolute path to the handoff file (the `@file` makes it the new session's initial message).
   - The launch goes through `launch-successor.sh`, NEVER a bare `bash -lc 'pi …'`: the script strips the crew identity from the environment (`PI_SUBAGENT`, `PI_SUBAGENT_CHILD`, `PI_SUBAGENT_PARENT_SESSION`, `PI_SUBAGENT_EXTENSION_BINDINGS`, `PI_INTERCOM_SESSION_ID`) plus `PI_FOREMAN`, and leaves `PI_SUBAGENT_PI_BINARY` and `PI_SUBAGENT_CACHE_RETENTION` alone. A successor that inherits a live worker's binding is refused every write for its whole life — and a worker-launched successor loses the subagents package entirely (`PI_SUBAGENT_CHILD=1` makes pi-subagents decline to register), so no crew verb works in it. If the successor must be a FOREMAN (a crew handoff), launch through `~/.local/bin/pi-foreman` instead once it is in place: it performs the same enumerated strip of the five identity names and then arms foreman mode itself. Those five names are one list in both — change both together.
   - Before spawning the window, send a `desktop_notify` heads-up (it opens a window / takes focus — intrusive action). Adapt the spawn for a different terminal/tmux if the user isn't on kitty.
5. **Clock out — close your own kitty window.** A handoff is end-of-shift: you
wrote the doc, opened the preview, spawned the successor, delivered your final
summary — then you STOP. The current session does not stay open beside the new
one. Closing the WINDOW (not just the pi process) is mandatory: a bare
`kill -TERM` on the pi PID leaves an empty kitty window stranded on the desktop.
Schedule a delayed self-close so the final response flushes first (never a
blocking kill mid-turn):
   ```
   setsid nohup "$HOME/.pi/agent/skills/handoff/close-self.sh" \
     >>"${TMPDIR:-/tmp}/handoff-close.log" 2>&1 </dev/null &
   ```
   - `close-self.sh` resolves the session it is closing FROM ITS OWN PARENT CHAIN (the
     nearest `pi` ancestor — the session that hired whoever runs this), takes that
     process's pty out of `/proc/<pid>/fd`, waits out a flush delay (default 2 s), writes
     the close frame there, and confirms the pid is gone before exiting 0. `--pid` and
     `--pty` override the resolution, `--window N` selects by id instead of `self`, and
     `--dry-run` prints the resolved target and the frame and writes nothing. **Use
     `setsid` WITHOUT `--fork` here**: the helper walks its own ancestry, and `--fork`
     would reparent it to init first.
   - **Primary path — the remote-control escape frame on the window's own pty.**
     kitty parses `ESC P @kitty-cmd <json> ESC \` out of the bytes a program writes to
     its terminal, and a write to the window's pty device reaches that parser the same
     way a program's own output does:
     `{"cmd":"close-window","version":[<major>,<minor>,<patch>],"no_response":true,"payload":{"self":true}}`.
     - `self:true` selects the window the frame came from — on this route that IS the
       target — so no window id has to be right and nothing depends on
       `$KITTY_WINDOW_ID` being in the environment (`--window N` switches the payload to
       `{"match":"id:N"}`).
     - `no_response:true` matters: the protocol's normal reply is written back to the
       tty, i.e. into the closing session's INPUT stream. Nothing is read from that pty —
       its read side belongs to the session being closed.
     - `version` is the protocol version read off the running instance (`kitty
       --version`). A version GREATER than the instance's makes kitty refuse the whole
       command and the window stays, so it is never copied from a doc; the script refuses
       to write a frame it cannot version (`--protocol-version` states one explicitly).
   - **`kitty @` does not work here, and its TTY route cannot be reached.**
     `allow_remote_control yes` is set in `~/.config/kitty/kitty.conf` but there is no
     `listen_on`, so no kitty RC socket exists; the remaining route — `kitty @` over the
     calling process's controlling tty — needs a controlling terminal, which a tool
     shell does not have (`open /dev/tty` fails with ENXIO) and which `setsid` would
     remove even if it did. `listen_on` is what would make `kitty @` valid; it is NOT set
     today, and setting it exposes a local kitty API surface (send text to windows, open
     and close windows, read window contents), so this skill documents the frame route
     as the working path.
   - **Never use `hyprctl dispatch closewindow`**: on Hyprland 0.56 an
     unresolvable address closes the FOCUSED window instead — machine canon.
     `self:true` is always resolvable (the frame is written to the target's own pty), and
     a frame written to a pty that is NOT a kitty window's (another terminal, a plain ssh
     pty) reaches no window at all — which is what the fallback below is for.
   - **Fallback**: when the frame has not ended pi inside the script's confirm window,
     `close-self.sh` arms `kill -TERM <pid>`. That ends the session but leaves an EMPTY
     kitty window on the desktop, so note it in the final response and let the user close
     it (`--no-kill-fallback` disables the arm entirely).
   - The target pid is the session's own pi process — never a pattern match and never the
     successor's PID. A worker running the close does not need to be told it: the helper
     resolves the nearest `pi` ancestor of its own process (not `$PPID`, which is the
     pi-subagents runner). That walk targets the session the worker was HIRED by, so a
     close delegated for a different session lands on the hiring session's window unless
     `--pid` names the other one — and `--pid` trusts any `pi` process that has a pty.
   - The self-close is the LAST tool action of the turn, composed together with
     the final response (reply text flushes at turn end, then the timer fires).
   - A pending close is CANCELLED EXPLICITLY, by killing the helper process: continuing to
     work does not stop a detached timer, so a close that was armed for the end of the
     shift fires mid-turn and takes the session with it. `close-self.sh` prints its own pid
     as `close-self: helper pid <pid>` to stdout and as the same `<pid>` in its log's
     `helper pid <pid>: target pid …` line, written before its delay — that pid is the
     process to kill.

## The spawn and the close are handed to a worker

A session that hands off a crew has no shell of its own — no `bash` in its tool set — so
steps 4 and 5 are not run from inside it. A session that DOES have a shell runs the two
command strings itself; the hire is for a session that has no shell. The session composes
ONE exact command string per step, hires a worker to run it verbatim, and then reads the
EFFECT back; the hire is not the work:

- **spawn — prove the successor exists**: the worker's log line plus a window process
  (`pgrep -f "kitty --class handoff"`) plus a session file under
  `~/.pi/agent/sessions/<cwd-slug>/` created after the spawn
  (`ls -t ~/.pi/agent/sessions/*/*.jsonl | head -3`).
- **close — prove the session is gone**: `/proc/<own-pi-pid>` is absent and the window is
  closed. A `kill -TERM` fallback that fired means the window is still there — say so.
- **A step whose effect did not appear is re-issued, not assumed.** A successor that died
  young is re-spawned detached; the predecessor's own window is closed by re-running
  `close-self.sh` (it re-resolves the target on every run) and reading its log.
- The intrusive-action heads-up for the new window (`desktop_notify`, step 4) goes out
  BEFORE the hire, so the notification always precedes the window it announces.
- Both log paths — `${TMPDIR:-/tmp}/handoff-spawn.log` and `${TMPDIR:-/tmp}/handoff-close.log`
  — are SHARED by every handoff on the machine and APPENDED to, never truncated: read the
  last entry that belongs to this handoff (the helper's own pid line names it) rather than
  assuming the file is this run's.

## Handing off a crew (foreman sessions)

A handoff normally lets the CREW die with the session: the workers keep running in
their own detached processes, but no new session can name them, because the name
registry is per-session by design. Publishing a crew closes that gap.

**Outgoing foreman** — if `fleet` action `roster` shows a crew, publish it as the
last fleet action before the spawn and before clocking out:

```
fleet({action: "handoff"})
```

- Writes `~/.local/pi/foreman/adopt/<iso>-<sessionId>.json` plus a `current.json`
  pointer, and marks every worker `handed-off` in THIS session's roster, so this
  session can no longer steer, assign or retire a crew it has given away.
- Signals NOTHING: no worker is restarted, resumed or interrupted, and every one of
  them keeps its own frozen prefix. A live worker is handed over as a pointer.
- Record it in the handoff md ("the crew is published; the successor adopts it") and
  name the workers and their states, so the successor knows what it is inheriting.

**Incoming successor** — a session that opened onto such a handoff takes the crew
over explicitly; it is never implicit:

```
fleet({action: "adopt", from: "current"})
```

- REFUSES while the predecessor session is still alive (or cannot be proved gone),
  so the outgoing session must have exited first — publish, spawn, then clock out.
- Adopts a live worker by pointer (steered, never resumed) and a settled one with
  its reuse verdict stated; it resumes nothing itself. Use `assign` for an idle
  worker inside the reuse window, and read its report file when the reuse verdict
  comes back cold.
- A worker whose run record is gone is refused by name, and the rest are still
  adopted.

Two things a successor must know: the extension is loaded per process, so this verb
exists only in a process started after it shipped (a running session never gains it),
and a worker adopted from a handoff carries the PREVIOUS session's intercom target —
the crew's channel to a foreman is its run output, not intercom.

## Template (framework, not a rigid form)

```markdown
# Handoff — <topic> (<date>)

Next session: read this first. One line: what this session was / is picking up.

## 1. Status
- What's DONE (and verified). Be concrete — names, paths, values. A fresh session
  should not re-do work that's complete.
- What's NOT done / in-flight, with the exact blocker (e.g. "waiting on user to
  review variants in the web UI").

## 2. Shipped / changed this session
- Files changed (paths) + the change. Any correction to a prior plan/assumption
  (e.g. "handoff said delete common/glyph/, but 3 helper files live there and are
  used — only nf.json + nf.ts were removed").
- Backups taken (paths).

## 3. Open thread — the next actionable step
- The single most important thing the next session should do, stated as a command
  ("port the winner into apps/files/config.* + tsx").
- What's needed to do it (user decision, a tool, an approval, an API call).
- Any API/spec cheatsheet the next session will need (endpoints, field names,
  token shapes) — inline, small.

## 4. Capability + machine notes
- Capabilities now in place (what changed that the next session should know:
  new tools, settings, canon rules).
- Machine state (production vs dev shell, running daemons, bus names, units).
- Gotchas / constraints that will bite if missed.

## 5. Escalation / stop rules
- When to ask the user vs. proceed. Anything gated on a human decision.
```

## Doc order — status sections last

The status sections (§1) and the shipped/changed list say what is DONE, what is in flight
and what is unproven. They are written when the CREW IS QUIET: no worker running, no build
in progress, nothing pending. A DONE entry is a promise that the successor will not re-do
that work, so the DONE list is the LAST thing written, never the first — a status written
while work continues describes a state that has already moved on.

- A doc that has to go out with work still in flight carries an explicit revision line
  under the title — `Revised N — <what changed since the first write>`, one line per
  revision, kept in place. Without that line the doc claims to describe a settled state.
- A correction AFTER the spawn does not reach the successor by itself: the successor read
  the file at its first turn, so the session that corrects it says so on the existing
  channel ("the corrected handoff doc has landed — re-read it") in addition to the
  re-render.
- Re-read the status sections against the live crew state once more immediately before the
  spawn, and revise or fix — that pass is what keeps the doc and the session from
  contradicting each other.

## Conventions

- **Write the file, give the path** — never paste the whole handoff inline in chat
  (canon: long docs → file + path + 2-3 key beats inline).
- **Cold-start complete**: the doc must state goal, target/cwd/ref, what's done vs
  not, the next step, and stop rules. Do not rely on the previous session's history.
- **Corrections matter**: if the prior handoff/plan was wrong, state the correction
  explicitly — a fresh session can't see the conversation.
- **Be terse but complete** — facts, not prose. Machine-level facts go in canon;
  project detail goes here.
- **Always** render the HTML preview (workflow step 2). Spawn the fresh TUI session (workflow step 4, detached form) **only when the user explicitly asks** — never by default — and then clock out (workflow step 5): the handing-off session exits, it does not linger. The status sections follow "Doc order" above — written when the crew is quiet, or carrying a revision line.
- **A crew is published, never re-homed by hand.** A foreman with workers calls
  `fleet handoff`; a successor calls `fleet adopt`. Never write an adoption sheet or
  a roster file by hand, and never point a successor at the predecessor's roster
  file — it is invisible to reads by design.

## Complements canon, does not replace it

Behavior rules stay in canon (e.g. write a handoff instead of blocking forever on
an unattainable approval; long docs → file + path). This skill is the *format* +
the *launch* — the structure, the cold-start-complete contract, the preview, and
the new-session spawn. Keep the two separate: canon for when/why, this skill for
how.
