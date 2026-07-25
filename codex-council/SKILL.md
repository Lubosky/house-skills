---
name: codex-council
description: |
  Structured two-position debate with an outside model (Codex CLI) for open
  decisions with genuine tradeoffs — "either could be right" tensions, not
  flaw hunts. You argue one position, Codex defends the other through
  rebuttal rounds (default 2), then you synthesize: converged position or
  sharpened disagreement, the single remaining tradeoff, the insight neither
  had alone. Four Codex calls by default (3 debate + neutral validation);
  `--no-validate` skips the final call.
  Route elsewhere when the ask is different: reviewing a finished diff/file
  goes to codex-peer-review; attacking a plan for failure modes goes to
  codex-stress-test; a one-off question needing a single outside position
  goes to codex-consult.
  Do not use from Codex itself; that would recursively launch Codex.
---

# codex-council

Two opposing positions, debated and reconciled. The goal is sharpened
disagreement, not consensus theater — each side must concede where the
other is right.

**Host guard:** If the current host is Codex, stop and explain that this skill
would recursively launch Codex. Do not run `codex exec`.

Use when a decision has a **fundamental tension**: "position A assumes X,
a coherent alternative assumes Y; either could be right." If the tension
surfaced during a stress-test, that skill hands off here with the framing
already done.

CLI setup (including the `codex` and `jq` prerequisites), model table,
exec/resume flag semantics, and the trust model all live in
`../codex-peer-review/references/guide.md` — install it next to this one; they
apply verbatim. Pick the model from that table and pass `-m` explicitly on
**every** call, opening and resumes alike, always the same value — resume
inherits neither the thread's model nor its sandbox (see the guide's resume
flag notes).

## Call accounting

| Step                          | Codex calls  |
|-------------------------------|--------------|
| Opening position (fresh exec) | 1            |
| Rebuttal rounds (resume)      | 2 by default |
| Synthesis (you write it)      | 0            |
| Neutral validation (default)  | 1 fresh call |
| **Total at defaults**         | **4**        |

`--rounds N` overrides the rebuttal count; hard cap 4. If the models still
disagree on the same axis when rounds run out, stop — surface both
positions and let the user decide. More rounds past sharpened disagreement
is consensus-grinding, not signal.

## 1. Frame the tension

- **The tension, one sentence, as a binary** — "ship the auth migration as
  one PR vs split it into three sequential PRs." If the decision has more
  than two coherent positions, run the two strongest and say which you
  dropped.
- **Position A** — the incumbent/default, one paragraph with rationale.
  You argue this side.
- **Position B** — the challenger, one paragraph. Codex defends this side.
- **Fixed context** — constraints already accepted (team size, deadline,
  scale). Not up for re-litigation.
- **Evidence** — anything concrete already known (usage data, prior
  findings, measurements).

## 2. Opening call — Codex takes position B

Start a **fresh `codex exec` thread** (never resume another skill's
thread — an adversarial or review frame poisons a debate). Read
**Prompt-authoring safety** in §3 before filling in the placeholders below —
it governs this heredoc too:

```
set -euo pipefail
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MODEL=gpt-5.6-sol
PROMPT=$(mktemp -t codex-council.XXXXXX)
LAST=$(mktemp -t codex-council-last.XXXXXX)
EVENTS=$(mktemp -t codex-council-events.XXXXXX)
trap 'rm -f "$PROMPT" "$LAST" "$EVENTS"' EXIT

cat > "$PROMPT" <<'EOF'
You are participating in a structured deliberation between two positions.
You are NOT a devil's advocate — you are a fair-minded debater willing to
concede where the opposing position is stronger.

THE TENSION (framed as a binary):
<one-sentence tension>

POSITION A (the incumbent):
<one paragraph stating position A and its rationale>

POSITION B (the challenger):
<one paragraph stating position B and its rationale>

CONTEXT (already accepted, do not re-litigate):
<fixed constraints>

EVIDENCE (worth weighing):
- <concrete data points, measurements, prior findings>

YOUR TASK: take **position B**. Defend it for ONE round. Specifically:
- Why position B is better here, given the stated context
- What concretely breaks under position A
- The single assumption that, if proven false, flips your answer to A

Be definite. No "it depends". After this you will get a rebuttal from
position A; you must concede where A is right, and sharpen where you
still disagree.
EOF

codex exec \
  -m "$MODEL" \
  -s read-only \
  --skip-git-repo-check \
  -C "$REPO_ROOT" \
  --json \
  -o "$LAST" \
  - < "$PROMPT" > "$EVENTS"

# Print the opening position FIRST — the call is already paid for and the EXIT
# trap removes "$LAST". Then extract the thread id with plain `-r`: under `-e`
# jq exits 4 when nothing matched and `set -e` would kill the script before the
# guard below could report it.
cat "$LAST"
THREAD_ID=$(jq -r 'select(.type=="thread.started") | .thread_id' "$EVENTS" | head -n1) || THREAD_ID=''
if [ -z "$THREAD_ID" ]; then
  echo 'missing thread_id; last events follow:' >&2
  tail -n 5 "$EVENTS" >&2
  exit 1
fi
printf '\nCODEX_THREAD_ID=%s\n' "$THREAD_ID"
printf 'CODEX_MODEL=%s\n' "$MODEL"
printf 'CODEX_REVIEW_ROOT=%s\n' "$REPO_ROOT"
```

