---
name: codex-peer-review
description: |
  Get a balanced second opinion via Codex CLI. Default is findings-only:
  self-review → external review → reconcile. Pass --apply to make agreed fixes
  and run follow-up verification. Diff mode (no path) reviews working-tree
  changes; target mode audits a file/folder for drift, dead code, and smells.
  --artifact PATCH reviews a prepared patch; --review-root DIR uses a
  sanitized review cwd and requires --artifact. Default model is gpt-5.6-sol;
  gpt-5.6-luna is the lighter option. Use for balanced review of existing work.
  Route adversarial plan review to codex-stress-test, one-off advice to
  codex-consult, and structured tradeoff debate to codex-council.
  Do not use from Codex itself; that would recursively launch Codex.
---

# codex-peer-review

Open `@references/guide.md` and follow it. Do not proceed without it.

Get a second opinion from an outside model through the Codex CLI. The loop is:
self-review → external review → reconcile → findings. With `--apply`, continue
through agreed fixes and an optional Round 2.

**Host guard:** If the current host is Codex, stop and explain that this skill
would recursively launch Codex. Do not run `codex exec`.

For deeper reviews that warrant more rounds: R1 keeps its initial framing, R2 stays the delta verification, **R3 onwards rotates the audit lens** (perf → drift/dead-code → boundary contracts → … pick what's relevant), and the **final round is a context reset** (fresh thread, contract artifacts only — moduledocs/types/public-API tests; fall back to a fresh full-artifact review if no contract exists). Same-lens iteration past R2 compounds blind spots. See the guide's "Multi-round (Round 3+) — rotate the lens" section.

## Mode dispatch

- **No args** → **diff mode.** Review uncommitted changes in the working tree. This is the default.
- **Path arg** (file or folder) → **target mode.** Audit the artifact as-is for inconsistencies, drift, dead code, and smells. Use the "Target review" section of the guide for the self-review checklist and Round 1 template.
- **`--artifact <patch>`** → **diff mode with a caller-prepared artifact.** Read the patch byte-for-byte instead of running `git diff`. The caller owns scope completeness.
- **`--review-root <path>`** → set the external process cwd to this existing
  sanitized tree instead of the live repository. This modifier requires
  `--artifact`; keep the root at the same path until all possible resumes end,
  and explicitly tell the reviewer not to read outside it.
- **Default (no `--apply`)** → stop after reconciliation and return findings.
  Do not edit or run Round 2+.
- **`--review-only`** → compatibility alias for the default findings-only
  behavior.
- **`--apply`** → after reconciliation, make only the agreed fixes and run
  follow-up verification. This composes with either mode.

Target mode has a size guard: if the path expands to more than ~20 files or ~2000 LOC, stop and ask the user to narrow scope before calling Codex.

Default model: `gpt-5.6-sol`. Switch to `gpt-5.6-luna` per call for a lighter/faster lens.
Fresh `codex exec` calls start with `-s read-only --skip-git-repo-check`;
resumed calls must re-pin working root (`codex exec -C <opening root> resume`),
sandbox (`-c 'sandbox_mode="read-only"'`), and model (`-m`, same value as the
opening call) — resume does not restore them reliably. The agent can read but
not mutate files.

The guide contains:
- Codex CLI setup and the model table
- Round 1 / Round 2 invocation recipes
- Reconciliation and stop conditions
- Trust model and failure modes
