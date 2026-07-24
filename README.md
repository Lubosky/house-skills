# house-skills

Portable agent skills used across Claude Code, Codex, and Gemini. Each skill is
a self-contained `SKILL.md` in its own directory.

## Skills

- **[`atomic`](./atomic)** — Split working-tree changes into logical atomic
  commits, generate conventional commit messages, plan interactive rebases,
  cherry-pick safely, and audit commit history for session-internal references.
  Subcommands: `commit` (default), `generate`, `rebase`, `cherry-pick`,
  `fixup`, `audit` (alias `lint`); all support `--dry-run`.

## Install

**Claude Code** — copy the skill into your skills directory:

```bash
mkdir -p ~/.claude/skills
cp -r atomic ~/.claude/skills/
```

…or pull it with the `skills` CLI:

```bash
npx skills add Lubosky/house-skills --skill atomic -g -a claude-code
```

**Codex / Gemini** — these read user skills from `~/.agents/skills` and
`~/.gemini/skills` respectively:

```bash
mkdir -p ~/.agents/skills ~/.gemini/skills
cp -r atomic ~/.agents/skills/     # Codex
cp -r atomic ~/.gemini/skills/     # Gemini
```

## Notes

These skills are authored for **Claude Code**: the `allowed-tools` frontmatter
is a Claude Code convention. Other agents ignore unknown frontmatter and read
the body as plain workflow guidance.

`atomic` requests `Bash(git *)`, which is broad — Claude Code's prefix matching
can't express "git but not `push`/`commit --amend`/`add -A`", so the grant
technically covers destructive commands too. The skill restricts itself to safe
operations in prose (see its **Safety Rules**: never force-push, never amend
unasked, never `git add -A`), but the allow-list can't enforce that. Review the
frontmatter before installing if that matters to you.

## License

[MIT](./LICENSE) © 2026 Lubos Hricak
