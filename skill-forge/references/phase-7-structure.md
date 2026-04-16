# Phase 7 — Structure

**Goal:** Apply progressive disclosure to any oversized skill; tighten filePatterns; deduplicate cross-skill content.

**Depends on:** Phase 6 edits (skills now contain their final content).

## When to refactor a skill

A skill is a refactor candidate if ANY of these hold:

| Trigger | Action |
|---|---|
| Main SKILL.md > 2,000 tokens | Split into main + `references/*.md` |
| Main SKILL.md has > 30 numbered rules | Split by topic |
| Rules span > 4 distinct topics | Split by topic even if under size threshold |
| Multiple skills match the same files (intentional or not) | Consolidate or tighten patterns |

## Progressive disclosure refactor — the pattern

For a too-large SKILL.md:

### Step 1: Identify topic clusters
Group existing rules by theme. Aim for 4-8 clusters of roughly similar size. For a PySide6 skill, clusters might be: QSS styling, widget lifecycle, threading, packaging, signing, platform quirks, architecture.

### Step 2: Create references/ subdirectory
```bash
mkdir -p ~/.claude/skills/<skill>/references
```

### Step 3: Write one file per cluster
Each `references/<topic>.md`:
- Plain markdown, **no YAML frontmatter** (references are not skills themselves)
- Contains the full content for that topic
- Preserves original rule numbers (don't renumber; breaks cross-references)
- Starts with a one-line purpose statement

### Step 4: Rewrite the main SKILL.md
The new main SKILL.md should have:
1. Frontmatter (unchanged name/description/tools; tighten filePattern/bashPattern per below)
2. Brief intro (~5 lines)
3. **Pointer table** mapping topics to reference files:
   ```markdown
   | For work on… | Read this |
   |---|---|
   | QSS stylesheets, "invisible text" | `references/qss.md` |
   | Threading / QObject lifecycle | `references/threading-and-cleanup.md` |
   ```
4. **5-8 drop-everything critical rules inline** (see selection criteria below)
5. (Optional) A "Pairs with" section linking related user skills

Target size: ~1,500-2,500 tokens.

### Step 5: Verify rule coverage
```bash
# All rule numbers present exactly once (in either main or a reference)
bash ~/.claude/skills/skill-forge/scripts/audit.sh ~/.claude/skills/<skill>
```

## How to pick the inline rules (not just any 5-8)

A rule belongs inline in the main SKILL.md if **all three** hold:

1. **Violated often** — seen in production ≥3 times, or likely to be violated by anyone new to the domain
2. **Silent violation** — no error thrown; it corrupts behaviour until a user-visible bug appears
3. **1-2 line fix** once you know

Rules that are severe-but-rare go in references (low inline leverage). Rules that are common-but-obviously-wrong (compiler/linter would catch) also go in references — they don't need the inline real estate.

**Example from pyside6-desktop:** Rules 1, 9, 10, 16, 28, 39, 43 made it inline. Why each:
- Rule 1 (QSS `color:` on every inline setStyleSheet): dozens of violations per project, silent (invisible text in dark mode), 1-line fix
- Rule 9 (no signals from ThreadPoolExecutor): silent corruption under load, 3-line fix
- Rule 16 (PySide6 has no ARM64 Linux wheel): wastes an hour if you don't know, trivial to sidestep once known

Rule 34 (`--onefile` antivirus FPs) didn't make it inline despite being important — it's a *distribution* concern, not a *writing-code* concern, and the developer only hits it at ship time.

## How to cluster reference files

Good clusters are **question-shaped**: "If a developer asks X, they'd open file Y." Test each candidate cluster by rephrasing the name as a question:

- ✅ `qss.md` → "help with Qt stylesheets"
- ✅ `pyinstaller.md` → "how do I package this for Windows?"
- ✅ `signing-and-av.md` → "what do I need to know about code signing?"
- ❌ `misc.md` / `other.md` → "various things"… if you can't name the question, regroup
- ❌ `rules-20-to-25.md` → never name by numeric range

Aim for 4-8 clusters. Cluster sizes don't need to match — one file might have 13 rules (threading) and another 3 (widgets). Force-symmetrical clusters break Q&A-shape.

## After refactor — sanity checks

Before moving to Phase 8, answer these:

1. **First-read test:** Could someone new to the skill navigate from the pointer table to the right reference in under 10 seconds?
2. **Self-contained test:** Does each reference file make sense on its own, or does it assume you've just read another?
3. **Deletion test:** If you had to delete one reference file, would the main break, or just lose depth on one topic? (It should be the latter.)
4. **Inline triage test:** Could you delete any one of the inline rules and have the skill stop preventing a real production bug? (If yes, that rule shouldn't be inline.)

If any answer is "no", regroup before continuing.

## Bad-refactor anti-patterns

- **Dump file** — `misc.md`, `other.md`, `everything-else.md`. Means clustering failed; redo.
- **Micro-references** — 15 files each with 2-3 rules. Defeats the purpose; harder to navigate than a monolith. Merge related ones until each has ≥ 5 rules or a cohesive single-topic scope.
- **Too-large main** — inlined 20+ rules "to be comprehensive". That's just the monolith you started with. Cut it down.
- **Rule-range names** — `rules-1-to-8.md`. Topics, not numbers. If you can't describe the file by topic, the cluster is wrong.
- **Renumbered rules** — breaks every cross-reference in the skill, in user project memory, in git history. Keep the numbers exactly as they were.

## filePattern / bashPattern tightening

After Phase 6 may have added cross-project scope hints, re-verify patterns:

### Too-broad filePatterns to avoid
- `**/*.py` — matches every Python file anywhere
- `**/*.js` — every JavaScript file
- `**/*.ts` — every TypeScript file
- `**/*.md` — every markdown file

### Good filePatterns
- File extensions unique to a domain: `*.qss`, `*.spec`, `*.qplug`
- Directory-convention patterns: `**/pages/*.py`, `**/widgets/*.py`, `**/migrations/*.py`
- Named-file patterns: `**/main_window.py`, `**/BUILD.bat`, `**/pyproject.toml`

### Too-broad bashPatterns to avoid
- `python`, `pip`, `npm`, `git` — trigger on every shell
- Single-letter commands

### Good bashPatterns
- Domain-specific binaries: `pyinstaller`, `signtool`, `xcodebuild`, `qpdk`
- Specific subcommands: `gh workflow`, `npm run`, `cargo build`

## Cross-skill overlap resolution

If Phase 2 or Phase 8 detects that two skills trigger on identical filePatterns (outside intentional pairing):

1. Decide which skill is the primary home for that file type
2. Remove the duplicate pattern from the less-relevant skill
3. Add a "Pairs with X" note in the remaining skill mentioning the adjacent one

Do NOT merge skills solely because they overlap — that defeats scoping. Consolidate only if both skills' content is genuinely the same domain.

## Dedup checks

Grep for the same rule appearing in multiple skills:

```bash
# For every rule heading in skill A, check if same heading exists in skill B
grep -h "^## Rule" ~/.claude/skills/*/references/*.md ~/.claude/skills/*/SKILL.md | sort | uniq -c | sort -rn | awk '$1 > 1'
```

Duplicates should be consolidated to one home + cross-reference.

## Produce the structure log

Write to `<project>/.skill-forge/structure-changes.md`:

```markdown
# Structural Changes — <date>

## Refactored skills
### pyside6-desktop: 936-line monolith → 168-line main + 7 references
- Main retains 7 critical inline rules (1, 9, 10, 16, 28, 39, 43)
- 45 rules moved to references/{qss,widgets,threading,pyinstaller,platform-gotchas,signing-and-av,architecture}.md
- Token cost on invocation: 9,162 → 1,698 (5.4×)

## filePattern tightening
- pyside6-desktop: removed `**/*.py`, added Qt convention patterns
- mass-deploy-ux: narrowed `**/widgets/*.py` → `**/deploy_page.py`, `**/batch_*.py`

## Cross-skill dedup
- No duplicates found
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Structure cleaned — run QA?"
Header:   "Phase 7 → 8"
Options:
  - Label: `Run QA`
    Description: Phase 8: automated audit on all modified skills
  - Label: `Explain more`
    Description: Describe what Phase 8 checks, then re-ask
  - Label: `Stop (not recommended)`
    Description: Skips QA; edits preserved but unverified
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 8 runs audit.sh on every skill touched in this run. Verifies YAML validity, description length, rule coverage (no duplicates, no gaps), reference file existence, no orphan references, cross-skill filePattern overlap. Fixes trivial issues (typos, whitespace) inline; logs non-fatal warnings for deferral. Takes ~15 seconds.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

`--skip-structure` — if audit (Phase 2) showed all skills already well-sized. QA will still catch issues.
