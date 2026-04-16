# Phase 8 — QA

**Goal:** Automated audit of every skill touched in this run. Prevent shipping broken frontmatter or missing reference files.

**Depends on:** Phases 4, 6, 7 (whatever edits were made).

## Run the audit script

```bash
bash ~/.claude/skills/skill-forge/scripts/audit.sh <skill-path> [<skill-path> ...]
```

The script checks each skill for:

1. **YAML frontmatter valid** — parses as YAML, has `name` and `description`
2. **`name` matches directory name** — prevents accidental rename bugs
3. **Description ≤ 300 chars** — Claude best practice
4. **filePattern exists** and is a list (can be empty list `[]` for user-invocable-only skills)
5. **Rule coverage** — if the skill uses numbered rules, no gaps and no duplicates across all markdown files (main + references)
6. **References exist** — every `references/X.md` mentioned in main SKILL.md is a real file
7. **No orphan references** — every file in `references/` is mentioned at least once in main SKILL.md
8. **Main SKILL.md size** — warn if > 2,500 tokens
9. **Cross-skill filePattern overlap** — detect identical glob patterns in multiple skills (prints as matrix)

## Manual checks (beyond the script)

After the script runs clean, spot-check:

### 8.1 Read the main SKILL.md of each edited skill
- Does the first 2 paragraphs make the scope clear?
- Do the inline critical rules actually match the "most commonly violated" claim? (Sanity: if a rule is there because it's rare but severe, say so)
- Does the pointer table look right?

### 8.2 Open one random reference file per skill
- Does it have a one-line purpose statement at the top?
- Any broken markdown (unclosed code blocks, orphaned list markers)?
- Any "TODO" or "XXX" markers left in?

### 8.3 Check recent edits rendered correctly
- Grep each edited skill for `(accessed YYYY-MM-DD)` — source citations should be present
- Grep for `UNVERIFIED` — if any leaked into committed skills, that's a bug (they should live in research docs only)

### 8.4 Verify filePattern targets actually exist in SOME real project
Not the target project necessarily. If a skill's filePattern matches zero files anywhere on the user's machine, the skill will never auto-trigger:

```bash
for pattern in <filePatterns>; do
  echo "$pattern:"
  find ~ -path ~/.claude -prune -o -type f -name "$pattern" -print 2>/dev/null | head -3
done
```

### 8.5 YAML-lint every SKILL.md
Fast catch of subtle issues (tab indentation, missing colons):

```bash
for f in ~/.claude/skills/*/SKILL.md; do
  python3 -c "
import yaml
with open('$f') as h:
    parts = h.read().split('---', 2)
    if len(parts) < 3: 
        print('$f: NO FRONTMATTER'); exit()
    try:
        yaml.safe_load(parts[1])
    except Exception as e:
        print(f'$f: {e}')
"
done
```

## Fix vs defer

For each QA issue:
- **Trivial fixes** (typo in description, missing source date): fix immediately, re-run script
- **Structural issues** (rule numbering collision, orphan reference): fix in this phase
- **Non-fatal warnings** (skill size 2,100 tokens — slightly over target): note in report but don't force refactor in this session

## Produce the QA report

Write to `<project>/.skill-forge/qa-report.md`:

```markdown
# QA Report — <date>

## Script output
<paste audit.sh output verbatim>

## Manual checks
- Source citations present: ✓
- UNVERIFIED markers leaked: 0
- filePattern targets real files: ✓ all patterns match ≥1 file
- YAML frontmatter valid: ✓ 5/5 skills

## Issues fixed this phase
- pyside6-desktop: fixed description length 355 → 239 chars
- python-packaging: normalized multi-line description to single-line

## Non-fatal warnings (noted, not fixed)
- network-device-discovery main is 8,631 tokens — refactor candidate for next run
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "QA passed — persist to memory?"
Header:   "Phase 8 → 9"
Options:
  - Label: `Save to memory`
    Description: Phase 9: write architectural decisions + preferences to project memory
  - Label: `Explain more`
    Description: Describe what Phase 9 persists, then re-ask
  - Label: `Stop (not recommended)`
    Description: Skips memory persistence — next run starts blind
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 9 writes 2-5 memory entries to `~/.claude/projects/<slug>/memory/`: new feedback preferences learned this run, architectural decisions from the research (with their why), and a reference entry pointing to the research docs. Updates MEMORY.md index with concise one-line descriptions. Takes ~30 seconds. Future sessions start with this context pre-loaded.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

Never skip. Phase 8 is what prevents shipping a broken skill library.
