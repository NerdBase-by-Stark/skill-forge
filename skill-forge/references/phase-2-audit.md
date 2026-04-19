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

### 2.5 Classify every skill with a Verdict

For each in-scope skill, assign exactly one verdict. This drives Phase 4/6 candidate lists — **only "Defect" verdicts become proposed changes**. "Fits — leave alone" skills are explicitly excluded from the approval gate so the list stays honest and short.

| Verdict | Criteria |
|---|---|
| **✓ Fits — leave alone** | YAML valid, description ≤300 chars and specific, triggers correctly scoped, under token budget, no stale content, no unintentional overlap. **No change is a success — do not rewrite.** |
| **Defect: YAML** | Frontmatter fails to parse, or missing required field |
| **Defect: description** | >300 chars, vague (`Python stuff`), or triggers false-positives per memory/logs |
| **Defect: trigger** | Overly-broad filePattern (`**/*.py`) or bashPattern (`python`, `git`) |
| **Defect: stale** | Year marker older than 12 months, version claim behind current stable, deprecated API |
| **Defect: overlap** | Unintentional filePattern overlap with another skill + no "Pairs with" cross-ref |
| **Defect: broken refs** | Main mentions `references/X.md` that doesn't exist, or dead external URL |
| **Borderline: size** | >2,000 tokens; candidate for Phase 7 refactor only if rules cleanly cluster |
| **Borderline: content gap** | Research in Phase 5 may surface additions; revisit in Phase 6 |

**"Fits — leave alone" is the default.** If in doubt, mark it Fits. Agents have a strong bias toward finding things to change; counter it explicitly. A rewording that's "slightly shorter" or "slightly clearer" is NOT a defect.

**Important scope clarification — Verdict affects EDITS only, not RESEARCH.** A "✓ Fits — leave alone" verdict excludes the skill from the Phase 4 edit candidate list. It does **not** exclude it from Phase 5 research. Research streams are driven by the project's tech stack + pain points, not by whether the skill looks broken today. A healthy skill can still acquire a newly verified rule from research; that rule becomes a Phase 6 *addition* proposal (existing wording untouched), which goes through the approval gate like any other change. Do not skip research on a skill because it passed audit.

### 2.6 Produce audit report

Write to `<project>/.skill-forge/audit-report.md`:

```markdown
# Skill Audit Report — <project> — <date>

## Size audit + verdict
| Skill | Main tokens | Refs | YAML | Trigger | Stale | Overlap | **Verdict** |
|---|---|---|---|---|---|---|---|
| pyside6-desktop | 1,698 | 7 | ✓ | ✓ | ✓ | none | **✓ Fits — leave alone** |
| network-device-discovery | 8,631 | 0 | ✓ | ✓ | ✓ | none | **Borderline: size** |
| python-packaging | 1,320 | 0 | ✓ | ✓ | ✓ | none | **✓ Fits — leave alone** |
| ios-capacitor-build | 2,821 | 2 | **ERROR (E1)** | ✓ | ✓ | none | **Defect: YAML** |

**Healthy-library check:** if every row is "✓ Fits — leave alone", the library needs no changes. Report that to the user and offer early exit at the Phase 3→4 gate.

## Trigger precision audit

**filePattern uses gitignore semantics (not shell glob).** Key rules:
- `*.py` matches ONLY top-level Python files (not recursive) — patterns without `/` match at the current directory level per gitignore.
- `**/*.py` matches Python files anywhere in the tree (recursive).
- Patterns with `/` anchor to specific paths.

Audit flags:
- **TR001 — recursive-wildcard overreach:** `**/*.py`, `**/*.js`, `**/*.ts`, `**/*.md` — matches entire project. Rarely appropriate; replace with directory-convention patterns (`**/widgets/*.py`) or named-file patterns (`**/pyproject.toml`).
- **TR002 — bashPattern too common:** `python`, `pip`, `npm`, `git` — fires on every shell session. Narrow to specific subcommands.
- **TR003 — empty filePattern + empty bashPattern:** command-invoked-only skill (like skill-forge itself). This is **intentional** for slash-command skills; not a defect.

Do **not** flag `*.py` as too-broad by default — per gitignore semantics it's scoped to top-level. Only flag if the top-level layout means it still matches many files.

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
