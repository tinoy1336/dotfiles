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

bin=${1:-gitleaks}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "secrets-scan: not inside a git work tree — export GIT_DIR and GIT_WORK_TREE" >&2
  exit 2
}

gitdir=$(git rev-parse --absolute-git-dir)

# Exit status is the verdict: gitleaks returns 1 when it finds a leak and
# `set -e` propagates that to the caller.
"$bin" git "$gitdir" --redact --no-banner --log-level=warn

echo "secrets-scan: no leaks reported in $gitdir"
