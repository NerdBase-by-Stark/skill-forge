# Phase 6 — Second-Pass Edits

**Goal:** Convert verified research findings into concrete skill updates. This is where the library actually improves.

**Depends on:** Phase 5 research docs + Phase 3 candidate review.

## Inputs you're working from

1. `<project>/docs/skill-research/*.md` — the N research docs, each with a "Proposed Skill Rules" section
2. `<project>/.skill-forge/audit-report.md` — Phase 3 candidate review with gems worth extracting
3. The user's existing skills under `~/.claude/skills/`

## Workflow

### 6.1 Read all research docs in a single pass

Use multiple Read calls in one message. Don't spread this across many turns — you need the whole picture to decide how rules group across skills.

### 6.2 Classify each proposed rule

For each research "Proposed Skill Rule", decide:

| Decision | Criteria |
|---|---|
| **ADD** to existing skill | Matches an existing skill's scope, has verified source, isn't already covered |
| **ADD** as new skill | No existing skill covers this domain, but topic is cohesive + reusable |
| **FIX** existing skill | Research contradicts something already in a skill (outdated info) |
| **REJECT** | Unverified, duplicate of existing rule, too project-specific, not reusable |
| **DEFER** | Interesting but not urgent — log for a future run |

Track decisions in a table:

```markdown
| Source doc | Proposed rule | Decision | Target skill | Notes |
|---|---|---|---|---|
| 02-code-signing.md | Rule 1: Always timestamp | ADD | pyside6-desktop/references/signing-and-av.md | Rule number TBD |
| 02-code-signing.md | Rule 3: Azure Trusted Signing decision matrix | FIX | pyside6-desktop Rule 40 | Current Rule 40 has stale EV claim |
| 07-ux-patterns.md | All 10 patterns | ADD | NEW skill: mass-deploy-ux | Distinct domain |
```

### 6.3 Apply FIX decisions first

Fixes to existing incorrect content are highest priority — they prevent the skill from actively misleading future sessions. Make these edits before additions.

### 6.4 Apply ADD to existing skills

For each rule going into an existing skill:
- Number it continuing from the current max (if the skill uses numbered rules)
- Preserve the source citation: `Source: [URL](url) (accessed YYYY-MM-DD)`
- Match the existing skill's voice and formatting
- If the skill has a `references/` structure, add to the correct reference file (not the main SKILL.md) unless the rule is inline-critical

### 6.5 Create new skills

Trigger: a research doc or candidate review produced a cohesive rule set (4+ rules) that:
- Doesn't fit any existing skill's scope
- Has a coherent filePattern / bashPattern trigger set
- Would be useful across multiple future projects (not one-off)

For new skills:
- Follow `writing-skills` or `skill-creator` best practices (invoke those skills)
- Name: kebab-case, verb-first or noun-first consistent with existing library style
- Description: ≤ 300 chars, specific enough to prevent false triggers
- Start with progressive disclosure from day 1 if rule count > 10
- Add cross-references to related user skills in the main SKILL.md

### 6.6 REJECT with reasons logged

Don't silently drop proposed rules. Log every rejection in `<project>/.skill-forge/rejections.md`:

```markdown
## Rejected rules (this run)

### 03-discovery-protocols.md "Rule: Use icmplib with privileged=False"
- **Reason:** Research doc itself notes the param is silently ignored on Windows. Adding this rule would mislead.

### 04-av-evasion.md "Rule: Rename python311.dll to avoid detection"
- **Reason:** Folklore, debunked in same doc. Would actively harm the skill.
```

### 6.7 Update related skills' cross-references

If a new skill was created, add bidirectional references:
- In the new skill's main SKILL.md: "Pairs with: X, Y"
- In skills X and Y: add the new skill to their "Pairs with" section

If a rule moved from one skill to another, leave a forwarding pointer for one run cycle (then remove in next Phase 6).

## Quality gate before committing edits

For each edited skill, verify:
- No claim added without a source URL or project memory reference
- No rule added that wasn't in the research docs or candidate review
- No framework version claims without a version-specific citation
- No breaking change to rule numbering without a rationale logged

## Produce the second-pass log

Write to `<project>/.skill-forge/second-pass-changes.md`:

```markdown
# Second-Pass Changes — <date>

## Summary
- Existing skills modified: 3
- New skills created: 2
- Total rules added: 14
- Rules fixed: 1
- Rules rejected: 5

## Per-skill changes
### pyside6-desktop
- Fixed Rule 40 (stale EV SmartScreen claim) — see research 02
- Added Rules 43-52 to references/ (PyInstaller edges, threading, AV mitigation)

### NEW: mass-deploy-ux
- 10 rules from research 07
- Pairs with: pyside6-desktop, network-device-discovery

### NEW: windows-release-pipeline
- 10 rules from research 06
- Pairs with: pyside6-desktop
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Edits applied — cleanup next?"
Header:   "Phase 6 → 7"
Options:
  - Label: `Refactor for cleanliness`
    Description: Phase 7: split oversized skills, tighten filePatterns
  - Label: `Show changes summary`
    Description: Print second-pass-changes.md before advancing
  - Label: `Explain more`
    Description: Describe what Phase 7 does in detail, then re-ask
  - Label: `Stop`
    Description: Exit; edits preserved
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 7 applies progressive-disclosure refactoring to any skill with a main SKILL.md > 2k tokens — splits into brief main + references/*.md. Also tightens overly-broad filePatterns (no `**/*.py` etc) and resolves any unintentional cross-skill overlap. Takes 2-5 minutes.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

Don't. If you ran research (Phase 5) without processing the results, you just paid for nothing.
