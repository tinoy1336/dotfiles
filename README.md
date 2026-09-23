# dotfiles

[![CI](https://github.com/tinoy1336/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/tinoy1336/dotfiles/actions/workflows/ci.yml)

The configuration of one Arch Linux machine, versioned so that a rebuild starts
from what the machine actually runs rather than from memory.

The desktop is Hyprland. The shell is tinshell, a GTK4/AGS shell that lives in a
separate repository and keeps its own live config in `~/.config/tinshell/`. What
is here is everything hand-written around them: the compositor configuration and
the Lua it consumes, GTK and terminal theming, systemd user units, the
per-machine host declaration, and the scripts in `~/.local/bin`.

## What this is not

- **Not a portable dotfiles setup, and not an installer.** Nothing here
  bootstraps a machine: there is no `install.sh` at the root, no templating
  layer, and no package list. The files are the configuration of one installed
  system, taken as-is.
- **Not machine-independent.** Absolute paths, a hostname, a username and a set
  of device-specific rules appear throughout, because that is what the files on
  disk contain. Enough of them do something only on this hardware (an
  accelerometer for display rotation, an ASUS keyboard, an AMD GPU watchdog)
  that copying a file without reading it is the wrong move.
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
| `.config/hosts/HOSTNAME/` | this machine's declaration — the units it enables, and the root-scoped files it installs at their absolute paths. Read by `~/.local/bin/host-apply` |
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

`~/.config/hosts/<machine>/host.conf` is the record of which units a rebuild has
to enable: git carries the unit files but not the enablement links. Two more
things do not travel with the clone and need a hand — the pre-commit hook, which
lives in the bare directory, and the two `node_modules` shims the shell's
`setup.sh` recreates.

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
   address; the keyboard script targets an ASUS model. Both are inert on other
   hardware and can be deleted.
5. **Everything requiring the shell.** The tinshell config in `.config/tinshell/`,
   its units, and the `~/.local/bin` scripts that call `tinshell-route` do nothing
   without that project installed.

## Checks

`.github/workflows/ci.yml` runs three jobs, each of which is also a script under
`.github/scripts/` so it can be run locally before a commit:

```sh
# each job is a script, so a local run and the CI run are the same run
export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"
.github/scripts/shellcheck.sh /tmp/shellcheck
.github/scripts/secrets-scan.sh /tmp/gitleaks
.github/scripts/restore-rehearsal.sh "$HOME/.dotfiles.git"
```

The rehearsal is the one with real value: it proves the committed set can rebuild
a home directory — the clone restores, the index and the file count match the
commit, the symlinks keep their targets, nothing outside the tracked set appears,
and `status` comes back quiet in the restored tree. It runs against the
repository itself, so in a normal checkout the argument is `.` and here it is the
bare metadata directory.

## Licence

MIT — see [LICENSE](LICENSE).
