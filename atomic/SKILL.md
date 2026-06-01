---
name: atomic
description: >-
  Split working tree changes into logical atomic commits, generate commit
  messages, plan interactive rebases, and cherry-pick safely. Subcommands:
  commit (default), generate, rebase, cherry-pick, fixup.
  All subcommands support --dry-run for preview without execution.
  TRIGGER when: user has uncommitted changes to organize, wants to split
  a large diff into atomic commits, needs rebase/cherry-pick guidance, or
  invokes /atomic.
  DO NOT TRIGGER when: user wants a single simple one-shot commit with no splitting.
allowed-tools:
  - Bash(git *)
  - Bash(mktemp *)
  - Bash(rm *)
  - Edit
  - Write
  - Read
  - Grep
  - Glob
---

# Atomic -- Git Workflow for Atomic Changes

Split messy diffs into clean, logical, independently reviewable commits.

## Subcommands

| Subcommand    | Purpose                                                  |
|---------------|----------------------------------------------------------|
| `commit`      | Default. Analyze changes, group into atomic commits, execute |
| `generate`    | Generate a conventional commit message for currently staged files |
| `rebase`      | Plan and execute interactive rebase from a base commit   |
| `cherry-pick` | Analyze and safely cherry-pick commits or ranges         |
| `fixup`       | Create fixup commits targeting existing commits          |

Usage: `/atomic [subcommand] [args]`

Pass `--dry-run` to any subcommand to preview without executing. In dry-run
mode, run only read-only inspection (e.g. `status`, `diff`, `log`, `show`) and
present the plan or assessment, then **stop before any command that mutates the
repo, index, or commits** (`git add`, `commit`, `rebase`, `cherry-pick`,
`checkout`, `--fixup`). `generate` never commits, so `--dry-run` is a no-op there.

---

## Subcommand: `commit` (default)

Split all uncommitted changes into atomic conventional commits.

### Workflow

#### 1. Pre-flight

Gather state -- run these in parallel:

```bash
git status --short
git diff --stat                    # unstaged summary
git diff --cached --stat           # staged summary
git log --oneline -5               # recent commits for style context
```

**Untracked files**: `git diff` does not show untracked files. Check
`git status --short` for `??` entries. For each untracked file, read its
contents to classify it into a group. Stage untracked files with
`git add <file>` (they are always whole-file, no hunk splitting needed).

Read diffs **per group** as you analyze (not all upfront). For large changesets
(20+ files), reading everything into context at once will degrade quality.
Use `--stat` to plan groups, then `git diff -U3 -- <file1> <file2>` for the
files in each group. The diff with 3 lines of context is usually sufficient
for writing commit messages -- avoid reading full files unless needed.

#### 2. Respect staged intent

If the user has already staged files (`git diff --cached` is non-empty), treat
staged changes as the scope for the **first** commit group. Ask before
re-scoping.

#### 3. Analyze and group

Read through all changes and classify into logical groups. Each group is one
atomic commit representing a single concern.

**Grouping signals:**
- Same feature or bug fix across multiple files = one group
- Test + implementation for the same feature = one group
- Unrelated formatting/lint fix = separate group
- Config change unrelated to feature = separate group
- Documentation update = separate group

**Rename/move rule**: When a rename is in progress, always commit both
halves together. Splitting them destroys git's rename detection. A rename
appears in `git status --short` as either a single `R` line (staged via
`git mv`), or as paired ` D` + `??` for the same logical file (unstaged),
or paired ` D` + `A ` (staged piecewise).

**Split signals** (changes in a single file that belong to different groups):
- Multiple unrelated functions changed
- Mixed concerns (e.g., bug fix + refactor in same file)
- Import additions for different features

