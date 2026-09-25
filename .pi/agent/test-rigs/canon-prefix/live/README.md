# live/ — OPT-IN and COST-BEARING

Everything in this directory drives a **real pi process and real provider
requests**. It is NOT part of the offline suite and must not be run routinely.

Run only when the live process path itself needs re-proving. Artifacts land in
`evidence/live-<leg>/` so a re-proof starts from a baseline. See the parent
`README.md` for the command and the residual limits (the offline harnesses are
the fast regression net; the live legs are the authority).

## Re-proving the loader-bullet prefix move (2026-09-24)

What it establishes: fleet's drift sweep used to remove a loader tool that the typed
path re-adds (pi-subagents' `subagents_enable`, pi-web-access' `web_enable`), so a wake
rendered one `- <tool>: <snippet>` bullet fewer and moved the head of the system prompt.
`test-rigs/canon-prefix/harness-fleet.ts` in the checkout is the regression net; this is
the authority, because it reads the bytes the provider was actually sent.

Two probes are used together:

- `probe-request-bodies.ts` — writes every outgoing request body to its own file
  (`BODY_PROBE_DIR`, default `./body-probe/`). **Bodies are session data**: they contain
  the whole system prompt, so keep them here and record only lengths and hashes under
  `evidence/`.
- `wake-probe.ts` — records one line per request and, once, fires an injected wake.

Recipe (all of it on a scratch copy/dir; nothing here writes the checkout):

```sh
# 1. a FIFO keeps an RPC session alive while idle, so a wake can land after the run
mkfifo /tmp/pi-rpc-fifo
BODY_PROBE_DIR=/tmp/bodies-pre \
  PI_FOREMAN=1 setsid timeout 120 pi --mode rpc --model <model> --thinking off \
    -e ./probe-request-bodies.ts < /tmp/pi-rpc-fifo > /tmp/pi-rpc-out.txt 2>&1 &
exec 3>/tmp/pi-rpc-fifo                      # hold the write end open
printf '%s\n' '{"id":"r1","type":"prompt","message":"Use the read tool on <any file>, then reply with one word."}' >&3
# 2. wait for the run to settle, then inject a wake (or let wake-probe do it)
printf '%s\n' '{"id":"r2","type":"prompt","message":"Use image_read on <png>, then reply with one word."}' >&3
```

Expected result, comparing the system-prompt length of the typed request against the
request that follows the loader's arrival or removal:

- **with the sweep (pre-fix)** — e.g. `ae18529^` of `packages/fleet`: typed 170,860
  characters, the idle-wake request 170,594, and the only byte difference is the
  `- subagents_enable: …` line at offset 1022 (its length including the newline is 266;
  the `web_enable` bullet is 195 in that configuration).
- **with the fix** — every request byte-identical at 170,860.

Rebuild the pre-fix package without touching the checkout:

```sh
git -C <pi-extensions-checkout> show ae18529^:packages/fleet/index.ts > /tmp/fleet-prefix.ts
# point a scratch copy of the installed package at that file, or run the checkout's rig
# arm with the file restored in a /tmp copy (never in place).
```

Record in `evidence/` the `index.txt` lines plus `sha1sum` of each body — not the bodies.
