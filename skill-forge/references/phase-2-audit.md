# Phase 2 — Audit

**Goal:** Catch existing problems in the project's relevant skills before any research happens. Size bloat, trigger over-eagerness, cross-skill overlap, stale content.

**Depends on:** Phase 1 profile.

## Steps

### 2.1 Run the audit script

```bash
bash ~/.claude/skills/skill-forge/scripts/audit.sh ~/.claude/skills/<skill1> ~/.claude/skills/<skill2> ...
```

The script emits a structured report covering:

- Token size per skill (main + any references)
- YAML frontmatter validity (name, description present; description ≤ 300 chars)
- filePattern overlap matrix between listed skills
- Description length check
- Rule count per skill (counts `^##+ Rule N:` headings)
- References/ subdirectory existence + file count
- Orphan references (references/*.md not mentioned in main SKILL.md)
- Broken cross-references (main mentions `references/X.md` but file doesn't exist)

### 2.2 Check for stale content

For each skill's main SKILL.md, grep for:
- **Dates older than 12 months** — `2023`, `2024` if current year is 2026+
- **Deprecated API references** — version strings that might be behind current stable
- **Project-specific details that belong in project memory, not global skills** — hostnames, IPs, customer names

Flag these as **review candidates** for Phase 6. Don't auto-delete.

### 2.3 Cross-skill overlap analysis

For each pair of relevant skills, compute:
- Common filePattern globs (literal match)
- Common topic keywords in descriptions
- Explicit cross-references (`pairs with X`, `see X skill`)

High overlap without explicit pairing = candidate for consolidation. Explicit pairing with no overlap = well-structured. Report both.

### 2.4 Description quality review

For each skill:
- Is the description specific enough to prevent false-positive triggering? (`Python stuff` = bad. `PySide6 desktop app rules, QSS gotchas, PyInstaller packaging` = good)
- Does it state when to USE vs when NOT to use?
- ≤300 chars?

### 2.5 Produce audit report

Write to `<project>/.skill-forge/audit-report.md`:

```markdown
# Skill Audit Report — <project> — <date>

## Size audit
| Skill | Main tokens | Has references? | Ref count | Verdict |
|---|---|---|---|---|
| pyside6-desktop | 1,698 | ✓ | 7 | Good |
| network-device-discovery | 8,631 | ✗ | 0 | **Borderline** — consider refactor |
| python-packaging | 1,320 | ✗ | 0 | Good |

## Trigger precision audit
<list any filePattern that matches `**/*.py`, `**/*.js` — too broad>
<list any bashPattern that matches common commands — too broad>

## Cross-skill overlap
<matrix of which skills match the same files — if cells > 1 skill, list them>

## Stale content flags
<list rules/sections with year markers > 12 months old or deprecated references>

## Recommendations
1. <concrete action items, ordered by impact>
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Audit done — next step?"
Header:   "Phase 2 → 3"
Options:
  - Label: `Find external skills`
    Description: Search community skills registry for candidates to review
  - Label: `Skip to local edits`
    Description: Jump to Phase 4 — improve skills using only local knowledge
  - Label: `Explain more`
    Description: Describe what Phase 3 does in detail, then re-ask
  - Label: `Stop`
    Description: Exit cleanly; audit report preserved
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 3 runs 3-5 `npx skills find` queries based on your tech stack, clones the top candidates to `<project>/skill-review/` (git clones only — never installs), and reviews each candidate for quality, overlap, and unique value. Produces a candidate-review section in audit-report.md with gems worth extracting in Phase 6. Takes ~2 minutes.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

If `--skip-audit` is passed, note in the run log that audit was skipped and proceed. Not recommended unless you ran Phase 2 in a previous session within the last 24h.