When a file contains changes for multiple groups, pick a strategy from the
decision table at the top of [Hunk-Level Staging](#hunk-level-staging) — the
3+ groups case routes to save-and-replay, not partial-patch staging.

#### 4. Order commits

Default ordering by risk (lowest risk to codebase first):

1. `ci` -- CI/CD pipeline changes (no runtime impact)
2. `docs` -- documentation only
3. `test` -- test additions/changes
4. `chore` -- maintenance, config, dependencies
5. `fix` -- bug fixes
6. `refactor` -- code restructuring
7. `feat` -- new features
8. `perf` -- performance improvements (touches hot paths)

Override this ordering when dependency requires it (e.g., a schema migration
must come before the code that uses it).

#### 5. Present plan

Display the plan before executing:

```
Atomic commit plan (N commits):

  1. fix(auth): handle expired token refresh
     Files: src/auth/token.ts, src/auth/middleware.ts
     Hunks: src/auth/client.ts (lines 45-62)

  2. feat(search): add fuzzy matching
     Files: src/search/fuzzy.ts, src/search/index.ts, tests/search/fuzzy.test.ts

  3. chore: update eslint config
     Files: .eslintrc.js
```

**Wait for user approval before executing.** The user may reorder, merge,
split, or rename groups.

#### 6. Execute

If the plan from step 5 includes any file in **3+ commit groups**, run
the save-and-replay pre-flight (see "Multi-commit files" below) before
staging the first commit. Doing it mid-execution after a commit has
already shifted context lines is painful and may require a
`git apply --3way` recovery step.

For each commit group, sequentially:

1. **Stage files**: `git add <file1> <file2> ...` for whole-file changes
2. **Stage hunks**: Use hunk-level staging for partial-file changes
3. **Commit**: `git commit -m "<type>[scope]: <description>"`
4. **Verify**: `git status --short` to confirm expected state

Each commit consumes the staged changes, so subsequent groups stage from the
remaining unstaged working tree. No index reset needed between groups.

**Minimize tool calls**: Reuse pre-flight state from step 1 throughout. Do not
re-run `git log`, `git diff --stat`, or `git status` between groups unless
verifying after a commit (step 4). Read full diffs once per file, not per group.

#### 7. Summary

After all commits:

```bash
git log --oneline -N    # show the N new commits
```

Surface any remaining unstaged/untracked changes.

### Hunk-Level Staging

Strategy when a file spans multiple commit groups:

| Situation                                         | Strategy                                  |
|---------------------------------------------------|-------------------------------------------|
| Single file, 2 cleanly-separated groups           | `git apply --cached` (this section)       |
| `git apply --cached` rejects due to context drift | retry with `git apply --cached --3way`    |
| Single file in 3+ groups                          | save-and-replay (next section)            |
| Hunks don't cleanly separate concerns             | stage whole file in dominant group        |

Filtered-patch staging (the first row above):

```bash
PATCH=$(mktemp)

# Extract the full diff for the file
git diff -- <file> > "$PATCH"

# Edit the patch to include only the desired hunks:
# - Keep the diff header (first 4 lines: diff, index, ---, +++)
# - Keep only the @@ hunk headers and content for target hunks
# - Remove unwanted hunks entirely

# Apply the filtered patch to the index
git apply --cached "$PATCH"
rm "$PATCH"
```

For already-staged files needing hunk splitting, unstage first — re-applying a
subset onto an index that already holds the full change fails. Snapshot the
staged diff, unstage, then apply only the wanted hunks:

```bash
PATCH=$(mktemp)
git diff --cached -- <file> > "$PATCH"   # snapshot the staged hunks
git reset HEAD -- <file>                 # unstage; working tree unchanged
# Edit "$PATCH" to keep only the hunks for THIS group, then:
git apply --cached "$PATCH"
rm "$PATCH"
```

**Important:**
- After applying a partial patch, verify with `git diff --cached -- <file>`
  that only the intended changes are staged
- If `git apply` fails (malformed patch), unstage with `git reset HEAD -- <file>`
  and retry. Common causes: corrupted hunk header line counts, missing newline
  at end of patch, or wrong `index` line. When in doubt, fall back to staging
  the whole file in one group and noting the split was not possible
- **`git apply --3way` for context drift** — when earlier commits in the
  series shift line numbers, the saved patch's context lines no longer
  match HEAD verbatim and plain `git apply` rejects it. `--3way` falls
  back to git's merge logic and applies cleanly when the conflicting
  hunks were already absorbed into earlier commits. Use it as the first
  retry before reaching for `Edit`-based replay.
- For files where hunk boundaries don't cleanly separate concerns, prefer
  staging the whole file in the group where the majority of changes belong

### Multi-commit files (save-and-replay)

When a single file appears in **three or more** commit groups, serial
`git apply --cached` on partial patches gets brittle fast — every
intermediate commit shifts context lines, and you'd need to recompute
hunk headers after each one. The reliable workflow:

```bash
# Pre-flight: save full diffs of every multi-commit file, then reset
# them to HEAD so the working tree is clean.
PATCH_DIR=$(mktemp -d -t atomic-patches.XXXXXX)
MULTI_COMMIT_FILES=(path/to/file-a path/to/file-b)
for f in "${MULTI_COMMIT_FILES[@]}"; do
  # Diff against HEAD so staged AND unstaged hunks are captured; slug the path
  # so files that share a basename don't overwrite each other's patch.
  git diff --binary HEAD -- "$f" > "$PATCH_DIR/${f//\//__}.patch"
done
git checkout HEAD -- "${MULTI_COMMIT_FILES[@]}"

# For each commit group that touches one of these files:
# 1. Apply just the changes needed for THIS commit, via the Edit tool
#    (or sed/awk for mechanical edits like a global rename).
# 2. Stage the file: git add <file>
# 3. Commit the group.
# 4. After ALL groups have committed, sanity-check that the per-commit
#    Edits add up to the original working-tree state:
#       git apply --3way "$PATCH_DIR/${f//\//__}.patch"
#       git diff --exit-code -- "$f"    # no diff means patch was absorbed
#    A clean path-scoped diff means HEAD matches the original working-tree
#    state for that file. If the diff shows changes or `--3way` produces
#    conflict markers, the Edits drifted from intent. Reset with
#    `git checkout HEAD -- <file>` and investigate before pushing.

# Cleanup
rm -rf "$PATCH_DIR"
```

**Why this beats partial-patch staging at scale:**
- The `Edit` tool tracks file state and won't let you make stale edits
- No need to recompute hunk header line counts between commits
- Each commit's diff is built fresh against current HEAD, no drift
- The final `--3way` apply is a structural sanity check that all the
  per-commit Edits add up to the original working-tree state

**When NOT to use this:** single file split into 2 commits where hunks
are cleanly separated — the simpler `git apply --cached` workflow above
is faster.

---

## Subcommand: `generate`

Generate a conventional commit message for currently staged changes.

### Workflow

1. Run `git diff --cached --stat` and `git diff --cached` to see staged changes
2. Analyze the diff for:
   - What changed (the "what")
   - Why it changed (the "why" -- infer from context, related tests, commit history)
   - The appropriate conventional commit type
   - A scope if the changes are localized to a module/component
3. **Atomicity check**: Before generating, check if staged changes span
   multiple concerns (unrelated directories/modules, mixed types like fix +
   feat). If so, warn that this isn't atomic and suggest `/atomic commit`
4. Print the message; copy it to the clipboard if a tool is available
   (`pbcopy` on macOS, `wl-copy` or `xclip` on Linux), otherwise skip silently
5. Do NOT commit -- the user will use a separate command for that

Message format:

```
<type>[(scope)]: <description>

[optional body -- only if the "why" isn't obvious from the description]

[optional footer -- BREAKING CHANGE, references, etc.]
```

**Rules:**
- Description is imperative mood, lowercase, no period
- Under 72 characters for the subject line
- Body wraps at 72 characters

### Conventional Commit Types

| Type       | When                                  | SemVer  |
|------------|---------------------------------------|---------|
| `feat`     | New feature for the user              | MINOR   |
| `fix`      | Bug fix                               | PATCH   |
| `docs`     | Documentation only                    | --      |
| `test`     | Adding or fixing tests                | --      |
| `refactor` | Neither fix nor feature               | --      |
| `perf`     | Performance improvement               | PATCH   |
| `chore`    | Maintenance, deps, config             | --      |
| `ci`       | CI/CD changes                         | --      |
| `build`    | Build system changes                  | --      |
| `revert`   | Reverts a previous commit             | varies  |

Breaking changes: append `!` after type/scope (e.g., `feat!: remove v1 API`)
or add `BREAKING CHANGE:` footer.

### Commit and PR Message Hygiene

Commit messages and PR descriptions are read by people who weren't in
the conversation when the change happened. Anything that names a
session-internal artifact becomes noise at best, a dead pointer at
worst. The reader has the diff, the surrounding commits, and the
repo's documentation — nothing else. Write the "why" using only those.

**Heuristic:** if a phrase only makes sense to someone who
participated in the conversation that produced this change, it is
session-internal and must be cut. A new contributor — or your future
self six months from now — should read the message and know how to
act on it without you in the room.

**Examples of forbidden phrasing (not exhaustive):**

- "the 2026-05-15 audit confirmed…", "after auditing…", "audit run
  showed…" — when the audit is an ephemeral session activity, not a
  named feature/log/script in the repo
- "previous session", "earlier in this thread", "as discussed earlier"
- "Round 1 findings", "round 2 caught", "the review pass said",
  "fresh-eyes pass"
- "the outside review flagged", "the external reviewer said"
- "the scratch notes said", "per the final-plan note",
  "the design doc we wrote earlier"

**Not forbidden** when they describe something in the repo: `audit`
in a commit about audit log code, `R1`/`R2` for release labels or a
Cloudflare R2 bucket, dates that appear in filenames already in the
diff (migrations, snapshot files). The trigger is *session reference*,
not the literal word.

**At draft time:** read every commit message subject AND body against
the heuristic above before executing the commit. If a sentence
explains *why* the change happened by pointing to an ephemeral
activity, rewrite it to state the direct fact ("X is unused," "this
fixes Y bug," "Z was racy under concurrent writes").

---

## Subcommand: `rebase`

Plan and guide interactive rebase of the current branch from a base commit.

### Usage

```
/atomic rebase [base]           # e.g., HEAD~5, main (default: upstream)
```

### Workflow

1. **Resolve base**: Treat the argument as the interactive rebase base. If no
   base is given, use the branch upstream when available. Do not accept
   two-dot or three-dot ranges (`main..feature`, `main...feature`) for
   execution; ask for the base commit or branch instead.
2. **Analyze commits to replay**: `git log --stat --reverse <base>..HEAD` lists
   exactly the commits that `git rebase -i <base>` will place in the todo file.
   Only read full diffs (`git show <sha> -- <file>`) for commits that need
   deeper inspection (split candidates, reword targets)
3. **Propose rebase plan**: For each commit, suggest one of:
   - `pick` -- keep as-is
   - `squash`/`fixup` -- combine with adjacent commit
   - `reword` -- fix the commit message
   - `split` -- commit has multiple concerns (flag for splitting)
   - `reorder` -- move to better position in sequence

   When any `fixup!` commits are present among the commits to replay, recommend
   `--autosquash` instead of a hand-written plan.
4. **Present plan** with rationale for each action
5. **Execute**: Bypass the interactive editor by writing the rebase-todo
   to a file and injecting it via `GIT_SEQUENCE_EDITOR`. Create the plan
   file with the **Write tool** (not a shell heredoc) at
   `.git/rebase-todo-plan` — it lives under `.git/`, so it is never
   committed and is overwritten on reuse:

   ```
   pick abc1234 feat: add search
   squash def5678 fix: search typo
   pick 789abcd refactor: extract utils
   ```

   Then run the rebase, injecting that file as the sequence editor:

   ```bash
   # The trailing `#` comments out the filename arg git appends to the editor command.
   GIT_SEQUENCE_EDITOR='cp .git/rebase-todo-plan "$1"; #' git rebase -i <base>
   rebase_status=$?
   rm -f .git/rebase-todo-plan
   exit "$rebase_status"
   ```
   - For simple autosquash: `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`
   - For splitting: mark the commit as `edit` in the plan. When rebase pauses,
     run `git reset HEAD~1` then use `/atomic commit` to re-commit atomically
   - If the plan includes `reword`, set `GIT_EDITOR` (the commit-message
     editor) for that step, or let rebase pause and run
     `git commit --amend -m "new message"` followed by `git rebase --continue`.
     `GIT_SEQUENCE_EDITOR` only handles the rebase-todo file, not commit messages

### Safety

- Always check for uncommitted changes before rebase. If present, ask the
  user before stashing -- `git stash` mutates state and may conflict with
  staged intent. Never stash silently
- Show `git log --oneline --graph` before and after
- If rebase conflicts, resolve using the Conflict Resolution workflow below
- Never rebase published commits without explicit user confirmation

---

## Subcommand: `cherry-pick`

Analyze and safely cherry-pick commits or ranges.

### Usage

```
/atomic cherry-pick <ref>                    # single commit
/atomic cherry-pick <start>..<end>           # range (inclusive)
```

### Workflow

1. **Analyze target commits**:
   ```bash
   # Inclusive range: use <start>^..<end> so the start commit isn't dropped
   # (plain A..B excludes A). If <start> is the repo's root commit it has no
   # parent — drop the ^ and use <start>..<end>. Single commit: git show --stat <ref>.
   git log --stat <start>^..<end>    # summary + file stats in one call
   ```
   Only read full diffs (`git show <sha>`) for commits that need deeper
   dependency analysis or partial cherry-pick evaluation.
2. **Dependency check**: For each commit, check if it depends on changes from
   commits NOT in the cherry-pick set:
   - Files modified that don't exist on the current branch
   - Functions/types referenced that aren't defined on current branch
   - Schema or migration dependencies
3. **Present assessment**:
   - Safe to cherry-pick (self-contained)
   - Needs adaptation (minor conflicts expected)
   - Risky (heavy dependencies on excluded commits)
4. **Execute**:
   ```bash
   # Single commit
   git cherry-pick <sha>

   # Range (preserving order)
   git rev-list --reverse <start>^..<end> | git cherry-pick --stdin

   # If conflicts arise, help resolve them
   git cherry-pick --continue   # after resolution
   git cherry-pick --abort      # if user wants to bail
   ```
5. **Verify**: `git log --oneline -N` and `git diff HEAD~N..HEAD --stat`

### Partial Cherry-Pick

When only some hunks from a commit are needed:

```bash
PATCH=$(mktemp)
git show <sha> -- <file> > "$PATCH"
# Edit patch to include only desired hunks
git apply --index "$PATCH"   # --index (not --cached): update working tree and
                             # index together; add --3way if it won't apply clean
rm "$PATCH"
git commit -m "<type>: <description> (cherry-picked from <short-sha>)"
```

See the safety warnings under Hunk-Level Staging for recovery if `git apply`
fails. If partial extraction is too complex, cherry-pick the full commit and
clean up unwanted changes afterward with a follow-up commit or amend.

---

## Subcommand: `fixup`

Create fixup commits that target existing commits for later autosquash.

### Usage

```
/atomic fixup [target-ref]    # create fixup for target (default: auto-detect)
```

### Workflow

1. Check staged changes: `git diff --cached --stat`
2. If no target specified, find commits that touched the same files:
   `git log --oneline -- <staged-files>`
3. If staged files map to multiple different commits, show all candidates
   and let the user pick. Do not silently choose one
4. Present the target commit and ask for confirmation
5. Create fixup commit:
   ```bash
   git commit --fixup=<target-sha>
   ```
6. Remind user to integrate later with one of:
   - `/atomic rebase` (agent-assisted)
   - `git rebase -i --autosquash <target-sha>~1` (user runs directly)

---

## Safety Rules

- **Never `git add -A` or `git add .`** -- always stage specific files
- **Never amend** previous commits unless explicitly asked
- **Never push** unless explicitly asked
- **Detect hooks**: Before first commit, check for hook frameworks (husky,
  lefthook, pre-commit) and respect them
- **Staged + unstaged conflict**: If a file has both staged and unstaged
  changes, surface this to the user before proceeding
- **Working state**: Each commit should leave the codebase in a buildable state
  when possible (no broken imports, no partial migrations)
- **Verify after each commit**: `git status --short` to confirm expected state
- **Hook failure recovery**: If a pre-commit hook rejects a commit mid-sequence,
  stop. The staged changes are still in the index. Fix the hook issue (lint,
  format, etc.), re-stage if needed, and retry the commit. Do NOT proceed to
  the next group until the current one succeeds. Never use `--no-verify`.
  Maximum 2 retries per commit -- if it still fails, abort and ask the user

## Conflict Resolution

Applies to rebase, cherry-pick, and any operation that pauses on conflict.

1. **Detect**: `git status --short` -- look for `UU` (both modified), `AA`
   (both added), `DU`/`UD` (delete/modify conflicts)
2. **Read**: Read each conflicted file and find `<<<<<<< HEAD` markers
3. **Analyze**: Compare the two versions. Use surrounding code context and
   commit messages to determine the correct resolution
4. **Resolve**: Edit the file to remove conflict markers (`<<<<<<<`, `=======`,
   `>>>>>>>`) and leave the correct merged code
5. **Stage**: `git add <file>` for each resolved file
6. **Continue**: `git rebase --continue` or `git cherry-pick --continue`

If the conflict is ambiguous (e.g., both sides made intentional but
incompatible changes), ask the user before resolving. Do not guess on
semantic conflicts.

## Principles

- One logical change per commit
- Each commit is independently reviewable
- Dependency-aware ordering (schema before code, types before usage)
- Conventional Commits format: `<type>[(scope)]: <description>`
- Imperative mood, lowercase, no trailing period
- Subject line under 72 characters
- Commit messages and PR descriptions must not reference
  session-internal artifacts (audits, scratch notes, plans, review
  rounds, prior sessions). See **Commit and PR Message Hygiene** for
  examples, heuristic, and rationale.
