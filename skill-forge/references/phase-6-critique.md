# Phase 6 Critique Pass — Sonnet read-only gap-finder

**Goal:** Catch extraction misses in Phase 6. One cheap Sonnet sub-agent reads the Phase 5 research docs + Phase 6 extraction log and reports what wasn't extracted but should have been.

**Depends on:** Phase 5 research docs + Phase 6 primary extraction (§6.1-§6.7) complete.

**Cost:** ~$0.30-0.50 per run. No web research, no file writes to `~/.claude/skills/`. Read-only.

**When this runs:** Automatically after §6.7 (primary extraction log written), before the Phase 5→6 approval gate presents the change set. The gaps surfaced here are added to the gate as "Model-specific: Sonnet critique" proposals.

## Why it exists

Primary extraction — done by whichever model is the supervisor — reads Phase 5 research docs and pulls rules into skills. But a single pass has a predictable failure mode: **novel rules buried inside otherwise-extracted docs get missed.** In the 2026-04-19 biltong-buddy run, the primary (Opus) extraction pulled most Capacitor mobile-web rules but missed the Keyboard v8 event rename (Gem 5 in doc 02). A Sonnet critique pass reading the same doc flagged the gap.

Root cause: extraction quality is "thorough" but not "exhaustive." A fresh pair of eyes with a narrow mandate (find gaps, don't extract) catches what the primary missed. The pattern generalizes — same reason code review catches bugs the author missed even when the author was careful.

## The brief template

```
You are performing a Phase 6 critique pass on skill-forge second-pass extraction work.
Your supervisor (a different model, typically Opus) has already extracted rules from
Phase 5 research docs into skills. Your job: find what the supervisor missed.

## STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.

Standard strict-scope clause — no git/gh/branch/commit/PR/sub-agent-spawn.
Also: you cannot call AskUserQuestion.
You CANNOT modify any skill file. You are READ-ONLY.

Your single write operation is the gap report at the output path below.

## Inputs to read

1. `<project>/docs/skill-research/*.md` — all Phase 5 research docs
2. `<project>/.skill-forge/second-pass-changes.md` — the primary extraction log listing
   what rules got added to which skills
3. Current state of any skill mentioned in the extraction log — read the main SKILL.md
   and relevant references/ files to confirm what's present

## Your task

For every research doc:
1. List each "Verified Gem" and "Proposed Skill Rule"
2. Check whether it landed in any skill (via grep on rule text, or by reading the
   extraction log's per-skill bullet points)
3. Flag gems/rules that did NOT land and justify inclusion:
   - Is the rule actually verified? (Cite the research doc's verification status)
   - Is it relevant to the target project? (Cross-check Phase 1 profile)
   - Is it non-duplicate? (Not already covered by an existing rule with different wording)

Produce a gap report. Err on the side of reporting — the supervisor will filter at the gate.

## Don't

- Don't extract rules yourself. Your output is gap findings, not new rule content.
- Don't re-research. If a rule is UNVERIFIED in the source doc, flag it as a rejected gap,
  not a new research question.
- Don't second-guess deliberate extraction choices. If the extraction log explicitly says
  "rejected: UNVERIFIED" for a gem, don't re-propose it.
- Don't comment on wording quality. Focus on completeness.

## Output format

Write to `<project>/.skill-forge/phase-6-critique.md`:

```markdown
# Phase 6 Critique Pass — 2026-MM-DD

## Supervisor model: <opus | sonnet>
## Critique model: sonnet

## Gaps found

### Gap 1: <short title>
- **Research doc:** `docs/skill-research/0N-<slug>.md` §<section>
- **Gem/Rule:** <quote the exact finding from the research doc>
- **Target skill:** <skill-name>
- **Why it should land:** <one paragraph — verification status, project relevance,
  non-duplicate justification>
- **Severity if missed:** <low | medium | high — e.g., silent-regression, production-bug, informational>

### Gap 2: ...

## Verified NO gaps (to record diligence)

Research docs I read with zero gap findings:
- `docs/skill-research/01-<slug>.md` — all gems extracted
- `docs/skill-research/03-<slug>.md` — all gems extracted
```

## Scope

Maximum 300 lines. Quality over breadth. If you find zero gaps, say so in the
"Verified NO gaps" section — silence is a valid output.
```

## How the supervisor handles the critique output

The supervisor (main context) reads `phase-6-critique.md` after the critique agent completes. For each gap:

1. **If severity=high AND target-skill is user-owned:** auto-add to the Phase 5→6 approval gate as a proposal marked `[Model-specific: Sonnet critique]`
2. **If severity=medium:** add to gate but tag clearly so the user can skip quickly
3. **If severity=low:** log to second-pass-changes.md as "Deferred gaps (low severity)"; don't burden the gate

The gap proposals go through the standard justification bar — same rules, same gate UX. The `[Model-specific: Sonnet critique]` tag is informational for the user, not a special path.

## Skipping this phase

`--skip-critique` — for budget-constrained runs. Note in the run log that critique was skipped; the next run may want to enable it to catch accumulated gaps.

`--budget=low` — automatically skips critique. The trade-off is documented at the Phase 4→5 cost gate so the user knows what they're opting out of.

## Anti-patterns

- **Critique agent doing web research.** It's a read-only gap-finder. If it starts citing new URLs, it's outside scope — reject the output and re-run with stricter brief.
- **Critique agent proposing new rules not in research docs.** Same — it should only surface gaps from existing docs, not invent.
- **Dual critique passes (Opus critique + Sonnet critique).** Wasteful. One critique pass catches 80-90% of gaps; a second finds diminishing returns.
- **Running critique BEFORE primary extraction.** Breaks the sequential dependency; critique needs the extraction log to compare against.

## Cost-benefit summary

| Aspect | Value |
|---|---|
| Token cost per run | ~$0.30-0.50 |
| Evidence of value | Caught Keyboard v8 gap in biltong-buddy 2026-04-19 run |
| Failure rate (unknown) | Sample size 1; monitor over next 5+ runs |
| Risk if enabled | Low (read-only, no `~/.claude/skills/` writes) |
| Risk if disabled | Extraction gaps compound over runs; memory-tracking makes them discoverable but fixes require a future run |

Default: enabled. Opt out via `--skip-critique` or `--budget=low`.
