#!/usr/bin/env bash
# atomic reword runner -- TEMPLATE for the `audit` reword handoff when history
# is signed by an interactive signer (Secretive / gpg-agent+pinentry / hardware
# key) that cannot be driven from a non-interactive tool. Copy this and the
# approved "$MSGDIR/<short-sha>.txt" message files to durable scratch space,
# fill every FILL block, then run the copy: `! bash <copy>`.
#
# Signedness is preserved by RE-SIGNING, not by copying old signatures: the
# interactive (merge-backend) rebase re-signs every replayed pick -- and every
# `exec git commit --amend` -- when commit.gpgsign=true, with the current
# key/format (confirmed, git 2.54). A rebase-level -S does NOT reach those amends,
# which is why this runner needs commit.gpgsign=true rather than -S. Expect up to
# P replayed + V reworded = P+V signer approvals. The rebase does NOT push; report
# back to the agent, which verifies (audit reword-handoff, verify step) and gives
# the push command only if the history was published.
set -uo pipefail

# ── FILL 1: repo root ────────────────────────────────────────────────────────
REPO="/abs/path/to/repo"
# ── FILL 2: durable scratch dir holding the per-commit message files ──────────
MSGDIR="/abs/path/to/scratchpad/reword"
# ── FILL 3: rebase base = <oldest-violating-sha>^  (or the literal "--root"
#            when the oldest violating commit is the repo's root commit) ────────
BASE="OLDEST_VIOLATING_SHA^"
# ── FILL 4: audited tip = the LITERAL commit SHA of HEAD at audit time (a SHA,
#            never HEAD or a branch name) + violating short SHAs, oldest first ──
EXPECT_HEAD="FILL_ME"
VIOL=("VIOLATING_SHA_1" "VIOLATING_SHA_2")
# ──────────────────────────────────────────────────────────────────────────────

[ "$EXPECT_HEAD" = "FILL_ME" ] && { echo "Template not filled in (EXPECT_HEAD). Aborting."; exit 1; }
case "$BASE" in *OLDEST_VIOLATING_SHA*) echo "Template not filled in (BASE). Aborting."; exit 1;; esac
cd "$REPO" || { echo "REPO does not exist: $REPO"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "REPO is not a git worktree: $REPO"; exit 1; }
dirty=$(git status --porcelain) || { echo "git status failed in $REPO"; exit 1; }
[ -z "$dirty" ] || { echo "Working tree not clean; aborting."; exit 1; }

# Drift guard: HEAD must still be the audited tip. EXPECT_HEAD must be a literal
# commit SHA (hex, full or abbreviated) -- never HEAD, a branch name, or a
# revision expression like HEAD~0 / HEAD^{}, all of which resolve to HEAD and
# make the check tautological. A hex-only form rejects every one of those.
case "$EXPECT_HEAD" in
  ""|*[!0-9a-fA-F]*) echo "EXPECT_HEAD ($EXPECT_HEAD) must be a literal commit SHA (hex), not a ref or revision expression."; exit 1;;
esac
expected_head=$(git rev-parse --verify -q "${EXPECT_HEAD}^{commit}") || { echo "EXPECT_HEAD does not resolve to a commit: $EXPECT_HEAD"; exit 1; }
actual_head=$(git rev-parse --verify -q HEAD) || { echo "cannot resolve HEAD"; exit 1; }
[ "$actual_head" = "$expected_head" ] || { echo "HEAD ($actual_head) is not the audited tip ($EXPECT_HEAD). Stop and re-run the audit."; exit 1; }

GITDIR=$(git rev-parse --absolute-git-dir) || { echo "cannot resolve git dir"; exit 1; }
TODO="$GITDIR/rebase-todo-plan"

# Resolve each violation to (full SHA, message file). Parallel arrays keep this
# working on stock macOS bash 3.2 -- no associative arrays.
VFULL=(); VFILE=()
for s in "${VIOL[@]}"; do
  f="$MSGDIR/$s.txt"; [ -f "$f" ] || { echo "missing message file $f"; exit 1; }
  full=$(git rev-parse --verify -q "${s}^{commit}") || { echo "violation does not resolve to a commit: $s"; exit 1; }
  VFULL+=("$full"); VFILE+=("$f")
done
msgfile_for() {  # print the message file for a full SHA; return 1 if none
  local h=$1 i
  for i in "${!VFULL[@]}"; do [ "${VFULL[$i]}" = "$h" ] && { printf '%s' "${VFILE[$i]}"; return 0; }; done
  return 1
}

if [ "$BASE" = "--root" ]; then RANGE=(--root); LOGRANGE=(HEAD)
else
  RANGE=("$BASE"); LOGRANGE=("${BASE}..HEAD")
  # BASE must resolve and be an ancestor of HEAD, else the replay range is not
  # the one the audit computed (wrong base, or the wrong branch checked out).
  base_commit=$(git rev-parse --verify -q "${BASE}^{commit}") || { echo "BASE does not resolve to a commit: $BASE"; exit 1; }
  git merge-base --is-ancestor "$base_commit" HEAD || { echo "BASE ($BASE) is not an ancestor of HEAD."; exit 1; }
fi

