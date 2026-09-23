# Contributing

This repository is one machine's configuration. Most changes to it are its
author's own; what follows is what a change from outside looks like, and what a
change has to satisfy either way.

## The workflow

There is no `npm install` and no build. Everything is a file that an application
on this machine reads, edited in place and committed through the wrapper, which
pairs the bare metadata directory with `$HOME`:

```sh
dotfiles status                   # what differs from the recorded set
dotfiles add .config/kitty/kitty.conf
dotfiles commit -m "kitty: raise the window padding"
dotfiles push
```

The wrapper refuses the blanket forms of `checkout`, `restore`, `reset --hard`
and `clean`, because the work tree is the running system. A restore is the pair it
allows — `dotfiles read-tree HEAD` to build the index from the commit, then
`dotfiles checkout-index -a` to write the tracked set, naming any file already in
the way rather than overwriting it. `DOTFILES_ALLOW_DESTRUCTIVE=1` is the escape
hatch for the forms that do overwrite.

### The wrapper acts on the live home directory

The wrapper sets `GIT_DIR="$HOME/.dotfiles.git"` and `GIT_WORK_TREE="$HOME"`
itself, whatever the environment says. That is what makes it usable at all — git
cannot be aimed at that pair by accident — and it is also the hazard: any command
run through the wrapper that writes the work tree writes the home directory you
are logged into. `checkout`, `reset`, `clean` and `restore` discard uncommitted
work, and the work tree is the whole home directory rather than one project, so
the loss is not confined to the file being worked on. The guards above lower the
odds of that happening by accident; they do not make a blanket form safe.

Consequences worth knowing before the first command:

- Use `git` directly, with `GIT_DIR` and `GIT_WORK_TREE` set to a scratch pair,
  for anything that has to exercise the work tree — a rehearsal, a test, a
  scripted restore. `.github/scripts/restore-rehearsal.sh` does exactly that, and
  refuses to run unless the wrapper it drives resolves its git directory inside
  the scratch tree.
- Anything that runs a variant of the wrapper — a copy, a function that calls it,
  an env override — still ends up at the real `$HOME`. Overriding the environment
  does not redirect it; only a wrapper whose own home is the scratch tree does.
- `dotfiles add` and `dotfiles commit` are the safe pair, and the only wrapper
  calls a change to this repository needs.

## Adding a file

`.gitignore` is a whitelist. Every entry at the home root is ignored unless a `!`
line re-includes it, so a new file needs a line of its own, for the narrowest path
that carries the change. Never add `!` for a cache, an application profile, a
credential store or a transcript directory — the hard-deny section exists for
exactly those, and the `.local/bin/tinshell-route` case shows the shape a
re-include takes when the file is a symlink into another tree.

## Commits

Conventional Commits, one subject line naming the area, and a body that says why
in terms of the configuration rather than what the diff does:

```text
fix(hypr): stop the idle timer locking the screen on a lap cat

The lock fires on the keyboard-idle timer while the lid is closed and a
Bluetooth controller is waking the session…
```

House style for anything a reader sees — comments, README text, commit bodies:
technical fact only. No dates, no notes about how a value was discovered, no
references to a plan document. A comment that explains a constraint is worth
its lines; a comment that records the history of the change is not.

## The installer

`./install.sh <target-home>` populates a home directory from a clone of this
repository; the README documents it for a reader who is not its author. The
implementation is `.github/scripts/dotfiles-install.sh`, and
`.github/scripts/installer-smoke.sh` is the job that holds it to what it
promises.

Three rules a change to that script has to keep:

- **It never runs the `dotfiles` wrapper.** Every git call goes through
  `git_permitted`, whose permitted set holds no `checkout`, `reset`, `clean`,
  `restore`, `stash` or `read-tree`: the target files are written by the script
  itself, from the cloned commit. That is the wrapper hazard above, removed by
  construction rather than by care.
- **A file that exists and differs is never overwritten without `--force`.**
  Each one is named under `skipped` in the summary, and the target is left byte
  for byte as it was.
- **The placeholder set stated in the README stays complete.** A new placeholder
  is a row in that table and a step in the installer, in the same change. A value
  the machine must read at runtime belongs in a local artifact rather than in the
  tracked file: a tracked template whose `*.in` name no tool loads, rendered into
  the gitignored destination beside it, or a name the machine's own tool resolves
  as a link to the tracked one. `.gitconfig` is the one tracked file the installer
  writes verbatim, because its content is the identity the published history
  carries.

Adding a file under `.github/` needs no `.gitignore` change — `!/.github/`
re-includes the directory — but a file the installer should NOT write into a home
directory belongs in its `surface` list beside `.github/`, `README.md`,
`CONTRIBUTING.md`, `LICENSE` and `install.sh`.

## Before pushing

Run what CI runs. Each job is a script, so a green local run and a green CI run
are the same run:

```sh
.github/scripts/shellcheck.sh
.github/scripts/secrets-scan.sh
.github/scripts/restore-rehearsal.sh .
.github/scripts/installer-smoke.sh .
```

`shellcheck.sh` lints every shell script the repository tracks. A finding fails
unless the same file and check appear in `.github/scripts/shellcheck-allowlist.txt`,
which records what the tree already has; anything else has to be fixed rather
than added to that file.

`restore-rehearsal.sh` clones the repository bare into a scratch directory, restores
the tracked set into a scratch `HOME` through a wrapper whose own home is that
directory, and verifies the result. It is the check that catches a file that was
added to the index but can no longer be produced from a clone. Run it with the
repository as an argument — `"$HOME/.dotfiles.git"` here, `.` in a checkout.

`installer-smoke.sh` installs into a scratch directory under `${TMPDIR:-/tmp}`
and then checks what came out of it: the filled-in values reached the files the
tools read — the rendered wireplumber fragment, the machine's name linked to the
tracked declaration, the target home path — a second run wrote nothing and
changed nothing, a pre-existing file that differs was named and left alone, and
the root refusal fires. It checks the root forwarder too: `./install.sh` has to be
executable and has to reach the installer it names, because a forwarder pointing
at nothing fails silently everywhere else. It takes the checkout as an argument,
and reads the repository — it never writes to it.

## Adapting the repository to another machine

The README's adaptation list is the short version, and `./install.sh` is what
creates the machine's own artifacts on the way in: it renders the wireplumber
fragment from its template and links this machine's name to the host declaration.
`--no-substitute` writes the tracked content exactly as committed and creates
neither, for a reader who would rather do both by hand.

In practice, past what the installer does: drop the units that exec scripts under
`~/dev/tinshell`, and replace or delete the device rules that name hardware the
new machine does not have. Keep the whitelist direction of `.gitignore` and the
wrapper — both exist because the work tree is a live system, and both stop
working the moment the git directory moves inside it.
