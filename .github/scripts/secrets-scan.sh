#!/bin/sh
# secrets-scan — run gitleaks over the tracked files and every committed revision.
#
# The work tree is a home directory, so the scan is scoped to the repository
# rather than to a directory path: gitleaks is pointed at the git repository,
# which covers what was committed and what is committed now, and touches nothing
# that was never staged.
#
# `--redact` keeps a matched value out of the log, so a finding that does slip
# through is reported by rule, file and line without printing the secret itself.
#
# Usage: secrets-scan.sh [path-to-gitleaks]

set -eu

# The scanner is resolved BEFORE the repository is read. An absent scanner would
# otherwise fail as a bare `command not found` several lines down, which names
# neither the tool nor the fact that the scan never happened.
bin=${1:-gitleaks}
bin_missing() {
  echo "secrets-scan: $bin is not available — install gitleaks, or name one as the first" >&2
  echo "secrets-scan: argument; THE SCAN DID NOT RUN" >&2
  exit 2
}

case $bin in
*/*) [ -x "$bin" ] || bin_missing ;;
*) command -v -- "$bin" >/dev/null 2>&1 || bin_missing ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "secrets-scan: not inside a git work tree — export GIT_DIR and GIT_WORK_TREE" >&2
  exit 2
}

gitdir=$(git rev-parse --absolute-git-dir)

# A scan of a repository with no commit reads nothing, and its clean verdict
# would be a verdict on an empty set: require something to scan before scanning.
git rev-parse --verify HEAD >/dev/null 2>&1 || {
  echo "secrets-scan: $gitdir has no commit to scan — nothing was read" >&2
  exit 2
}

# Exit status is the verdict, and it is read rather than passed through
# unexamined: gitleaks returns 1 when it finds a leak — the answer this job
# exists for — while any other non-zero status is the scanner failing, which must
# not be left to read as a clean scan.
set +e
"$bin" git "$gitdir" --redact --no-banner --log-level=warn
scan_status=$?
set -e

case $scan_status in
0) ;;
1) exit 1 ;;
*)
  echo "secrets-scan: $bin exited $scan_status — the scan did NOT complete" >&2
  exit "$scan_status"
  ;;
esac

echo "secrets-scan: no leaks reported in $gitdir"
