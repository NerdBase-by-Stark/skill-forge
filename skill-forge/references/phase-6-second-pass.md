# Phase 6 — Second-Pass Edits

**Goal:** Convert verified research findings into concrete skill updates. This is where the library actually improves.

**Depends on:** Phase 5 research docs + Phase 3 candidate review + **user approval via `AskUserQuestion` at the §6.0 gate below**.

## Inputs you're working from

1. `<project>/docs/skill-research/*.md` — the N research docs, each with a "Proposed Skill Rules" section
2. `<project>/.skill-forge/audit-report.md` — Phase 3 candidate review with gems worth extracting
3. The user's existing skills under `~/.claude/skills/`

## Workflow

### 5.5 Research-coverage matrix (before extraction, transparent gap surfacing)

Before running §6.1 (reading research docs for extraction), build a **coverage matrix** that maps every stack component identified in Phase 1 against the research docs that cover it. This catches Phase 5 stream-planning gaps before they become Phase 6 extraction misses.

```
| Stack component (from Phase 1 profile) | Research coverage        | Notes               |
|----------------------------------------|--------------------------|---------------------|
| tailwind-v4 + vite                     | ✓ doc 01                 |                     |
| capacitor-ios-mobile-web               | ✓ doc 02                 |                     |
| ios-logs-xcode26                       | ✓ doc 03                 |                     |
| playwright + vitest                    | ✓ doc 04                 |                     |
| supabase-rls-ssr                       | ✓ doc 05                 |                     |
| react19-vite7                          | ✓ doc 06                 |                     |
| zustand                                | ✗ MISSING                | No stream assigned  |
| cloudflare-pages                       | ✗ MISSING                | No stream assigned  |
```

If any component shows MISSING, **call `AskUserQuestion`** before proceeding to §6.0:

```
Question: "Research has gaps — spawn catch-up streams?"
Header:   "Coverage gaps"
Options:
  - Label: `Spawn catch-up streams`
    Description: Adds <N> research streams (~$<cost>) to cover missing components; extends Phase 5 before extraction
  - Label: `Proceed without coverage`
    Description: Extract from current research; skills won't cover missing components until next run
  - Label: `Explain more`
    Description: Show what each missing component would research
```

This is not Audit Army. It's a transparent free check (no agents spawned) that surfaces what Phase 5 planning may have missed, and lets the user decide whether to spend catch-up-stream cost or accept the gap. Most runs will have zero gaps; when gaps exist, the user makes an informed decision.

### 6.0 Phase 5 → 6 second-pass approval gate (MANDATORY in autopilot)

This is the **second write-consent gate**. Runs BEFORE any edit to `~/.claude/skills/`. The user sees every proposed Phase 6 change in plain English and approves via `AskUserQuestion`.

**Sequence:**

1. Perform §6.1 (read all research docs) and §6.2 (classify each proposed rule) — these are reads/analyses only, no writes.
2. Run the **justification bar** filter (same bar as Phase 3→4):
   - Each proposed rule must name a **concrete observable gain** — "closes a verified knowledge gap flagged in research doc 0N", "prevents silent failure X", "codifies behaviour change in library Y v2.0"
   - Drop proposals that amount to rewording existing content with no new information
   - Keep UNVERIFIED flags as rejected (already a Phase 6 rule) — never silently drop
3. Print the plain-English change blocks (same format as Phase 3→4, see `phase-3-find-candidates.md §Step B`), one per proposed change. For new-skill proposals, print an extra block:
   ```
   New skill: <name>
   Scope:     <one-line summary>
   Rules:     <N> inline + <M> in references/
   Trigger:   <filePattern / bashPattern list>
   Pairs with: <existing skills this cross-refs>
   ```
4. Present the approval dialog:

```
Question: "<N> changes + <K> new skills proposed — approve?"
Header:   "Phase 5 → 6 approval"
Options:
  - Label: `Approve all`
    Description: Apply every change and create every new skill
  - Label: `Review each`
    Description: Walk change-by-change with approve/skip
  - Label: `Additions only`
    Description: Add new rules to existing skills; skip new-skill creation
  - Label: `Cancel`
    Description: Make no Phase 6 changes; advance to Phase 7 on nothing
```

If **Review each**, loop `AskUserQuestion` per change with `[Approve / Skip / Show source doc / Cancel review]`. "Show source doc" prints the relevant `docs/skill-research/0N-*.md` section then re-asks.

**Leave-alone reminder:** existing skill wording is NOT proposed for rewording in Phase 6 unless research directly contradicts it (a FIX, not an enhancement). Additions append; they don't rephrase. A skill can be "Fits — leave alone" in Phase 2 AND gain new rules here — those are not mutually exclusive.

**Healthy-library Phase 6 exit:** if the justification bar leaves zero changes (all research gems were already covered or were UNVERIFIED), print *"Research surfaced no new verified additions that pass the justification bar"* and `AskUserQuestion` with `[Advance to Phase 7 / Show what was filtered / Stop]`.

Only after the user approves does §6.3 onwards execute. Cancel = advance to Phase 7 on an empty change set.

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

### 6.6b Sonnet critique pass (automatic, cheap)

After §6.1-§6.6 complete (primary extraction done, logged to `second-pass-changes.md`), but BEFORE §6.0 presents the approval gate, automatically spawn a single **Sonnet read-only critique sub-agent** to find extraction gaps.

See `references/phase-6-critique.md` for the full brief template, output format, supervisor-handles-results protocol, and skip-flag behavior.

Summary of flow:
1. Supervisor (Opus or user's chosen model) finishes primary extraction
2. Supervisor spawns one Sonnet sub-agent: `subagent_type: general-purpose, model: sonnet, run_in_background: true`
3. Sub-agent reads Phase 5 research docs + extraction log, writes gap report to `.skill-forge/phase-6-critique.md`
4. Supervisor reads the critique gap list, folds gaps into the approval gate's proposal list with `[Model-specific: Sonnet critique]` tags
5. Gate presents the combined set; user approves per-change as usual

Cost: ~$0.30-0.50 per run. Skipped automatically under `--budget=low` or explicitly via `--skip-critique`.

Evidence base: caught Keyboard v8 event-rename extraction gap in biltong-buddy 2026-04-19 run.

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
