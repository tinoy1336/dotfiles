#!/usr/bin/env bash
# dotfiles-install.sh — populate a home directory from this repository.
#
#   dotfiles-install.sh <target-home> [options]
#
# The repository records one machine's configuration with the work tree set to
# $HOME and the git metadata outside it. This script reproduces that shape on
# another machine: it clones (or updates) the repository into
# <target-home>/.dotfiles.git and writes the tracked configuration into
# <target-home>, filling in the values that belong to one machine rather than to
# the repository:
#
#   the headset Bluetooth address   the tracked template
#                                   .config/wireplumber/wireplumber.conf.d/
#                                   70-bt-headset-local.conf.in carries the
#                                   placeholders AA:BB:CC:DD:EE:FF and
#                                   AA_BB_CC_DD_EE_FF; this script renders it
#                                   into the fragment beside it, the one file
#                                   there that the repository does not carry
#   the hostname                    the host declaration is tracked under the
#                                   placeholder name .config/hosts/HOSTNAME/;
#                                   this script links the machine's own name to
#                                   it, because host-apply opens the directory
#                                   named by `hostnamectl --static`
#   the absolute home path          /home/tinoy wherever a tracked file carries
#                                   it: the Hyprland configuration, the systemd
#                                   user units, the environment snippets
#
# A tracked template is a file whose name ends in .in. It is written as the
# commit carries it, placeholder intact, and its rendered twin — the same name
# without the suffix — is written beside it: that is where a machine's value
# belongs, and no tool mistakes the twin for the template, because WirePlumber
# reads only *.conf and host-apply only a directory name.
#
# Options:
#   --repo URL                clone or update from URL
#                             (default https://github.com/tinoy1336/dotfiles.git)
#   --ref REF                 branch, tag or commit to install (default: the ref
#                             the repository itself is on)
#   --bluetooth-address MAC   paired headset address, e.g. 11:22:33:44:55:66;
#                             prompted for when omitted, and rendered into the
#                             local wireplumber fragment beside the template
#   --hostname NAME           this machine's hostname; prompted for, then read
#                             from `hostnamectl --static`, when omitted
#   --user NAME               the user the target home belongs to; the paths
#                             that name a user without naming a home get it
#                             (default: the user running this script)
#   --force                   overwrite a file that exists and differs, printing
#                             the md5 of what it destroys
#   --no-substitute           write the tracked content verbatim, placeholders
#                             and absolute paths included
#   --quiet                   summary only, no per-path lines
#   --dry-run                 print the plan and change nothing
#
# What it is built to keep:
#
#   idempotent            a second run writes nothing and reports every path
#                         unchanged
#   no silent overwrite   a file that exists and differs is left alone and named,
#                         unless --force is given
#   never root            running as root is refused: the tracked configuration
#                         is one user's, and root's home is never the target
#   arbitrary target      the home directory is an argument, never implicitly
#                         $HOME
#   no destructive git    this script never invokes the repository's `dotfiles`
#                         wrapper at all. Every git call goes through
#                         git_permitted, whose permitted set holds no checkout,
#                         reset, clean, restore, stash or read-tree, so no git
#                         command here can discard what it finds in the target
#                         home; the target files are written by this script
#                         itself, from the cloned commit.
#
# Exit codes: 0 the target home matches the commit (or already did), 3 refused or
# unable to proceed (usage errors included).

set -euo pipefail

