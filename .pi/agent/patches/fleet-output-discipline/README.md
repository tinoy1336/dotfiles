# Local patch: `pi-fleet` foreman output discipline

**One file, one hunk pair.** `output-discipline.patch` patches
`@tinoy/pi-fleet/section.ts` only.

## What it carries

The published 0.2.4 section permits two output failures and its own message
vocabulary has no room for an answer:

- it lists the shapes a message may take as a landed bullet, a question and the
  closing summary — a closed set, so a question that wants a paragraph reads as
  a bullet is the only shape available;
- it says a turn with nothing to report returns no text, but never names the
  placeholder a turn reaches for when it must emit something.

The patch carries the tightened text: a bullet reports a LANDING (worker, state,
artifact as a path) and no in-flight or liveness line counts as one; a turn with
nothing to report carries no text at all, with the placeholder explicitly
forbidden (`.`, `…`, "no action", a line restating the rule) and the turn that
ends after a tool call on a reasoning block alone named as the same failure seen
from the other side; PROSE is required whenever the requester asks a question,
requests a plan, an explanation or an opinion, or reports a defect; the message
is the shortest one that carries the information; and a stylistic choice the
house files already answer stays the foreman's to make.

`SECTION_VERSION` moves 9 → 10 so a diff in the section is attributable in the
cache log instead of appearing as an anonymous miss.

## Applied automatically

`apply-patches.sh` in the directory above keeps this patch applied, from the
entry `fleet-output-discipline` in `../managed-patches.conf`. The dry run uses
`--fuzz=0`, so a target whose surrounding code moved fails loudly instead of
being fuzz-applied, and the package is left byte-identical: the patch is applied
to copies in a staging directory and each patched copy is renamed over its
original. `pre-patch/section.ts.<version>` keeps the bytes as packaged.

## Is it applied?

```
grep -cF 'A turn with nothing to report carries NO text at all' /home/tinoy/.pi/agent/npm/node_modules/@tinoy/pi-fleet/section.ts
```

`1` = applied · `0` = not applied, or an update replaced the file. A dry run
confirms it, and the two directions read differently:

```
patch -p1 --dry-run    -d <pkg> < <patch>   # "Reversed (or previously applied) patch detected!" = applied
patch -p1 --dry-run -R -d <pkg> < <patch>   # "Unreversed patch detected!" = not applied
```

## When it takes effect

At the **next pi session start**: pi loads extension modules at startup and a
running session keeps the module it loaded, so a foreman session started after
the apply run carries the tightened section and the session that was open while
it ran keeps the old one until it ends.

The patch is a bridge to the published release and nothing more: once a pi-fleet
release carries the change, the installed bytes match without it, and the entry
becomes a no-op that can be retired.

The trigger that re-applies patches after an npm rewrite is the systemd path
unit, whose `PathModified=` list names one watched directory per patched
package. This package is not on that list yet, so a rewrite of it lands
unpatched until either the list gains the package directory and the unit is
reloaded, or the release supersedes the patch.

## Apply by hand

```
patch -p1 -d /home/tinoy/.pi/agent/npm/node_modules/@tinoy/pi-fleet \
  < /home/tinoy/.pi/agent/patches/fleet-output-discipline/output-discipline.patch
```

Prefer `apply-patches.sh`: it reads the applied state from the installed file,
requires a clean dry run before writing, keeps the per-version rollback copy and
records what it did.

## Checking the installed bytes

The section is a module constant, so the applied text can be read back without
loading the package: `grep -cF` for any of the new marker strings (above) is the
whole check, and `../doctor.sh -v` re-greps every manifest marker against the
installed files.
