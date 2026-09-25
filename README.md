# dotfiles

[![CI](https://github.com/tinoy1336/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/tinoy1336/dotfiles/actions/workflows/ci.yml)

The configuration of one Arch Linux machine, versioned so that a rebuild starts
from what the machine actually runs rather than from memory.

The desktop is Hyprland. The shell is tinshell, a GTK4/AGS shell that lives in a
separate repository and keeps its own live config in `~/.config/tinshell/`. What
is here is everything hand-written around them: the compositor configuration and
the Lua it consumes, GTK and terminal theming, systemd user units, the
per-machine host declaration, and the scripts in `~/.local/bin`.

## Install it onto a machine

One script takes this repository from GitHub and populates a home directory with
it, filling in the values that belong to the machine rather than to the
repository:

```sh
git clone https://github.com/tinoy1336/dotfiles.git
cd dotfiles
./install.sh "$HOME"
```

It clones the repository into `$HOME/.dotfiles.git`, writes the tracked
configuration into the home directory you name, and prints every path it wrote.
The values that belong to the machine rather than to the configuration are
derived from the machine the script runs on: the hostname from `hostnamectl
--static` (falling back to `hostname -s`), and the user name from the target
home — `/home/<name>` is owned by `<name>`, and any other target belongs to the
user running the script. `--hostname` and `--user` are the overrides for
installing onto a machine you are not on, and a `--user` that disagrees with the
home being installed into is reported and honoured:

```sh
./install.sh /home/someone \
  --hostname someone-laptop \
  --user someone
```

What it will not do:

- **Overwrite a file that already exists and differs.** Each one is named under
  `skipped` in the summary and left byte for byte as it was, so a distribution
  `.bashrc` survives the install. `--force` applies the repository's version
  instead, printing the md5 of what it replaced.
- **Run as root.** The tracked configuration is one user's, and root's home is
  never the target.
- **Write anything outside the target home.** The clone lives in
  `<target-home>/.dotfiles.git`, and the script refuses to proceed if that path
  resolves anywhere else.
- **Use the `dotfiles` wrapper for anything that writes.** No `checkout`,
  `reset`, `clean` or `restore` is ever run, so a home directory that already
  holds uncommitted work cannot lose it — see
  [CONTRIBUTING.md](CONTRIBUTING.md), which is where that rule is written down.

Running it twice is safe: the second run reports every path unchanged and writes
nothing. `--dry-run` prints the plan and changes nothing, and `--no-substitute`
writes the tracked content exactly as it is committed and creates neither local
artifact below, placeholders included.

## The placeholders in the tracked set

Two values are not this repository's to keep: this machine's hostname and the
author's home path. They are written as placeholders so they read as obviously
incomplete rather than as silently wrong.

The hostname cannot simply be left in a tracked file and substituted on the way
in, because this checkout is also a live home directory: whatever is tracked is
what the machine reads. So the tracked set carries the *shape* of the name and
the machine keeps the name itself, in a link git ignores. The home path is the
one value the installer substitutes as it writes, because it names no content of
its own.

| value | the tracked file | where the machine's value lives | how the tool finds it |
| --- | --- | --- | --- |
| `HOSTNAME` | the directory `.config/hosts/HOSTNAME/` and its `host.conf` — a machine's declaration, under the placeholder name | this machine's own name, as the link `.config/hosts/<hostname>` → `HOSTNAME`, which `.gitignore` excludes | `~/.local/bin/host-apply` opens the directory named by `hostnamectl --static`; the name is the link, the declaration stays the tracked directory, and no content is copied to drift from it |
| `/home/tinoy` | the Hyprland configuration and binds, the systemd user units, the environment snippets, the comment at the top of `.gitignore` | — | the installer substitutes it on the way in; nothing reads it at runtime |

`.config/wireplumber/wireplumber.conf.d/50-bt-default.conf` names no device: it is
the rule that gives any Bluetooth sink the default slot, so it is the same on
every machine. No device's volume is configured anywhere in the tracked set:
WirePlumber stores the volume and mute of every device route in its own state
directory and restores them when the route comes back, so each device returns at
the level it was left at. `10-default-sink-volume.conf` holds the one value such
a route takes when it has nothing stored — a device's first use on a machine, and
its first use after the state directory is cleared.

The installer creates the one local artifact: it links the machine's name to the
declaration. By hand it is that one command:

```sh
ln -s HOSTNAME ~/.config/hosts/$(hostnamectl --static)
```

`.gitconfig` is deliberately **not** on that list. It carries the repository
author's name and address because that is the identity the published history is
committed under, and the installer writes it verbatim; change it if the machine
is not the author's.

## What this is not

- **Not a portable dotfiles setup, even with the installer.** The installer
  fills in the two placeholders above and nothing else: the files are the
  configuration of one installed system, taken as-is.
- **Not machine-independent.** Absolute paths, a hostname and a set of
  device-specific rules appear throughout, because that is what the files on disk
  contain. The installer substitutes the home path and the hostname; the device
  scripts need a decision per machine, and enough of them do something only on
  this hardware (an accelerometer for display rotation, an ASUS keyboard, an AMD
  GPU watchdog) that copying a file without reading it is the wrong move.
- **Not a mirror of the shell it drives.** What is carried here is this home's
  configuration, the shell's live config included: `.config/tinshell/` holds the
  values the running desktop reads. The shell's machinery belongs to the shell's
  own repository — the unit files it declares and the promptd clients it links
  into `~/.local/bin` are templates and sources in the tinshell tree, installed
  by its `setup.sh`, and are not tracked here. A path whose only reason to exist
  is that the shell runs is that repository's to carry.
- **Not a backup of the home directory.** The tracked set is a whitelist; see
  below.

## How the repository is shaped

The git metadata lives outside the work tree, because the work tree is the home
directory itself and a stray `.git/` there would make every other tool treat
`$HOME` as a repository:

```text
/home/tinoy/.dotfiles.git     bare metadata
/home/tinoy                   work tree
/home/tinoy/.local/bin/dotfiles   the wrapper that pairs the two
```

`git` cannot be aimed at that pair by accident, so the wrapper exports `GIT_DIR`
and `GIT_WORK_TREE` and then execs git. Those two values come from `$HOME` and
nothing else, which is the point and also the hazard: a command run through the
wrapper writes the home directory you are logged into — including the live config
of applications that are running — and one that discards uncommitted work discards
it there. Two guards lower the odds of that happening by accident: a blanket
`checkout`, `restore`, `reset --hard` or `clean` is refused unless
`DOTFILES_ALLOW_DESTRUCTIVE=1` is set. Naming an explicit pathspec after
`--` stays allowed, and restoration runs through `read-tree` and `checkout-index`,
the pair that works from a clone with no index.

Commits go through the same wrapper:

```sh
dotfiles status                  # what differs from the recorded set
dotfiles add .config/kitty/kitty.conf
dotfiles commit -m "kitty: …"    # Conventional Commits
dotfiles push
```

`$GIT_DIR/hooks/pre-commit` refuses a staged set larger than 2000 files or
50 MiB. That limit is aimed at the one accident that matters here: an edit to
the ignore file that loosens the whitelist, followed by a blanket stage of the
home directory.

### The tracked set is a whitelist

`.gitignore` starts from `/*` — every entry at the home root is ignored — and
re-includes the directories and files that carry intent. The mechanism is what
keeps a machine's credentials, state and caches out of the repository:
`~/.config/gh/`, `~/.local/share/keyrings/`, `~/.pi/`, `~/.local/state/`,
`~/.cache/` and the other tool trees are named there explicitly, each on its own
line, so a future re-include cannot sweep them back in. Adding a file means
adding a `!` line for the narrowest path that carries it.

The same file is a second, functional ignore for the whole home directory:
`core.excludesFile` points at `~/.config/git/ignore`, which is where `**/.claude/`
and friends are kept out of unrelated `git add` calls.

## Layout

| Path | What it holds |
| --- | --- |
| `.config/hypr/` | Hyprland configuration (`hyprland.lua` and the conf files it loads), idle timers, lock screen, the workspace-cycle and plugin-loader scripts |
| `.config/tinshell/` | the shell's live config, one JSON file per surface |
| `.config/wireplumber/` | the WirePlumber drop-ins — Bluetooth sinks take the default slot, and a device route with nothing stored starts at one set volume |
| `.config/systemd/user/` | the units this machine declares and enables: wallpaper, display rotation, key refresh and the patch applier's. The shell's own units — the shell, the artifact warm, the portal, polkit, the watchdog — are templates in the shell's tree, rendered to this directory by its `setup.sh`, and are not tracked here |
| `.config/hosts/HOSTNAME/` | a machine's declaration — the units it enables, and the root-scoped files it installs at their absolute paths. Read by `~/.local/bin/host-apply`, which looks the directory up by this machine's hostname; the installer links that name to this directory, so the declaration stays tracked under the placeholder name |
| `.config/gtk-3.0/`, `.config/gtk-4.0/` | GTK theming and its window-decoration assets |
| `.config/` (single files) | terminal, launcher, file-dialog, wallpaper and portal config, `mimeapps.list` and the XDG user directories |
| `.local/bin/` | this machine's hand-written scripts: the wrapper, `host-apply`, the sudo shim, the desktop helpers. The promptd clients are linked here by the shell's `setup.sh` and are not tracked |
| shell and identity | `.zshrc`, `.zshenv`, `.bashrc`, `.gitconfig`, `.tmux.conf`, `.gtkrc-2.0` |
| `.github/` | the CI workflows and the scripts they run |

## What is deliberately not tracked

Credential stores and key material (`~/.npmrc`, `~/.config/gh/`, the keyrings,
the pass-cli vault's local key store), agent state under `~/.pi/`, machine state
under `~/.local/state/` and `~/.local/share/`, caches, shell history, browser
profiles, and the shell's own project tree — a separate repository, not part of
this one, its unit files and the promptd clients its `setup.sh` installs
included.

## Restoring this onto a fresh machine

`./install.sh "$HOME"` is the whole of it — see
[Install it onto a machine](#install-it-onto-a-machine). What follows is the same
work by hand, for a reader who wants to see each step, or whose home directory
has files in the way that the installer would report and leave alone.

The bare shape costs one extra step: a clone hands over metadata, not a checked
out configuration, and the wrapper that pairs the metadata with `$HOME` has to be
in place before anything can be checked out.

```sh
git clone --bare <remote> "$HOME/.dotfiles.git"

# the wrapper comes from the clone itself; without it the pair cannot be set
git --git-dir="$HOME/.dotfiles.git" show HEAD:.local/bin/dotfiles > "$HOME/.local/bin/dotfiles"
chmod 0755 "$HOME/.local/bin/dotfiles"

# repo-local settings do not travel with a clone
dotfiles config feature.manyFiles true
dotfiles config core.fileMode true
dotfiles config core.autocrlf false
dotfiles config core.excludesFile "$HOME/.config/git/ignore"

dotfiles read-tree HEAD    # the index from the commit; nothing on disk changes
# writes the tracked set into $HOME and names any file already in the way
# instead of overwriting it — a distribution .bashrc is left as it is, per path
dotfiles checkout-index -a

bash <path-to-tinshell>/setup.sh   # the shell's own tree: units, clients, links and root steps
host-apply                     # re-enable the units this host declares
```

`host-apply` follows `setup.sh` and not the other way round: the units
`host.conf` enables include the shell's two, and those arrive with `setup.sh`,
not with the checkout above.

`~/.config/hosts/HOSTNAME/host.conf` is the record of which units a rebuild has
to enable: git carries the unit files this machine declares but not the
enablement links, and `host-apply` opens the directory named after the machine
(`hostnamectl --static`).
A restore by hand links that name to the tracked declaration — `ln -s HOSTNAME
~/.config/hosts/$(hostnamectl --static)` — which is the command under
[The placeholders in the tracked set](#the-placeholders-in-the-tracked-set). Two
more things do not travel with the clone and need a hand — the pre-commit hook,
which lives in the bare directory, and the two `node_modules` shims the shell's
`setup.sh` recreates.

## Adapting it to another machine

Reading it is the point; running it elsewhere needs the following, roughly in
order of how much they matter:

1. **Paths and user name.** `/home/tinoy` is written literally in the Hyprland
   binds, the idle timers, the units and the environment snippets. A different
   home directory means editing those, or substituting them at install time the
   way the shell's `setup.sh` does for its own units.
2. **Units.** The units carried here run this machine's own scripts — the
   rotation helper, the key refresher, the wallpaper applier — plus a packaged
   binary and the patch applier under `~/.pi/`. Replace or drop the ones whose
   script the new machine does not have; the shell's own units are not carried
   here at all and arrive only with its `setup.sh`.
3. **Host-specific hardware.** `.config/hosts/<machine>/` declares the rotation,
   sleep-inhibit, Bluetooth and fan units for one laptop, and its `root/` tree
   mirrors files into `/etc` and `/usr/local`. Replace the directory, keep the
   shape.
4. **Device rules.** Nothing in the tracked set names a device: the volume a
   device route starts at is one value in the wireplumber drop-ins, applied
   wherever a route has no stored volume, and each device's own level afterwards
   is WirePlumber's state. The keyboard script targets an ASUS model, so it can
   be deleted on hardware that is not that laptop.
5. **Everything requiring the shell.** The live config in `.config/tinshell/`,
   the unit names `host.conf` enables, and the `~/.local/bin` scripts that call
   `tinshell-route` do nothing without that project installed; its own units and
   its promptd clients reach this home only through its `setup.sh`.

## The files rendered from the house palette

Every colour and opacity this home configures comes from one source: the house
palette repository (`https://github.com/tinoy1336/house-palette`). That repository
holds the tokens (`palette.json`) and a renderer (`bin/render`); it holds no
template for any program and knows no destination. Each program's values are
therefore rendered here, by a template that lives beside the file it produces,
and this repository gates both.

A carrier is three files: the template (`<name>.template.ts`), the rendered file,
and the renderer's record of it (`<name>.record.json`). The record names the
digests of the template, the palette and the output and no path at all, so it is
identical in every checkout and a gate can compare it.

| Carrier | Template | Rendered file, and what reads it |
| --- | --- | --- |
| terminal | `.config/kitty/palette.house.template.ts` | `.config/kitty/palette.house.conf`, included by `kitty.conf` |
| GTK3 apps | `.config/gtk-3.0/palette.gen.template.ts` | `.config/gtk-3.0/palette.gen.css`, imported by `gtk.css` |
| GTK4 / libadwaita apps | `.config/gtk-4.0/palette.gen.template.ts` | `.config/gtk-4.0/palette.gen.css`, imported by `gtk.css` |
| GTK2 apps | `.config/gtkrc.house.template.ts` | `.config/gtkrc.house`, included by `.gtkrc-2.0` |
| the compositor | `.config/hypr/palette.template.ts` | `.config/hypr/palette.lua`, required by `hyprland.lua` |
| the lock screen | `.config/hypr/hyprlock.colours.template.ts` | `.config/hypr/hyprlock.colours.conf`, sourced by `hyprlock.conf` |
| git | `.config/git/colors.template.ts` | `.config/git/colors.inc`, included by `.gitconfig` |
| tmux | `.config/tmux/colors.template.ts` | `.config/tmux/colors.conf`, sourced by `.tmux.conf` |
| the login shell | `.config/zsh/house-colors.template.ts` | `.config/zsh/house-colors.sh`, sourced by `.zshrc` |
| KDE / Plasma | `.config/house-palette/kdeglobals.colours.template.ts` | `.config/house-palette/kdeglobals.colours.ini`, merged by hand into `kdeglobals` on a machine that installs that desktop |
| the chat client | `.config/vesktop/settings/quickCss.template.ts` | `.config/vesktop/settings/quickCss.css`, watched by the client |
| the music player | `.config/YouTube Music/themes/house.template.ts` | `.config/YouTube Music/themes/house.css`, named by the player's theme list, added by hand |
| the agent | `.pi/agent/themes/house.template.ts` | `.pi/agent/themes/house.json`, selected by `.pi/agent/settings.json` |

The record beside each rendered file is what lets a gate tell a current file from
a stale one; it is committed with the file and never edited by hand.

Generation is the first of three separate facts about a carrier. The second is
whether the program reads the rendered file at all, and the third is how it comes
to: a file whose program selects it with one line, in a loader that travels with
the tracked set, arrives through that line and nothing else; a file whose program
has no include mechanism, or is not installed here, is written and read by
nothing; and a file whose only reader keeps live session state in the same file is
named there by hand, once, deliberately. The table's last column says which case
each carrier is in, and the section below says why the two exceptions are
exceptions.

### Re-rendering

The renderer is a program from the palette repository, so it is named on the
command line rather than vendored here:

```sh
# once, to have the renderer locally
git clone https://github.com/tinoy1336/house-palette

# compare every carrier against a fresh render (the CI job runs exactly this)
.github/scripts/palette-check.sh <path-to-house-palette>/bin/render

# re-render every carrier after a template or palette change
.github/scripts/palette-check.sh <path-to-house-palette>/bin/render --render
```

A single carrier takes the same two commands with the renderer's own arguments,
which is what the header of every rendered file repeats:

```sh
bin/render --template .config/tmux/colors.template.ts \
  --out .config/tmux/colors.conf --record .config/tmux/colors.conf.record.json
```

Edit a template, re-render, read the diff, then commit the template, the rendered
file and the record together. A rendered file is never edited by hand: its first
line says it was generated, and the gate overwrites or reports anything that
disagrees with its template. One carrier cannot carry that line — pi reads its
theme as JSON, which has no comment syntax — so for `.pi/agent/themes/house.json`
the record beside it is the only record of where it comes from.

### The pinned palette revision

`.github/scripts/palette-targets.json` lists the carriers and pins the palette
this home rendered against by its commit and its content digest. Every run passes
both to the renderer, so a palette that moved is reported before anything is
compared:

```text
palette-mismatch …/palette.json: expected 15322952…, found 4c1f0b31…
```

That is the point of the pin: taking an upstream palette change is a deliberate
act — re-render, read the diff of every carrier, commit the files and the new
revision together — rather than something that happens silently under a reader.
A carrier added later takes its own entry in that file and its own narrow `!`
lines in `.gitignore`, both in the change that adds it.

### What a gate failure says

`.github/scripts/palette-check.sh` prints the renderer's own one-line reasons and
ends with a count:

```sh
.github/scripts/palette-check.sh <path-to-house-palette>/bin/render
stale /home/tinoy/.config/tmux/colors.conf
palette: 13 target(s) checked, 1 stale, 0 could not run
```

The exit codes are the contract a job relies on: `0` every file and record is
current, `1` drift — a rendered file was edited, a template changed without a
re-render, a record is missing or was written against a different template or
palette, or the palette is not the pinned digest — and `2` the check could not
run at all: no renderer named, node missing, or a render the renderer refused. A
`2` is never drift, and a gate that reads it as a clean tree is broken.

### What is not rendered here, and why

The exceptions below are the carriers whose program cannot select a rendered file
on its own. Every other carrier already has its line: `~/.gitconfig` includes
`.config/git/colors.inc`, `~/.tmux.conf` sources `.config/tmux/colors.conf`,
`~/.zshrc` sources `.config/zsh/house-colors.sh` and `.gtkrc-2.0` includes
`.config/gtkrc.house`. Those four are tracked home-root files, so the line a
machine writes once arrives through a restore as well.

- **The desktop environment.** The KDE INI format has no include, so there is no
  place for a rendered file to attach, and no application of that environment is
  installed on this machine — nothing here reads the merged file either.
  `kdeglobals.colours.ini` is therefore a fragment: a machine that installs that
  desktop merges its sections into `~/.config/kdeglobals` by hand, leaving every
  other section there alone, and re-merges it whenever the palette moves.
- **The music player.** The generated stylesheet is written and gated, but the
  file that would name it — `.config/YouTube Music/config.json` — is the running
  player's live session state, so adding `.config/YouTube Music/themes/house.css`
  to its theme list is a step taken with the player stopped, not a line this
  repository can commit. That file is not tracked, so a rebuild repeats it.
- **GTK2.** No GTK2 application is installed on this machine, so `.gtkrc-2.0` is
  read by nothing yet. The include line is in that tracked file, so the first
  GTK2 application installed here picks the palette up with no edit; the file the
  desktop's own toolkit page used to write, `~/.config/gtkrc`, is not read by GTK2
  at all and is left as it was.
- **Values with no token.** A colour the palette does not name is not invented
  here. A rendered file that needs one fails loudly instead, naming the token it
  could not find.

## Checks

`.github/workflows/ci.yml` runs seven jobs, each of which is also a script under
`.github/scripts/` so it can be run locally before a commit:

```sh
# each job is a script, so a local run and the CI run are the same run
export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"
.github/scripts/shellcheck.sh
.github/scripts/secrets-scan.sh
.github/scripts/restore-rehearsal.sh "$HOME/.dotfiles.git"
.github/scripts/installer-smoke.sh .
.github/scripts/portability.sh
.github/scripts/boundary-check.sh
.github/scripts/palette-check.sh <path-to-house-palette>/bin/render
```

The rehearsal is the one with real value for a reader: it proves the committed
set can rebuild a home directory — the clone restores, the index and the file
count match the commit, the symlinks keep their targets, nothing outside the
tracked set appears, and `status` comes back quiet in the restored tree. It runs
against the repository itself, so in a normal checkout the argument is `.` and
here it is the bare metadata directory.

The installer job is the one with real value for someone who is not this
machine's author: it installs into a scratch home and then checks what the
installer promises — every filled-in value arrived where the tool reads it, a
second run writes nothing and changes nothing, a file that already exists and
differs is named and left alone, and running as root is refused. It also holds
the repository's root entry point to what it claims to be: `./install.sh` has to
exist, be executable, and reach the installer it names.

The boundary job is the one that holds the tracked set's membership: the shell's
own unit files and the promptd clients it links into `~/.local/bin` are that
project's, installed by its `setup.sh`, and a path from that set appearing here
again fails the run. It exists because every other job reads a tracked file for
what it says — its shell, its path references, its rendered values — and none of
them reads whether the file should be carried at all.

The palette job is the one that keeps the rendered files honest: it re-renders
every carrier listed in `.github/scripts/palette-targets.json` and compares the
result with the file and the record committed here, against the palette revision
pinned in the same file. It fetches the palette repository's renderer, because
that program belongs to that repository and is not vendored here.

## Licence

MIT — see [LICENSE](LICENSE).
