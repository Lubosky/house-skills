---
name: codex-stress-test
description: |
  Adversarial Codex CLI review for stress-testing a plan, design, or decision BEFORE building. The reviewer is biased toward finding failure modes — outputs FATAL / BLIND SPOT / WEAK ASSUMPTION / ALTERNATIVE buckets. Use for prompts like "devil's advocate", "poke holes", "what could go wrong", "find failure modes", "pre-mortem", "stress test". Do NOT use for balanced review of a diff or completed work — that's codex-peer-review; when the review surfaces an either-could-be-right design tension, hand it to codex-council for structured debate; for a one-off question needing advice rather than an attack, use codex-consult. Do NOT use for trivial decisions or sanity checks.
  Do not use from Codex itself; that would recursively launch Codex.
---

# codex-stress-test

Open `@references/guide.md` and follow it. Do not proceed without it.

Stress-test a plan, decision, or design through an adversarial Codex CLI
review. The reviewer is selected to be biased — it will find concerns
even when they are weak. The agent (you) is responsible for filtering
real concerns from theoretical noise.

**Host guard:** If the current host is Codex, stop and explain that this skill
would recursively launch Codex. Do not run `codex exec`.

## When this skill vs `codex-peer-review`

| Want | Use |
|---|---|
| Balanced "is anything wrong here" review of a diff or completed work | `codex-peer-review` |
| Aggressive "what will break this" stress-test before building | `codex-stress-test` |
| Audit existing code for drift, dead code, smells | `codex-peer-review` (target mode) |
| Two-model deliberation on a contested design tradeoff | `codex-council` |

The two skills share the same Codex CLI infrastructure (recipe, sandbox
flags, thread_id capture, resume mechanics) — see
`../codex-peer-review/references/guide.md` (install it alongside this one) for
those. This skill differs in the prompt template and the output taxonomy;
when the review surfaces a contested design tension, it hands off to the
standalone `codex-council` skill for deliberation.

The guide contains:
- Adversarial Round 1 prompt template + output taxonomy
- Round 2 delta prompt, for when reconciliation changed the plan
- Reconciliation guidance (adversarial output requires more filtering)
- Council handoff (`codex-council`) for design tensions
- Adversarial-specific trust-model addendum
- Failure modes
