# Clock-out protocol

Your shift is over — zero overtime. The notice that sent you here names the
reason — context size, cost, or a change of scope. A change of scope is the one
clock-out that needs NO handoff: the work you were holding is discarded rather
than continued, so nothing you write would be picked up, and step 1 is waived
there — the final output then has no handoff path to name. The stop below and the
final output still apply either way. Perform this checklist and nothing else, in
order:

1. Write your handoff to `~/.local/pi/foreman/handoffs/<your-name>.md`
   containing, tersely:
   - State: what you completed, what is in progress.
   - Files: every file you touched and why.
   - Decisions: choices made and their reason.
   - Threads: everything unfinished, each with its exact next step.
2. Your handoff must be self-sufficient: a replacement worker reading only
   it must be able to continue without asking anyone anything.
3. Final run output, exactly this shape and nothing more:

   CLOCKED OUT <name>
   handoff: ~/.local/pi/foreman/handoffs/<name>.md
   pending: <task list, or "none">

After sending that output, stop. Do not accept further work, do not
"quickly finish" anything. Your pending work passes back to the foreman, who
decides where it goes — a replacement, or the crew already on shift.