prog=${0##*/}

say() { printf '%s\n' "$*"; }
step() { [ "$quiet" -eq 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s: %s\n' "$prog" "$*" >&2; }
die() {
  printf '%s: %s\n' "$prog" "$*" >&2
  exit 3
}

usage() {
  cat <<'EOF'
Usage: dotfiles-install.sh <target-home> [options]

Clones or updates this repository into <target-home>/.dotfiles.git and writes
the tracked configuration into <target-home>, filling in the values that belong
to one machine and printing every path it writes.

  --repo URL                clone or update from URL
                            (default https://github.com/tinoy1336/dotfiles.git)
  --ref REF                 branch, tag or commit to install
                            (default: the ref the repository itself is on)
  --bluetooth-address MAC   paired headset address, e.g. 11:22:33:44:55:66,
                            rendered into the local wireplumber fragment beside
                            the tracked template
  --hostname NAME           this machine's hostname
  --user NAME               the user the target home belongs to
                            (default: the user running this script)
  --force                   overwrite a file that exists and differs, printing
                            the md5 of what it destroys
  --no-substitute           write the tracked content verbatim
  --quiet                   summary only, no per-path lines
  --dry-run                 print the plan and change nothing
  -h, --help                this text

An existing file is never overwritten without --force; each one is named under
"skipped" in the summary. Running the same command twice writes nothing the
second time.
EOF
}

# The repository URL may carry a credential in its userinfo section, and that
# value must never reach a transcript: every message that names the repository
# goes through this filter.
redact() { printf '%s\n' "$1" | sed -E 's#(://)[^/@]*@#\1#'; }

# A sed replacement is text, not a pattern: the delimiter and the two characters
# sed reads inside a replacement have to be escaped.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# ---- options -----------------------------------------------------------------
repo="https://github.com/tinoy1336/dotfiles.git"
ref=""
mac=""
host=""
user=""
target=""
force=0
substitute=1
quiet=0
dry=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --repo)
      [ $# -ge 2 ] || die "--repo needs a value"
      repo=$2
      shift 2
      ;;
    --ref)
      [ $# -ge 2 ] || die "--ref needs a value"
      ref=$2
      shift 2
      ;;
    --bluetooth-address)
      [ $# -ge 2 ] || die "--bluetooth-address needs a value"
      mac=$2
      shift 2
      ;;
    --hostname)
      [ $# -ge 2 ] || die "--hostname needs a value"
      host=$2
      shift 2
      ;;
    --user)
      [ $# -ge 2 ] || die "--user needs a value"
      user=$2
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --no-substitute)
      substitute=0
      shift
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    --dry-run)
      dry=1
      shift
      ;;
    -*)
      warn "unknown option: $1"
      usage >&2
      exit 3
      ;;
    *)
      [ -z "$target" ] || {
        warn "one target home at a time, not '$target' and '$1'"
        usage >&2
        exit 3
      }
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || {
  warn "no target home given"
  usage >&2
  exit 3
}

# ---- the two refusals that come before anything else -------------------------
if [ "$(id -u)" -eq 0 ]; then
  die "refusing to run as root: the tracked configuration is one user's, and root's home is never the target"
fi

command -v git >/dev/null 2>&1 || die "git is not installed"

case "$target" in
  /*) ;;
  *) die "the target home must be an absolute path: $target" ;;
esac
[ -d "$target" ] || die "the target home is not a directory: $target"
target=$(cd -- "$target" && pwd -P)
[ "$target" != "/" ] || die "refusing to install into /"

gitdir="$target/.dotfiles.git"
# The git directory every read below runs against: the target's own clone, or —
# for a dry run of a target that has no clone yet — a local source repository.
gdir=$gitdir
resolved=$(realpath -m -- "$gitdir")
case "$resolved" in
  "$target"/*) ;;
  *) die "refusing to proceed: the git directory $resolved resolves outside $target" ;;
esac

# The script's own git calls, and the only git calls it makes. The permitted set
# carries nothing that writes or discards a work tree (checkout, reset, clean,
# restore, stash, read-tree), because the target home is written by the loop
# below and by nothing else.
git_permitted() {
  local sub=${1:-}
  case "$sub" in
    clone | fetch | remote | rev-parse | ls-tree | cat-file | symbolic-ref) ;;
    *) die "internal refusal: git '$sub' is not in this script's permitted set" ;;
  esac
  # GIT_DIR and GIT_WORK_TREE belong to this script alone: an inherited pair
  # points at another repository, and a clone refuses to run with either set.
  env -u GIT_WORK_TREE -u GIT_INDEX_FILE GIT_DIR="$gdir" git "$@"
}

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# ---- what this machine is called, and which headset it pins ------------------
host_default=""
if command -v hostnamectl >/dev/null 2>&1; then
  host_default=$(hostnamectl --static 2>/dev/null || true)
fi
[ -n "$host_default" ] || host_default=$(hostname -s 2>/dev/null || true)

if [ -z "$host" ] && [ "$substitute" -eq 1 ] && [ -t 0 ] && [ "$dry" -eq 0 ]; then
  printf 'Hostname for the host declaration [%s]: ' "${host_default:-none}"
  IFS= read -r host || true
  [ -n "$host" ] || host=$host_default
fi
if [ -z "$host" ] && [ "$substitute" -eq 1 ]; then
  host=$host_default
fi

if [ -n "$host" ]; then
  case "$host" in
    */* | *[[:space:]]*) die "not a hostname: $host" ;;
    HOSTNAME) die "'HOSTNAME' is the placeholder this script replaces, not a hostname" ;;
  esac
fi

if [ -z "$mac" ] && [ "$substitute" -eq 1 ] && [ -t 0 ] && [ "$dry" -eq 0 ]; then
  printf 'Paired headset Bluetooth address, or blank to leave the placeholder: '
  IFS= read -r mac || true
