#!/bin/sh
# installer-smoke — exercise the installer against a scratch home directory.
#
# The installer is the repository's front door, so the promises it makes are
# checked here rather than assumed:
#
#   - a first run writes the tracked configuration and fills in the per-machine
#     values: the hostname and the home path
#   - both values are derived from the machine the installer runs on: the
#     hostname from `hostnamectl --static`, the user name from the target home,
#     and neither is asked for
#   - a second run writes nothing and changes nothing, byte for byte
#   - a file that already exists and differs is named and left alone
#   - running as root is refused
#   - the repository's root forwarder exists, is executable, and reaches the
#     installer it names
#
# Nothing is installed outside a scratch directory under ${TMPDIR:-/tmp}, and the
# repository is read as the clone source, never written. The one run that reads a
# home outside that scratch directory is the /home/<name> derivation check, which
# is a --dry-run against $HOME and writes nothing.
#
# Usage: installer-smoke.sh [checkout]

set -eu

# A relative path named as the checkout would be resolved against an inherited
# CDPATH otherwise.
unset CDPATH

src=${1:-.}
src=$(cd -- "$src" && pwd)
installer="$src/.github/scripts/dotfiles-install.sh"
[ -f "$installer" ] || {
  echo "installer-smoke: no installer at $installer" >&2
  exit 2
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home="$work/home"

status=0
problem() {
  printf 'installer-smoke: %s\n' "$*" >&2
  status=1
}

# MD5 of the scratch home's contents, modes and symlink targets, with the
# installer's own clone left out: the clone is not part of what it installs.
tree_digest() {
  {
    find "$home" -mindepth 1 -not -path "$home/.dotfiles.git*" -type f -printf '%m %p\n' |
      LC_ALL=C sort
    find "$home" -mindepth 1 -not -path "$home/.dotfiles.git*" -type l -printf '%p -> %l\n' |
      LC_ALL=C sort
    find "$home" -mindepth 1 -not -path "$home/.dotfiles.git*" -type f |
      LC_ALL=C sort | xargs -r md5sum
  } | md5sum | cut -d' ' -f1
}

installed_count() {
  find "$home" -mindepth 1 -not -path "$home/.dotfiles.git*" ! -type d | wc -l | tr -d ' '
}

result_counts() {
  sed -n 's/.*result *\([0-9]*\) written, \([0-9]*\) unchanged, \([0-9]*\) skipped, \([0-9]*\) replaced.*/\1 \2 \3 \4/p' "$1"
}

count_field() { printf '%s' "$1" | cut -d' ' -f"$2"; }

# A path is quoted before it is handed to a terminal-owning helper as one command
# string, so the helper re-reads it as the single argument it was.
esc_dq() { printf '%s' "$1" | sed -e 's/[\\"]/\\&/g' -e 's/[$`]/\\&/g'; }

host="smoke-host"
mkdir -p "$home"

# ---- the root forwarder ------------------------------------------------------
forwarder="$src/install.sh"
[ -f "$forwarder" ] || problem "no ./install.sh at the repository root"
[ -x "$forwarder" ] || problem "./install.sh is not executable"
if [ -x "$forwarder" ]; then
  "$forwarder" --help > "$work/forwarder.log" 2>&1 || problem "./install.sh --help failed"
  grep -q 'Usage: dotfiles-install.sh' "$work/forwarder.log" ||
    problem "./install.sh did not reach the installer"
fi

# ---- first run ---------------------------------------------------------------
"$installer" "$home" --repo "$src" --hostname "$host" \
  --quiet > "$work/first.log" 2>&1 || problem "the first install failed"

counts=$(result_counts "$work/first.log")
[ -n "$counts" ] || problem "the first run reported no result line"
written=$(count_field "$counts" 1)
on_disk=$(installed_count)
[ "$written" = "$on_disk" ] ||
  problem "the first run reported $written path(s) written and $on_disk arrived on disk"
[ "${written:-0}" -gt 100 ] || problem "the first run wrote only $written path(s)"

# The value it fills in: this machine's name is a link to the tracked
# declaration. No tracked wireplumber fragment may name a device — each device's
# volume is WirePlumber's own state, so a fragment carrying a real address would
# pin one machine's hardware into the tracked set. Both spellings WirePlumber
# uses for an address (colon in a device name, underscore in a node name) are
# read, and the placeholder spelling the tracked set uses is accepted.
fragdir="$home/.config/wireplumber/wireplumber.conf.d"
[ -d "$fragdir" ] || problem "the wireplumber drop-in directory was not installed"
grep -rEh -o -e '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' -e '([0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}' "$fragdir" |
  grep -qv -e '^AA:BB:CC:DD:EE:FF$' -e '^AA_BB_CC_DD_EE_FF$' &&
  problem "a tracked wireplumber fragment names a device, so it is not machine-independent"

[ -L "$home/.config/hosts/$host" ] ||
  problem "this machine's name is not a link to the tracked host declaration"
[ "$(readlink -- "$home/.config/hosts/$host")" = "HOSTNAME" ] ||
  problem "this machine's name does not link to the tracked HOSTNAME declaration"
[ -f "$home/.config/hosts/$host/host.conf" ] ||
  problem "the host declaration is not readable under this machine's own name"
[ -d "$home/.config/hosts/HOSTNAME" ] ||
  problem "the tracked HOSTNAME declaration directory is not installed"
[ -e "$home/install.sh" ] && problem "the root forwarder was installed into the home"

grep -q "$home" "$home/.zshenv" || problem "the home path was not substituted into .zshenv"
grep -rq '/home/tinoy' "$home/.config" "$home/.local" 2>/dev/null &&
  problem "a tracked file still names the repository author's home path"

[ -x "$home/.local/bin/dotfiles" ] || problem ".local/bin/dotfiles is not executable after the install"
[ -L "$home/.local/bin/pi" ] || problem ".local/bin/pi is not a symlink after the install"

# ---- second run: idempotent --------------------------------------------------
before=$(tree_digest)
"$installer" "$home" --repo "$src" --hostname "$host" \
  --quiet > "$work/second.log" 2>&1 || problem "the second install failed"
after=$(tree_digest)

second_written=$(count_field "$(result_counts "$work/second.log")" 1)
second_kept=$(count_field "$(result_counts "$work/second.log")" 2)
[ "$second_written" = "0" ] ||
  problem "the second run wrote $second_written path(s) instead of none"
[ "$second_kept" = "$written" ] ||
  problem "the second run reported $second_kept unchanged path(s), expected $written"
[ "$before" = "$after" ] || problem "the scratch home changed between two identical runs"

# ---- the two derived values --------------------------------------------------
# Neither value is asked for: the hostname is the machine's own name and the user
# name is the owner of the target home. A scratch home sits outside /home, so for
# it the derived user is whoever runs this script — which is what makes the
# --user disagreement below checkable, and what makes the /home/<name> branch
# reachable only where this machine has such a home (see below).
me=$(id -un)
detected=$(hostnamectl --static 2>/dev/null || true)
[ -n "$detected" ] || detected=$(hostname -s 2>/dev/null || true)
[ -n "$detected" ] || problem "this host reports no name to derive"

"$installer" "$home" --repo "$src" --dry-run > "$work/derived.log" 2>&1 ||
  problem "the dry run with neither --hostname nor --user failed"
grep -q "linked      .config/hosts/$detected -> HOSTNAME" "$work/derived.log" ||
  problem "the dry run did not link the machine's own detected name: $detected"
grep -q 'disagrees' "$work/derived.log" &&
  problem "the run without --user reported a disagreement with the derived user"

"$installer" "$home" --repo "$src" --dry-run --user smoke-other > "$work/other.log" 2>&1 ||
  problem "the dry run with --user smoke-other failed"
grep -q "disagrees with the user $home names ($me)" "$work/other.log" ||
  problem "--user smoke-other did not report its disagreement with the derived user ($me)"

# The prompt is gone: with a terminal on stdin the installer reads nothing and
# waits for nothing. `script` supplies that terminal without a session to hang in.
if command -v script >/dev/null 2>&1; then
  ptycmd="\"$(esc_dq "$installer")\" \"$(esc_dq "$home")\" --repo \"$(esc_dq "$src")\" --dry-run"
  script -qec "$ptycmd" /dev/null < /dev/null > "$work/pty.log" 2>&1 ||
    problem "the installer failed with a terminal on stdin"
  grep -qi 'hostname for the host declaration' "$work/pty.log" &&
    problem "the installer still prompts for the hostname"
else
  echo "installer-smoke: SKIPPED the hostname-prompt check — this host has no script(1)" >&2
  echo "installer-smoke: to give the installer a terminal on stdin" >&2
fi

# A second scratch home, installed with neither flag: what it links is the
# machine's own detected name, so the hostname is derived rather than supplied.
home2="$work/home2"
mkdir -p "$home2"
"$installer" "$home2" --repo "$src" --quiet > "$work/noflags.log" 2>&1 ||
  problem "the install with neither --hostname nor --user failed"
[ -L "$home2/.config/hosts/$detected" ] ||
  problem "the install linked no declaration for the derived hostname $detected"

# The /home/<name> branch: the target home's own name is the derived user. It
# cannot be reached from a scratch home — that would take a directory under /home,
# which this test may not create — so it runs only where this machine already has
# such a home with the repository's clone beside it, and is announced as skipped
# everywhere else.
if [ "$(dirname -- "$HOME")" = "/home" ] && [ -f "$HOME/.dotfiles.git/HEAD" ]; then
  timeout 300 "$installer" "$HOME" --repo "$HOME/.dotfiles.git" --dry-run \
    --user smoke-other > "$work/home-branch.log" 2>&1 ||
    problem "the read-only dry run against \$HOME failed"
  grep -q "disagrees with the user $HOME names (${HOME#/home/})" "$work/home-branch.log" ||
    problem "the /home/<name> branch did not derive ${HOME#/home/} from $HOME"
else
  echo "installer-smoke: SKIPPED the /home/<name> derivation check — it needs a target" >&2
  echo "installer-smoke: home directly under /home with the repository's clone beside it" >&2
fi

# ---- refusal: an existing file that differs ----------------------------------
printf '\n# a distribution default, not the repository content\n' >> "$home/.zshrc"
marker="a distribution default"
keep=$(md5sum < "$home/.zshrc")

"$installer" "$home" --repo "$src" --hostname "$host" \
  --quiet > "$work/third.log" 2>&1 || problem "the run against a differing file failed"

grep -q "\.zshrc" "$work/third.log" || problem "the differing file was not named in the summary"
grep -q "1 skipped" "$work/third.log" || problem "the differing file was not counted as skipped"
grep -q "$marker" "$home/.zshrc" || problem "the differing file was overwritten without --force"
[ "$keep" = "$(md5sum < "$home/.zshrc")" ] || problem "the differing file changed without --force"

# ---- refusal: root -----------------------------------------------------------
# A user namespace is enough to answer `id -u` with 0 without becoming root. When
# the host refuses to create one, the check is announced as skipped rather than
# passed over in silence: a run that cannot exercise the refusal has not verified
# it, and the summary below must not read as if it had.
if command -v unshare >/dev/null 2>&1 && [ "$(unshare -r id -u 2>/dev/null || echo x)" = "0" ]; then
  if unshare -r "$installer" "$home" --repo "$src" --dry-run > "$work/root.log" 2>&1; then
    problem "running as root was not refused"
  elif ! grep -q 'as root' "$work/root.log"; then
    problem "running as root failed for a reason other than the root refusal"
  fi
else
  echo "installer-smoke: SKIPPED the root refusal check — this host has no unshare that" >&2
  echo "installer-smoke: maps a user namespace to uid 0" >&2
fi

[ "$status" -eq 0 ] || exit 1

printf 'installer-smoke: %s path(s) installed, %s unchanged on a second run, refusal path names its skip\n' \
  "$written" "$second_kept"
