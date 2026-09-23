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
It asks for the two values it cannot know — the paired headset's Bluetooth
address and this machine's hostname — and takes them as flags instead when it is
not attached to a terminal:

```sh
./install.sh /home/someone \
  --bluetooth-address 00:11:22:33:44:55 \
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
writes the tracked content exactly as it is committed, placeholders included.

## The placeholders in the tracked set

Three values are not this repository's to keep. They are written as placeholders
so they read as obviously incomplete rather than as silently wrong, and the
installer replaces all three — a manual copy has to:

| placeholder | where it sits | what replaces it |
| --- | --- | --- |
| `AA:BB:CC:DD:EE:FF`, and WirePlumber's underscore form `AA_BB_CC_DD_EE_FF` | `.config/wireplumber/wireplumber.conf.d/50-bt-default.conf` — in the comment and in the two matchers | the paired headset's Bluetooth address. WirePlumber spells it with underscores inside node and device names. Until it is filled in, the volume-pinning rules match no device; the rest of that file, which gives any Bluetooth sink the default output, does not name a device |
| `HOSTNAME` | the directory `.config/hosts/HOSTNAME/`, and the path in the first line of its `host.conf` | the machine's own hostname, `hostnamectl --static` — the name `~/.local/bin/host-apply` looks up, so rename the directory and rewrite that line together |
| `/home/tinoy` | the Hyprland configuration and binds, the systemd user units, the environment snippets, the comment at the top of `.gitignore` | the target home directory, wherever a tracked file names it |

`.gitconfig` is deliberately **not** on that list. It carries the repository
author's name and address because that is the identity the published history is
committed under, and the installer writes it verbatim; change it if the machine
is not the author's.

## What this is not

- **Not a portable dotfiles setup, even with the installer.** The installer
  fills in the three placeholders above and nothing else: the files are the
  configuration of one installed system, taken as-is.
- **Not machine-independent.** Absolute paths, a hostname and a set of
  device-specific rules appear throughout, because that is what the files on disk
  contain. The installer substitutes the home path and the hostname; the device
  rules need a decision per machine, and enough of them do something only on this
  hardware (an accelerometer for display rotation, an ASUS keyboard, an AMD GPU
  watchdog) that copying a file without reading it is the wrong move.
- **Not a mirror of the shell it drives.** The shell's code and its packaged
  units come from the tinshell repository and its `setup.sh`. This repository
  carries the live config and the units that are installed on this machine, not
  the sources that generate them.
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
`~/.config/gh/`, `~/.local/share/keyrings/`, `~/.local/share/cli-keys/`,
`~/.pi/`, `~/.local/state/`, `~/.cache/` and the other tool trees are named
there explicitly, each on its own line, so a future re-include cannot sweep them
back in. Adding a file means adding a `!` line for the narrowest path that
carries it.

The same file is a second, functional ignore for the whole home directory:
`core.excludesFile` points at `~/.config/git/ignore`, which is where `**/.claude/`
and friends are kept out of unrelated `git add` calls.

## Layout

| Path | What it holds |
| --- | --- |
| `.config/hypr/` | Hyprland configuration (`hyprland.lua` and the conf files it loads), idle timers, lock screen, the workspace-cycle and plugin-loader scripts |
| `.config/tinshell/` | the shell's live config, one JSON file per surface |
| `.config/systemd/user/` | the user units: the shell, the artifact warm, the portal, polkit, swaync, wallpaper and rotation units |
| `.config/hosts/HOSTNAME/` | a machine's declaration — the units it enables, and the root-scoped files it installs at their absolute paths. Read by `~/.local/bin/host-apply`, which looks the directory up by this machine's hostname; the installer renames it from the placeholder |
| `.config/gtk-3.0/`, `.config/gtk-4.0/` | GTK theming and its window-decoration assets |
| `.config/` (single files) | terminal, launcher, file-dialog, wallpaper and portal config, `mimeapps.list` and the XDG user directories |
| `.local/bin/` | the hand-written scripts: the wrapper, `host-apply`, the sudo and zenity shims, the AGS-facing helpers, the promptd clients |
| shell and identity | `.zshrc`, `.zshenv`, `.bashrc`, `.gitconfig`, `.tmux.conf`, `.gtkrc-2.0` |
| `.github/` | the CI workflows and the scripts they run |

## What is deliberately not tracked

Credential stores and key material (`~/.npmrc`, `~/.config/gh/`, the keyrings,
the pass-cli vault's local key store), agent state under `~/.pi/`, machine state
under `~/.local/state/` and `~/.local/share/`, caches, shell history, browser
profiles, and the project tree at `~/dev/tinshell` — which is its own repository
and is not part of this one.

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

bash ~/dev/tinshell/setup.sh   # the shell's own tree, units, links and root steps
host-apply                     # re-enable the units this host declares
```

`~/.config/hosts/<hostname>/host.conf` is the record of which units a rebuild
has to enable: git carries the unit files but not the enablement links, and
`host-apply` opens the directory named after the machine (`hostnamectl --static`).
A restore by hand renames `.config/hosts/HOSTNAME/` to that name and rewrites the
path in the first line of its `host.conf`. Two more things do not travel with the
clone and need a hand — the pre-commit hook, which lives in the bare directory,
and the two `node_modules` shims the shell's `setup.sh` recreates.

## Adapting it to another machine

Reading it is the point; running it elsewhere needs the following, roughly in
order of how much they matter:

1. **Paths and user name.** `/home/tinoy` is written literally in the Hyprland
   binds, the idle timers, the units and the environment snippets. A different
   home directory means editing those, or substituting them at install time the
   way the shell's `setup.sh` does for its own units.
2. **Project-independent units.** Several units exec scripts under
   `~/dev/tinshell`. Without that tree they install and then fail; drop them.
3. **Host-specific hardware.** `.config/hosts/<machine>/` declares the rotation,
   sleep-inhibit, Bluetooth and fan units for one laptop, and its `root/` tree
   mirrors files into `/etc` and `/usr/local`. Replace the directory, keep the
   shape.
4. **Device rules.** The wireplumber rules name a paired headset by its Bluetooth
   address, which is a placeholder here — the address-pinning entries are inert
   until it is filled in, and on hardware without that headset they stay inert.
   The keyboard script targets an ASUS model. Both can be deleted.
5. **Everything requiring the shell.** The tinshell config in `.config/tinshell/`,
   its units, and the `~/.local/bin` scripts that call `tinshell-route` do nothing
   without that project installed.

## Checks

`.github/workflows/ci.yml` runs four jobs, each of which is also a script under
`.github/scripts/` so it can be run locally before a commit:

```sh
# each job is a script, so a local run and the CI run are the same run
export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"
.github/scripts/shellcheck.sh /tmp/shellcheck
.github/scripts/secrets-scan.sh /tmp/gitleaks
.github/scripts/restore-rehearsal.sh "$HOME/.dotfiles.git"
.github/scripts/installer-smoke.sh .
```

The rehearsal is the one with real value for a reader: it proves the committed
set can rebuild a home directory — the clone restores, the index and the file
count match the commit, the symlinks keep their targets, nothing outside the
tracked set appears, and `status` comes back quiet in the restored tree. It runs
against the repository itself, so in a normal checkout the argument is `.` and
here it is the bare metadata directory.

The installer job is the one with real value for someone who is not this
machine's author: it installs into a scratch home and then checks what the
installer promises — every filled-in value arrived, a second run writes nothing
and changes nothing, a file that already exists and differs is named and left
alone, and running as root is refused.

## Licence

MIT — see [LICENSE](LICENSE).
