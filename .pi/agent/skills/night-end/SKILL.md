---
name: night-end
description: Use when the user asks to shut down, suspend, or end a night/late session (including when the user says they are going to sleep and the machine must be put away). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Night end

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Shutdown preferred, suspend = fallback

**END-OF-NIGHT SESSION: SHUTDOWN PREFERRED, SUSPEND = FALLBACK:** when the user asks to "shut the machine down" at session end, they mean a real poweroff — ask via `sudo_approve` (`shutdown`) even if it shows an approval window; if the approval doesn't happen / is denied, fall back to `systemctl suspend` (user-approved alternative, no root needed). Either way schedule DELAYED (`shutdown +3` / `setsid sh -c 'sleep N; systemctl suspend'`) after composing the final response; never block before the reply flushes.

## Elevated-perms wall → handoff file

**END-OF-NIGHT ELEVATED-PERMS WALL → HANDOFF .MD:** when an agent cannot proceed past a point without elevated perms (sudo_approve approval impossible — user asleep), it writes the situation to a markdown file (what was attempted, exact blocker, state of evidence, next steps) so a fresh session can efficiently pick up in the morning; peer sessions get an intercom pointer to the file. Never block indefinitely on approval nobody can grant.

## No notification noise overnight

CRITICAL NOTIFS DO NOT WAKE THE USER OVERNIGHT — during night sessions never attempt shutdown approval expecting a response; go straight to the approved delayed `systemctl suspend` fallback when work ends.

## Terminal actions after the final response

**TERMINAL ACTIONS AFTER THE FINAL RESPONSE:** never run a blocking suspend/poweroff then write the final response — the reply flushes at turn end, so it lands in the void. Compose everything first, then schedule DELAYED (`setsid sh -c 'sleep N; systemctl suspend'`). Nothing follows a blocking terminal action.
