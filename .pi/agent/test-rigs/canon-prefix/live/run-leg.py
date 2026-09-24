#!/usr/bin/env python3
"""Live leg driver (NOT shipped): runs one leg in RPC mode.

*** COST-BEARING — OPT-IN ONLY. *** Every run starts a real pi process that
makes real provider requests against the user's account. Do not run it as part
of the offline suite; run it only when the LIVE path itself needs re-proving
(the offline harnesses are the fast regression net).

Sends one typed prompt, lets the wake-probe extension inject one
{triggerTurn:true} message on settle (the intercom/completion wake path), waits
for two provider requests, then closes stdin and reports the artifacts.

Usage: run-leg.py <leg-name> <expect-requests> <ext...>
   env: LEG_CHILD=1              run child-shaped (the pi-subagents async-runner
                                 marker; a crew worker's launch shape).
        LEG_CWD=<dir>            working dir for pi (default the ags repo).
Artifacts land in ./evidence/live-<leg>/ next to this script.
"""
import json, os, subprocess, sys, time, pathlib

HERE = pathlib.Path(__file__).resolve().parent
leg = sys.argv[1]
expect = int(sys.argv[2])
exts = sys.argv[3:]
d = HERE / "evidence" / f"live-{leg}"
d.mkdir(exist_ok=True)
for f in ("probe.log", "prefix.jsonl", "rpc.out", "rpc.err"):
    (d / f).unlink(missing_ok=True)

env = dict(os.environ)
env.update({
    "PI_OFFLINE": "1", "PI_SKIP_VERSION_CHECK": "1",
    "PI_CACHE_PREFIX_LOG": str(d / "prefix.jsonl"),
    "WAKE_PROBE_LOG": str(d / "probe.log"),
})
# The leg declares its own session shape: every marker the extensions under test
# read is cleared first, so a leg launched from a crew worker shell — which
# exports PI_SUBAGENT_CHILD=1 — is not read as a child by accident, and a leg
# launched from a foreman session does not inherit PI_FOREMAN.
for marker in ("PI_SUBAGENT", "PI_SUBAGENT_CHILD", "PI_FOREMAN"):
    env.pop(marker, None)
if os.environ.get("LEG_CHILD") == "1":
    # The shape the pi-subagents async runner produces, marker and all: it sets
    # PI_SUBAGENT_CHILD and never PI_SUBAGENT.
    env["PI_SUBAGENT_CHILD"] = "1"

argv = ["/usr/lib/pi-coding-agent/pi", "--mode", "rpc", "--no-session"]
for e in exts:
    argv += ["--no-extensions" if e == exts[0] else "-e", e] if False else (["-e", e] if e != exts[0] else ["--no-extensions", "-e", e])
p = subprocess.Popen(argv, cwd=os.environ.get("LEG_CWD", "/home/tinoy/.config/ags"), env=env,
                     stdin=subprocess.PIPE, stdout=open(d / "rpc.out", "w"),
                     stderr=open(d / "rpc.err", "w"), text=True)
print("started pid", p.pid, "argv", " ".join(argv))
p.stdin.write(json.dumps({"id": "p1", "type": "prompt", "message": "Reply with exactly: PONG"}) + "\n")
p.stdin.flush()
deadline = time.time() + 200
reqs = 0
while time.time() < deadline:
    time.sleep(2)
    if (d / "probe.log").exists():
        reqs = len([l for l in (d / "probe.log").read_text().splitlines() if '"req"' in l])
        if reqs >= expect:
            break
print("requests observed:", reqs, "(expected", expect, ")")
time.sleep(1)
try:
    p.stdin.close()
except Exception:
    pass
try:
    p.wait(timeout=20)
except subprocess.TimeoutExpired:
    p.kill()
print("exit:", p.returncode)
print("---- probe.log")
print((d / "probe.log").read_text() if (d / "probe.log").exists() else "(none)")
print("---- prefix rows")
print((d / "prefix.jsonl").read_text() if (d / "prefix.jsonl").exists() else "(none)")
err = (d / "rpc.err").read_text()
print("---- stderr (400)", err[:400])