# Every violation must live in the replay range, else its `exec` is silently
# never emitted while the rebase still reports success. Validate before touching
# history. (awk reads the whole list -- no pipe, no SIGPIPE surprises.)
RANGE_SHAS=$(git rev-list "${LOGRANGE[@]}") || { echo "cannot enumerate replay range ${LOGRANGE[*]}"; exit 1; }
for full in "${VFULL[@]}"; do
  awk -v t="$full" '$0==t{f=1} END{exit !f}' <<<"$RANGE_SHAS" || { echo "violation $full is not in the replay range (${LOGRANGE[*]})."; exit 1; }
done

# BASE exactness: the oldest commit in the replay range must itself be a
# violation -- i.e. BASE == oldest-violation^ (non-root), or the root commit is
# the violation (--root). Guards a too-old BASE / wrong --root that would replay
# commits outside the audited range. (The membership loop above guards the
# too-new direction.) rev-list is newest-first, so the last line is the oldest.
oldest_in_range=${RANGE_SHAS##*$'\n'}
msgfile_for "$oldest_in_range" >/dev/null || { echo "BASE is too broad: the oldest replayed commit ($oldest_in_range) is not a violation. Set BASE to the oldest violation's parent (or --root only if the root commit is the violation)."; exit 1; }

# Signed range + commit.gpgsign off => this `rebase -i` would emit UNSIGNED
# replacements: it passes no -S, and neither rebase.gpgSign nor a rebase-level -S
# reaches the `exec git commit --amend` children (git 2.54). Refuse rather than
# silently unsign; ALLOW_UNSIGNED=1 opts in. awk reads the whole object so git
# never takes SIGPIPE (which pipefail would misread as unsigned). --type=bool
# normalizes yes/on/1 -> true.
range_signed=0
for h in $RANGE_SHAS; do
  git cat-file -p "$h" | awk '/^gpgsig/{f=1} END{exit !f}' && { range_signed=1; break; }
done
if [ "$range_signed" = 1 ] && [ "$(git config --type=bool --get commit.gpgsign 2>/dev/null || echo false)" != true ] && [ "${ALLOW_UNSIGNED:-0}" != 1 ]; then
  echo "Range is signed but commit.gpgsign is not true -- the rebase would drop signatures."
  echo "Fix: git config commit.gpgsign true   (or re-run with ALLOW_UNSIGNED=1 to accept unsigned)."
  exit 1
fi

: > "$TODO" || { echo "cannot write rebase todo: $TODO"; exit 1; }
US=$'\x1f'
while IFS="$US" read -r full short subject; do
  printf 'pick %s %s\n' "$short" "$subject" >> "$TODO"
  # `printf %q` shell-quotes the path so spaces/metacharacters survive the exec.
  mf=$(msgfile_for "$full") && printf 'exec git commit --amend -F %q\n' "$mf" >> "$TODO"
done < <(git log --reverse --format="%H${US}%h${US}%s" "${LOGRANGE[@]}")

# Verify the todo is complete BEFORE rebasing -- a missing pick line (e.g. a
# failed append) silently drops that commit from history. Every range commit
# must appear as a pick, and every distinct violation must map to exactly one
# amend exec.
pick_count=$(grep -c '^pick' "$TODO")
exec_count=$(grep -c '^exec' "$TODO")
range_count=$(git rev-list --count "${LOGRANGE[@]}")
distinct_viol=$(printf '%s\n' "${VFULL[@]}" | sort -u | grep -c .)
[ "$pick_count" -eq "$range_count" ] || { echo "todo incomplete: $pick_count picks for $range_count commits; aborting before rebase."; exit 1; }
[ "$exec_count" -eq "$distinct_viol" ] || { echo "todo has $exec_count amend execs for $distinct_viol violations; aborting before rebase."; exit 1; }

echo "Rewriting $pick_count commits, amending $exec_count..."
export PLAN="$TODO"
# --reschedule-failed-exec: if an amend fails (signer denial, hook), `git rebase
# --continue` RE-RUNS it. Without the flag git skips the failed exec, silently
# leaving that commit un-reworded while the rebase reports success.
GIT_SEQUENCE_EDITOR='cp "$PLAN"' git rebase -i --reschedule-failed-exec "${RANGE[@]}"
rc=$?
rm -f "$TODO"
if [ "$rc" -eq 0 ]; then
  signed=$(git log --format='%H' "${LOGRANGE[@]}" | while read -r h; do git cat-file -p "$h" | awk '/^gpgsig/{f=1} END{exit !f}' && echo x; done | grep -c x)
  if [ "$(git config --type=bool --get commit.gpgsign 2>/dev/null || echo false)" = true ]; then expect="expect all"; else expect="unsigned accepted via ALLOW_UNSIGNED"; fi
  echo
  echo "Done. Rewritten range signed: $signed of $(git rev-list --count "${LOGRANGE[@]}") commits ($expect)."
  echo "Re-scan the range for the fixed phrase(s) per /atomic audit (expect no hits),"
  echo "then report back to the agent -- it confirms and, only if the history was"
  echo "published, gives the 'git push --force-with-lease' command."
else
  echo "Rebase paused (rc=$rc). Could be a signer prompt, a merge conflict, or a"
  echo "failing hook. Run 'git status'; unlock the signer / resolve+stage conflicts /"
  echo "fix the hook, then: git rebase --continue   |   bail: git rebase --abort"
  echo "Keep $MSGDIR until the rebase completes or you abort."
fi
exit "$rc"
