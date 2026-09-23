#!/bin/sh
# installer-smoke — exercise the installer against a scratch home directory.
#
# The installer is the repository's front door, so the promises it makes are
# checked here rather than assumed:
#
#   - a first run writes the tracked configuration and fills in the per-machine
#     values (the headset address, the hostname, the home path)
#   - a second run writes nothing and changes nothing, byte for byte
#   - a file that already exists and differs is named and left alone
#   - running as root is refused
#
# Nothing is installed outside a scratch directory under ${TMPDIR:-/tmp}, and the
# repository is read as the clone source, never written.
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

mac="11:22:33:44:55:66"
host="smoke-host"
mkdir -p "$home"

# ---- first run ---------------------------------------------------------------
"$installer" "$home" --repo "$src" --hostname "$host" --bluetooth-address "$mac" \
  --quiet > "$work/first.log" 2>&1 || problem "the first install failed"

counts=$(result_counts "$work/first.log")
[ -n "$counts" ] || problem "the first run reported no result line"
written=$(count_field "$counts" 1)
on_disk=$(installed_count)
[ "$written" = "$on_disk" ] ||
  problem "the first run reported $written path(s) written and $on_disk arrived on disk"
[ "${written:-0}" -gt 100 ] || problem "the first run wrote only $written path(s)"

# The values it fills in.
bt="$home/.config/wireplumber/wireplumber.conf.d/50-bt-default.conf"
grep -q "$mac" "$bt" || problem "the headset address did not reach 50-bt-default.conf"
grep -q "$(printf '%s' "$mac" | tr ':' '_')" "$bt" ||
  problem "the underscore form of the headset address did not reach the wireplumber matchers"
grep -q 'AA:BB:CC:DD:EE:FF' "$bt" && problem "the headset placeholder survived a filled-in install"

[ -f "$home/.config/hosts/$host/host.conf" ] ||
  problem "the host declaration was not renamed to $host"
[ -d "$home/.config/hosts/HOSTNAME" ] && problem "the HOSTNAME placeholder directory is still present"

grep -q "$home" "$home/.zshenv" || problem "the home path was not substituted into .zshenv"
grep -rq '/home/tinoy' "$home/.config" "$home/.local" 2>/dev/null &&
  problem "a tracked file still names the repository author's home path"

[ -x "$home/.local/bin/dotfiles" ] || problem ".local/bin/dotfiles is not executable after the install"
[ -L "$home/.local/bin/pi" ] || problem ".local/bin/pi is not a symlink after the install"
[ -L "$home/.config/systemd/user/swaync.service" ] ||
  problem "the swaync mask is not a symlink after the install"

# ---- second run: idempotent --------------------------------------------------
before=$(tree_digest)
"$installer" "$home" --repo "$src" --hostname "$host" --bluetooth-address "$mac" \
  --quiet > "$work/second.log" 2>&1 || problem "the second install failed"
after=$(tree_digest)

second_written=$(count_field "$(result_counts "$work/second.log")" 1)
second_kept=$(count_field "$(result_counts "$work/second.log")" 2)
[ "$second_written" = "0" ] ||
  problem "the second run wrote $second_written path(s) instead of none"
[ "$second_kept" = "$written" ] ||
  problem "the second run reported $second_kept unchanged path(s), expected $written"
[ "$before" = "$after" ] || problem "the scratch home changed between two identical runs"

# ---- refusal: an existing file that differs ----------------------------------
printf '\n# a distribution default, not the repository content\n' >> "$home/.zshrc"
marker="a distribution default"
keep=$(md5sum < "$home/.zshrc")

"$installer" "$home" --repo "$src" --hostname "$host" --bluetooth-address "$mac" \
  --quiet > "$work/third.log" 2>&1 || problem "the run against a differing file failed"

grep -q "\.zshrc" "$work/third.log" || problem "the differing file was not named in the summary"
grep -q "1 skipped" "$work/third.log" || problem "the differing file was not counted as skipped"
grep -q "$marker" "$home/.zshrc" || problem "the differing file was overwritten without --force"
[ "$keep" = "$(md5sum < "$home/.zshrc")" ] || problem "the differing file changed without --force"

# ---- refusal: root -----------------------------------------------------------
# A user namespace is enough to answer `id -u` with 0 without becoming root; when
# the host refuses to create one, this check is skipped rather than faked.
if command -v unshare >/dev/null 2>&1 && [ "$(unshare -r id -u 2>/dev/null || echo x)" = "0" ]; then
  if unshare -r "$installer" "$home" --repo "$src" --dry-run > "$work/root.log" 2>&1; then
    problem "running as root was not refused"
  elif ! grep -q 'as root' "$work/root.log"; then
    problem "running as root failed for a reason other than the root refusal"
  fi
fi

[ "$status" -eq 0 ] || exit 1

printf 'installer-smoke: %s path(s) installed, %s unchanged on a second run, refusal path names its skip\n' \
  "$written" "$second_kept"
