---
name: night-end
description: Use when the user asks to shut down, suspend, or end a night/late session (including when the user says they are going to sleep and the machine must be put away). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Night end

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Shutdown preferred, suspend = fallback

**END-OF-NIGHT SESSION: SHUTDOWN PREFERRED, SUSPEND = FALLBACK:** when the user asks to "shut the machine down" at session end, they mean a real poweroff — ask via `sudo_approve` (`shutdown`) even if it shows an approval window; if the approval doesn't happen / is denied, fall back to `systemctl suspend` (user-approved alternative, no root needed). Either way schedule DELAYED (`shutdown +3` / `setsid sh -c 'sleep N; systemctl suspend'`) after composing the final response; never block before the reply flushes.

## Elevated-perms wall → report inline, never a file

**END-OF-NIGHT ELEVATED-PERMS WALL → SAY IT IN THE REPLY:** when work cannot proceed past a point without elevated perms and no approval can be granted (user asleep), stop that thread and put it in the final reply — the blocker, what was attempted, the exact command that clears it, and the state of the evidence. Do NOT write a handoff/report markdown file for it: the user never asked for one (canon `15mwmo`), and an unrequested file is something they then have to police. Never block indefinitely on an approval nobody can grant, and never open an approval window overnight (see below).

## No notification noise overnight

CRITICAL NOTIFS DO NOT WAKE THE USER OVERNIGHT — during night sessions never attempt shutdown approval expecting a response; go straight to the approved delayed `systemctl suspend` fallback when work ends.

## Terminal actions after the final response

**TERMINAL ACTIONS AFTER THE FINAL RESPONSE:** never run a blocking suspend/poweroff then write the final response — the reply flushes at turn end, so it lands in the void. Compose everything first, then schedule DELAYED (`setsid sh -c 'sleep N; systemctl suspend'`). Nothing follows a blocking terminal action.
