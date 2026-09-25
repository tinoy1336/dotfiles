# Local patch: `pi-deepseek-cost` two-unit countdown

**One file, one hunk.** `two-unit-countdown.patch` patches
`@tinoy/pi-deepseek-cost/index.ts` only.

## What it carries

The published 0.2.0 release renders the time left in the tariff window as a single
unit (`2d`, `11h`, `53m`, `38s`), so an interval with hours still to run drops its
minutes entirely. The patch carries the change published after it: the remainder is
rendered as the **two largest non-zero units** — `1d 3h`, `11h 5m`, `53m 4s`, `38s` —
with the second unit dropped when it is zero (`2d`, `5h`, `1m`) and seconds alone
under a minute. Every magnitude stays floored, so a remainder never overstates.

`windowLabel()` is untouched: the glyph, one space, then the label. The label grows
from at most 3 characters to at most 7 (`59m 59s`), so the field beside the glyph
goes from exactly 5 cells to at most 9. The footer joins every extension status into
one line sorted by key and truncates that line from the right; the cost segment sorts
first, so the added width can push a later segment off the row but cannot cut the
countdown.

## Applied automatically

`apply-patches.sh` in the directory above keeps this patch applied, from the entry
`deepseek-cost-two-unit-countdown` in `../managed-patches.conf`. The dry run uses
`--fuzz=0`, so a target whose surrounding code moved fails loudly instead of being
fuzz-applied, and the package is left byte-identical: the patch is applied to copies
in a staging directory and each patched copy is renamed over its original.
`pre-patch/index.ts.<version>` keeps the bytes as packaged.

## Is it applied?

```
grep -c 'TWO LARGEST NON-ZERO units' /home/tinoy/.pi/agent/npm/node_modules/@tinoy/pi-deepseek-cost/index.ts
```

`1` = applied · `0` = not applied, or an update replaced the file. A dry run confirms
it, and the two directions read differently:

```
patch -p1 --dry-run    -d <pkg> < <patch>   # "Reversed (or previously applied) patch detected!" = applied
patch -p1 --dry-run -R -d <pkg> < <patch>   # "Unreversed patch detected!" = not applied
```

## When it takes effect

At the **next pi session start**: a running session keeps the module it loaded.
`apply-patches.sh` writes the installed file, so a session started after that run
renders the two-unit countdown; the session that was open while it ran keeps the
one-unit form until it ends.

The trigger that re-applies this patch after an npm rewrite is the systemd path unit,
and its `PathModified=` list names one watched directory per patched package. This
package is not on that list yet, so a rewrite of it lands unpatched until the list
gains the package directory and the unit is reloaded — the run above is the manual
apply until then.

## Apply by hand

```
patch -p1 -d /home/tinoy/.pi/agent/npm/node_modules/@tinoy/pi-deepseek-cost \
  < /home/tinoy/.pi/agent/patches/deepseek-cost/two-unit-countdown.patch
```

Prefer `apply-patches.sh`: it reads the applied state from the installed file, requires
a clean dry run before writing, keeps the per-version rollback copy and records what it
did.

## Checking the installed bytes

`node --experimental-strip-types` refuses a file whose real path is under
`node_modules`, and this package is a real npm copy rather than a link, so the installed
file cannot be imported by path. `verify-installed.mjs` loads it in place through jiti —
the loader pi itself uses — and asserts the four shapes, the dropped-zero boundary and the
one-hour-zero-minutes case:

```
timeout 120 node /home/tinoy/.pi/agent/patches/deepseek-cost/verify-installed.mjs
```

For the wider sweep (the 4-cell-to-9-cell field ceiling over a two-week run, plus the shape
invariants) point the repository rig's override at the same file: the rig resolves a module
by path, so a copy of the installed file outside `node_modules` is what it takes.

```
COST_RIG_MODULE=<copy>/index.ts bash packages/deepseek-cost/rig/run.sh
```