fi
if [ -n "$mac" ]; then
  case "$mac" in
    [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) ;;
    *) die "not a Bluetooth address: $mac (expected AA:BB:CC:DD:EE:FF)" ;;
  esac
  mac=$(printf '%s' "$mac" | tr 'a-f' 'A-F')
fi

# The placeholder the repository carries, in both spellings it uses. Passing it
# back in is the same as leaving it: there is nothing to fill in.
mac_placeholder="AA:BB:CC:DD:EE:FF"
if [ "$mac" = "$mac_placeholder" ]; then
  mac=""
fi

# ---- clone or update ---------------------------------------------------------
say "$prog: repository  $(redact "$repo")${ref:+ (ref $ref)}"
say "$prog: target home $target"
say "$prog: git dir     $gitdir"
[ "$dry" -eq 0 ] || say "$prog: dry run — nothing will be written"

if [ -f "$gitdir/HEAD" ]; then
  if [ "$dry" -eq 0 ]; then
    git_permitted remote set-url origin "$repo" 2>/dev/null ||
      git_permitted remote add origin "$repo"
    git_permitted fetch --prune --tags --quiet origin '+refs/heads/*:refs/heads/*'
  fi
  origin_note="updated"
elif [ -e "$gitdir" ]; then
  die "$gitdir exists and is not a git directory — move it aside and re-run"
else
  if [ "$dry" -eq 0 ]; then
    git_permitted clone --bare --quiet "$repo" "$gitdir"
  fi
  origin_note="cloned"
fi

if [ ! -f "$gitdir/HEAD" ] && [ "$dry" -eq 1 ]; then
  # A dry run writes nothing, so a target with no clone has no commit of its own
  # to plan from. A local repository named as the source can be read instead;
  # a remote URL cannot, and that is reported rather than guessed at.
  if [ -f "$repo/HEAD" ]; then
    gdir=$repo
    say "$prog: planning from $repo — the target has no clone yet"
  else
    say "$prog: nothing to plan — $gitdir does not exist, and $(redact "$repo") is not a local git directory"
    say "$prog: done"
    exit 0
  fi
fi

if [ -n "$ref" ]; then
  commit=$(git_permitted rev-parse --verify --quiet "${ref}^{commit}" || true)
  [ -n "$commit" ] ||
    commit=$(git_permitted rev-parse --verify --quiet "origin/${ref}^{commit}" || true)
  [ -n "$commit" ] || die "no such ref in $(redact "$repo"): $ref"
else
  commit=$(git_permitted rev-parse --verify 'HEAD^{commit}')
fi
say "$prog: commit      ${commit:0:12} (${origin_note:-read})"

# ---- the tracked set ---------------------------------------------------------
# Repository surface, not configuration: these describe or check the repository
# itself, and writing them into a home directory would put a CI workflow and a
# licence where an application expects its own config.
surface=".github/ README.md CONTRIBUTING.md LICENSE install.sh"

# The user the target home belongs to, for the paths that name one without
# naming a home directory (a hyprpm cache path, a comment about which user a
# shim runs as). The repository's own user name needs no substitution.
[ -n "$user" ] || user=$(id -un)
case "$user" in
  tinoy | "") user="" ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
blob="$tmpdir/blob"
new="$tmpdir/new"

written=0
kept=0
skipped=0
replaced=0
skipped_list=""