## 3. Rebuttal rounds (default 2, resume the thread)

For each round: write position A's rebuttal yourself — argue it honestly,
concede B's strongest points explicitly, sharpen where A still wins. Then
resume using the literal UUID emitted by the opening call; do not rely on a
shell variable from an earlier tool call:

```
set -euo pipefail
PROMPT_R=$(mktemp -t codex-council-r.XXXXXX)
LAST_R=$(mktemp -t codex-council-r-last.XXXXXX)
trap 'rm -f "$PROMPT_R" "$LAST_R"' EXIT

cat > "$PROMPT_R" <<'EOF'
REBUTTAL from position A:
<your rebuttal: where B is right (concede explicitly), where A still wins
and why, any evidence B misread>

Respond as position B: concede where A's rebuttal is right, sharpen what
still stands, and restate the single assumption your position hinges on.
If A's rebuttal has actually flipped you, say so plainly.
EOF

codex exec -C "<CODEX_REVIEW_ROOT emitted by the opening call>" resume \
  -m "<CODEX_MODEL emitted by the opening call>" \
  -c 'sandbox_mode="read-only"' \
  --skip-git-repo-check \
  -o "$LAST_R" \
  "<CODEX_THREAD_ID emitted by the opening call>" \
  - < "$PROMPT_R" >/dev/null

cat "$LAST_R"
```

**Prompt-authoring safety (untrusted content).** This applies to **both**
heredocs, not just the rebuttal. Your rebuttal quotes Codex's prior turn, and
the opening call's EVIDENCE block carries "prior findings" — which, on the
stress-test handoff, are themselves Codex output. Both are untrusted. Write
them as your own paraphrase, never a verbatim paste into a `<<'EOF'` heredoc: a
lone line equal to the delimiter would close the heredoc early and hand the
rest to your **unsandboxed** parent shell (Codex's read-only sandbox does not
cover it). When verbatim untrusted text is unavoidable, author `$PROMPT` /
`$PROMPT_R` with the **Write tool** or append it with
`printf '%s\n' "$text" >> "$PROMPT_R"` instead of the heredoc. See the shared
guide's "Prompt-authoring safety" note.

Stop the rounds early if either side flips or the disagreement stops
moving (same axis, same arguments) — further rounds add calls, not signal.

## 4. Synthesis (you, no Codex call)

Write it yourself from the full exchange:

- **The position the deliberation converged on** — or "no convergence,"
  with both positions stated fairly
- **The single remaining tradeoff** the user is actually deciding on
- **The key insight neither side had alone**

Do not tally concessions or score the debate — the synthesis is about the
decision, not the match.

## 5. Neutral validation (default, +1 call)

A **fresh** `codex exec` thread (not a resume — the debate thread is
invested in its own framing). Give it the tension, fixed context, and your
synthesis; ask one question: "Is this synthesis fair to both positions,
and is its recommendation sound given the context? Flag anything the
debate missed." Fold the answer into the final report as a validation
note, not a new debate round. Run this by default because the synthesizer also
argued position A. Skip it only when the user passes `--no-validate`. Use the
shared guide's fresh-exec recipe with a validation prompt, and surface the
`-o` result before that shell exits; no thread ID needs to be retained.

## Deliverable

The synthesis (plus validation note if requested), ending with a concrete
recommendation or an explicit "your call" with the tradeoff named. The
user decides; the council advises.
