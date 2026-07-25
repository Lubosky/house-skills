# house-skills

Portable agent skills used across Claude Code, Codex, and Gemini. Each skill is
a directory holding a `SKILL.md`, plus `references/` or `scripts/` where the
workflow needs more room. The four Codex second-opinion skills form one family
built on a shared base: `codex-peer-review` installs standalone, and the other
three each require it alongside them.

## Skills

- **[`atomic`](./atomic)** — Split working-tree changes into logical atomic
  commits, generate conventional commit messages, plan interactive rebases,
  cherry-pick safely, and audit commit history for session-internal references.
  Subcommands: `commit` (default), `generate`, `rebase`, `cherry-pick`,
  `fixup`, `audit` (alias `lint`); all support `--dry-run`.

### The codex family — second opinions in a fresh Codex thread

Four skills that shell out to the [Codex CLI](https://github.com/openai/codex)
so a non-Codex host agent can get an isolated second opinion instead of grading
its own homework. Pick by what you are holding:

| You have                                      | Use                                        |
|-----------------------------------------------|--------------------------------------------|
| A finished diff, or a file/folder to audit    | [`codex-peer-review`](./codex-peer-review) |
| A plan you haven't built yet                  | [`codex-stress-test`](./codex-stress-test) |
| A decision where either answer could be right | [`codex-council`](./codex-council)         |
| A question with no artifact to review at all  | [`codex-consult`](./codex-consult)         |

- **[`codex-peer-review`](./codex-peer-review)** — balanced review loop:
  self-review → external review → reconciled findings by default. `--apply`
  continues through agreed fixes and Round 2 verification, with lens rotation
  for deeper multi-round reviews. Diff mode reviews the working tree; target
  mode audits a file or folder for drift, dead code, and smells.
- **[`codex-stress-test`](./codex-stress-test)** — adversarial pre-mortem on a
  plan or design. The reviewer is deliberately biased toward finding failure
  modes and buckets them FATAL / BLIND SPOT / WEAK ASSUMPTION / ALTERNATIVE;
  the calling agent does the filtering and quarantines what it drops in view of
  the user.
- **[`codex-council`](./codex-council)** — structured two-position debate. Your
  agent argues position A, Codex defends position B across rebuttal rounds,
  then your agent synthesizes and a fresh neutral call validates the synthesis.
- **[`codex-consult`](./codex-consult)** — one Codex call for a position on a
  question. No diff, no file target, nothing edited: advice in, advice out.

**`codex-peer-review` is the shared base.** Its
`references/guide.md` carries the CLI setup, model table, `codex exec` /
`codex exec resume` flag semantics, and the trust model that the other three
reference instead of duplicating. So `codex-peer-review` is installable on its
own, but each of the other three needs it installed beside them or their sibling
references dangle; `codex-stress-test` additionally references `codex-council`
for its deliberation handoff.

The Codex family is intended for hosts such as Claude Code and Gemini. Do not
install it into Codex itself unless you explicitly want a nested Codex process;
`atomic` remains suitable for Codex.

## Requirements

`atomic` needs `git`. The codex family needs:

| Tool                        | Why                                               |
|-----------------------------|---------------------------------------------------|
| `codex` (codex-cli ≥ 0.144) | Runs the external review. Run `codex login` once  |
| `git`                       | Working-root discovery; diff capture in diff mode |
| `jq`                        | Reads the thread ID out of the JSONL event stream |
| `rg` (ripgrep)              | Detects an empty peer-review diff capture         |
| `tokei` (optional)          | Target-mode size guard; falls back to `find`      |

The `0.144` floor is where the family's `codex exec resume` semantics were
observed to hold — resume accepts neither `-s` nor a subcommand-level `-C`, and
re-pinning model and sandbox on every resume is mandatory. Verified against
codex-cli 0.145.0.

## Install

**Claude Code** — copy the skills you want into your skills directory:

```bash
mkdir -p ~/.claude/skills
cp -r atomic ~/.claude/skills/
cp -r codex-peer-review codex-stress-test codex-council codex-consult ~/.claude/skills/
```

…or pull them with the `skills` CLI (one invocation per skill):

```bash
npx skills add Lubosky/house-skills --skill atomic -g -a claude-code
npx skills add Lubosky/house-skills --skill codex-peer-review -g -a claude-code
npx skills add Lubosky/house-skills --skill codex-stress-test -g -a claude-code
npx skills add Lubosky/house-skills --skill codex-council -g -a claude-code
npx skills add Lubosky/house-skills --skill codex-consult -g -a claude-code
```

**Codex** reads user skills from `~/.agents/skills`; install `atomic`, not the
recursive Codex family:

```bash
mkdir -p ~/.agents/skills
cp -r atomic ~/.agents/skills/
```

**Gemini** reads user skills from `~/.gemini/skills`:

```bash
mkdir -p ~/.gemini/skills
cp -r atomic codex-peer-review codex-stress-test codex-council codex-consult ~/.gemini/skills/
```

## Notes

These skills are authored for **Claude Code**: the `allowed-tools` frontmatter
is a Claude Code convention, and `AskUserQuestion` is its structured-question
tool — on another agent, read that as "stop and ask the user." Other agents
ignore unknown frontmatter and read the body as plain workflow guidance.

`atomic` requests `Bash(git *)`, which is broad — Claude Code's prefix matching
can't express "git but not `push`/`commit --amend`/`add -A`", so the grant
technically covers destructive commands too. The skill restricts itself to safe
operations in prose (see its **Safety Rules**: never force-push, never amend
unasked, never `git add -A`), but the allow-list can't enforce that. Review the
frontmatter before installing if that matters to you.

The codex skills declare no `allowed-tools` at all and so inherit whatever the
session grants. The family uses `Bash` for `codex`, `jq`, and `mktemp`;
peer-review diff mode additionally uses `git` and `rg`. Prompt authoring also
needs file reads and writes.

**They also send your code to a model provider.** Every fresh call uses
`-s read-only`; resumes re-pin the equivalent read-only configuration. This
stops Codex mutating files — it does *not* stop network egress. Whatever Codex
reads, including secrets in tracked or untracked files, reaches whichever
provider the CLI is authenticated against. Point them only at artifacts you are
willing to send.

## License

[MIT](./LICENSE) © 2026 Lubos Hricak