# ---- one destination, one decision -------------------------------------------
# Identical content keeps the file, and keeps its mode right — an executable
# that lost its bit is not the committed file. An existing file that differs is
# named and left alone unless --force. A destination named as a link is
# compared and written as a link instead (link_target) and nothing else is
# stat-ed about it.
place() {
  local dest_path=$1 permissions=$2 source=$3 link_target=${4:-}
  local dest="$target/$dest_path"

  if [ -n "$link_target" ]; then
    if [ -L "$dest" ] && [ "$(readlink -- "$dest")" = "$link_target" ]; then
      step "  keep      $dest_path (link to $link_target)"
      kept=$((kept + 1))
      return 0
    fi
  elif [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$source" "$dest"; then
    if [ "$(stat -c '%a' -- "$dest")" != "$permissions" ]; then
      if [ "$dry" -eq 0 ]; then chmod "$permissions" "$dest"; fi
      step "  keep      $dest_path (mode set to $permissions)"
    else
      step "  keep      $dest_path"
    fi
    kept=$((kept + 1))
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$force" -eq 0 ]; then
      step "  skip      $dest_path (exists and differs — --force overwrites it)"
      skipped_list="$skipped_list $dest_path"
      skipped=$((skipped + 1))
      return 0
    fi
    if [ -d "$dest" ] && [ ! -L "$dest" ]; then
      die "$dest is a directory and the commit carries a file there — refusing to remove it"
    fi
    step "  replace   $dest_path (replaced md5 $(md5sum -- "$dest" | cut -d' ' -f1))"
    replaced=$((replaced + 1))
  else
    step "  write     $dest_path${link_target:+ (link to $link_target)}"
    written=$((written + 1))
  fi

  if [ "$dry" -eq 0 ]; then
    mkdir -p -- "$(dirname -- "$dest")"
    if [ -n "$link_target" ]; then
      rm -f -- "$dest"
      ln -s -- "$link_target" "$dest"
    else
      install -m "$permissions" -- "$source" "$dest"
    fi
  fi
}

while IFS= read -r -d '' entry; do
  meta=${entry%%$'\t'*}
  path=${entry#*$'\t'}
  mode=${meta%% *}
  sha=${meta##* }

  case "$path" in
    .github/* | README.md | CONTRIBUTING.md | LICENSE | install.sh) continue ;;
  esac

  permissions=${mode#100}

  # What this script would write, built from the cloned commit and never from
  # the running work tree.
  git_permitted cat-file blob "$sha" > "$blob"
  # .gitconfig is the author's identity, carried in the repository deliberately:
  # it is installed verbatim, because substituting a user name there would write
  # a different identity rather than this machine's spelling of the same one.
  if [ "$substitute" -eq 1 ] && [ "$mode" != "120000" ] && [ "$path" != ".gitconfig" ]; then
    expressions=(-e "s|/home/tinoy|$(esc "$target")|g")
    [ -z "$user" ] || expressions+=(-e "s|\\btinoy\\b|$(esc "$user")|g")
    if [ -n "$mac" ]; then
      expressions+=(-e "s|$mac_placeholder|$mac|g")
      expressions+=(-e "s|${mac_placeholder//:/_}|${mac//:/_}|g")
    fi
    LC_ALL=C sed "${expressions[@]}" "$blob" > "$new"
  else
    cp "$blob" "$new"
  fi

  template=${path%.in}
  if [ "$template" != "$path" ]; then
    # A tracked template ends in .in, which no tool reads. Its rendered twin —
    # the same name without the suffix — carries the values, so the template is
    # written as the commit holds it and the twin is written beside it.
    if [ "$substitute" -eq 1 ]; then
      place "$template" "$permissions" "$new"
    fi
    cp "$blob" "$new"
  fi

  if [ "$mode" = "120000" ]; then
    place "$path" "" "$new" "$(cat "$blob")"
  else
    place "$path" "$permissions" "$new"
  fi
done < <(git_permitted ls-tree -r -z "$commit")

# ---- the machine's own name --------------------------------------------------
# host-apply opens ~/.config/hosts/<hostname>, and the declaration is tracked
# under the placeholder name HOSTNAME. The machine's name is a link to that
# directory: the name belongs to the machine and cannot be tracked, while the
# declaration's content stays in the tracked set instead of in a copy beside it
# that would drift from the tracked one.
if [ "$substitute" -eq 1 ] && [ -n "$host" ]; then
  place ".config/hosts/$host" "" "" "HOSTNAME"
fi

# ---- what happened -----------------------------------------------------------
say ""
say "$prog: result      $written written, $kept unchanged, $skipped skipped, $replaced replaced"
say "$prog: repository-surface paths not installed: $surface"

if [ "$substitute" -eq 1 ]; then
  if [ -n "$mac" ]; then
    say "$prog: rendered    the local fragment with headset address $mac"
  else
    warn "headset address not given — the local fragment was not rendered, so no device volume is pinned"
  fi
  if [ -n "$host" ]; then
    say "$prog: linked      .config/hosts/$host -> HOSTNAME"
  else
    warn "no hostname — .config/hosts carries only the placeholder and host-apply will find no declaration for this machine"
  fi
  say "$prog: filled in   home path $target"
fi

if [ "$skipped" -gt 0 ]; then
  say "$prog: skipped (left exactly as they were):"
  for item in $skipped_list; do
    say "  $item"
  done
  say "$prog: re-run with --force to overwrite the files listed above"
fi

if [ "$dry" -eq 0 ] && [ -f "$target/.gitconfig" ] &&
  grep -q 'yo@t69.dev' "$target/.gitconfig"; then
  say "$prog: note        .gitconfig carries the repository author's git identity — change it if this is not that machine"
fi

say "$prog: done"
