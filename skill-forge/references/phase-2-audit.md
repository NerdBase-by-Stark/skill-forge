# Phase 2 — Audit

**Goal:** Catch existing problems in the project's relevant skills before any research happens. Size bloat, trigger over-eagerness, cross-skill overlap, stale content.

**Depends on:** Phase 1 profile.

## Steps

### 2.0 Determine audit scope (deterministic, not hand-picked)

The audit scope must be **deterministic** — not a human-curated subset of "skills I think are relevant." Curation misses things. A 2026-04-19 cross-model run demonstrated this: curating 17 skills missed a real defect (`gh-cli` description 4 chars over budget) that a 20-skill scope caught. The fix is process, not model-count.

**Deterministic scope rule:** audit every user-owned skill in `~/.claude/skills/` whose filePattern matches at least one file in the target project, OR whose bashPattern appears in project scripts, OR that is explicitly listed in `profile.json` under `relevant_skills`, **PLUS every project-local skill from `profile.json`'s `project_local_skills`** (project-local skills are the most stack-specific and get priority). No manual "this probably isn't relevant, skip it." If in doubt, include.

**Exclude only** upstream skills the user cannot edit. *Ownership split* = the boundary between skills the user authored/owns (editable by this pipeline) and skills installed from upstream sources they don't maintain (writing-skills, skill-creator, plugin-dev:*, vendor plugins). Upstream skills appear in FYI-only reports and never in edit proposals, but audits of them are informational.

**Write the scope list to `.skill-forge/audit-scope.txt`** — format: one absolute skill-directory path per line (the directory containing SKILL.md), `#` lines are comments, no trailing whitespace. Subsequent runs diff this file to spot scope changes:

```bash
# if a prior run's scope exists, show what changed before overwriting
[ -f .skill-forge/audit-scope.txt ] && cp .skill-forge/audit-scope.txt .skill-forge/audit-scope.prev.txt
# ... write the new audit-scope.txt ...
[ -f .skill-forge/audit-scope.prev.txt ] && diff .skill-forge/audit-scope.prev.txt .skill-forge/audit-scope.txt || true
```

### 2.1 Run the audit script

Resolve the script path first — user-level install is the default, but INSTALL.md documents project-local installs too:

```bash
AUDIT=~/.claude/skills/skill-forge/scripts/audit.sh
[ -f "$AUDIT" ] || AUDIT=<project>/.claude/skills/skill-forge/scripts/audit.sh
```

Run it twice — text for the human-readable log, JSON for verdict derivation:

```bash
bash "$AUDIT" $(grep -v '^#' .skill-forge/audit-scope.txt | tr '\n' ' ')
bash "$AUDIT" --format json $(grep -v '^#' .skill-forge/audit-scope.txt | tr '\n' ' ') > .skill-forge/audit-findings.json
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

### 2.1b Fold in empirical telemetry (if the profile has it)

If `profile.json`'s `usage_telemetry` is non-null, extract per-skill facts — these are pre-computed verdicts from a stronger scan; transcribe them, don't re-judge:

```bash
jq -r --arg s "<skill-name>" '.by_skill[$s] | {criteria_failures, fire_count_estimate, invocation_count_estimate}' <telemetry-path>
```

- `criteria_failures` map to verdicts via the fixed lookup in §2.5 (e.g. `frontmatter_valid` → Defect: YAML; `trigger_specificity` → Defect: trigger; `description_*` → Defect: description).
- **Over-matching descriptions:** `fire_count_estimate ≥ 20` with `invocation_count_estimate == 0` = the description over-matches the catalog without producing use → Defect: description. (This replaces any vague "triggers false-positives per memory/logs" judgment — the numbers are the evidence.)
- **Never-used skills:** `fire_count_estimate ≥ 10` AND `invocation_count_estimate == 0` AND skill unmodified > 60 days → verdict **Candidate: archive (unused)** (§2.5).

No telemetry → skip this step; the audit still works, it just relies on the script + judgment alone.

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

Most of this is now scripted — audit.sh checks length (FM003), when-NOT-to-use presence (FM004), third-person voice (FM005), always-invoke language (FM006), and destructive-keywords-without-disable-model-invocation (FM007). Read those findings from the JSON; do not re-derive them.

The two judgment calls that remain for the model:
- Is the description **specific** enough to prevent false-positive triggering? (`Python stuff` = bad. `PySide6 desktop app rules, QSS gotchas, PyInstaller packaging` = good)
- Is the description **accurate** — does it match what the skill's body actually covers?

### 2.5 Classify every skill with a Verdict

For each in-scope skill, assign exactly one verdict. This drives Phase 4/6 candidate lists — **only "Defect" verdicts become proposed changes**. "Fits — leave alone" skills are explicitly excluded from the approval gate so the list stays honest and short.

**Derive verdicts from `.skill-forge/audit-findings.json` via this fixed mapping first** — model judgment covers only what the script can't check (stale content, description vagueness/accuracy, intentionality of overlap):

| JSON `rule_id` | → Verdict |
|---|---|
| FM001, FM002 | Defect: YAML |
| FM003, FM004, FM005, FM006 | Defect: description |
| TR001, TR002 | Defect: trigger |
| TR003 (cross-skill) | Defect: overlap — unless an explicit "Pairs with" cross-ref makes it intentional (judgment) |
| RI001, RI002 | Defect: broken refs |
| SS001 | Borderline: size |
| SS002-SS007, RI003, TR004, FM007 | note in report; not verdict-changing on their own |
| no findings for the skill | ✓ Fits — leave alone (unless §2.2 stale-content or §2.1b telemetry says otherwise) |

| Verdict | Criteria |
|---|---|
| **✓ Fits — leave alone** | No verdict-mapped findings, description specific+accurate, no stale content, no unintentional overlap. **No change is a success — do not rewrite.** |
| **Defect: YAML** | Frontmatter fails to parse, or missing required field |
| **Defect: description** | >300 chars, vague (`Python stuff`), missing when-NOT-to-use clause, wrong person/voice, always-invoke language, or telemetry shows over-matching (fire ≥20, invocations 0 — §2.1b) |
| **Defect: trigger** | Overly-broad filePattern (`**/*.py`) or bashPattern (`python`, `git`) |
| **Defect: stale** | Year marker older than 12 months, version claim behind current stable, deprecated API |
| **Defect: overlap** | Unintentional filePattern overlap with another skill + no "Pairs with" cross-ref |
| **Defect: broken refs** | Main mentions `references/X.md` that doesn't exist, or dead external URL |
| **Borderline: size** | Main SKILL.md > 500 lines (SS001 — the one split metric); candidate for Phase 7 refactor only if rules cleanly cluster |
| **Borderline: content gap** | Research in Phase 5 may surface additions; revisit in Phase 6 |
| **Candidate: archive (unused)** | Telemetry-only verdict (§2.1b): fired ≥10× in the catalog, invoked 0 times, unmodified > 60 days. Proposes a consent-gated move to `~/.claude/skills-archive/<name>/` at the Phase 3→4 gate (restore = move it back). Never fires without telemetry. |

**"Fits — leave alone" is the default.** If in doubt, mark it Fits. Agents have a strong bias toward finding things to change; counter it explicitly. A rewording that's "slightly shorter" or "slightly clearer" is NOT a defect.

**Important scope clarification — Verdict affects EDITS only, not RESEARCH.** A "✓ Fits — leave alone" verdict excludes the skill from the Phase 4 edit candidate list. It does **not** exclude it from Phase 5 research. Research streams are driven by the project's tech stack + pain points, not by whether the skill looks broken today. A healthy skill can still acquire a newly verified rule from research; that rule becomes a Phase 6 *addition* proposal (existing wording untouched), which goes through the approval gate like any other change. Do not skip research on a skill because it passed audit.

### 2.6 Produce audit report

Write to `<project>/.skill-forge/audit-report.md`:

```markdown
# Skill Audit Report — <project> — <date>

## Size audit + verdict
| Skill | Main lines | Refs | YAML | Trigger | Stale | Overlap | **Verdict** |
|---|---|---|---|---|---|---|---|
| pyside6-desktop | 168 | 7 | ✓ | ✓ | ✓ | none | **✓ Fits — leave alone** |
| network-device-discovery | 936 | 0 | ✓ | ✓ | ✓ | none | **Borderline: size** |
| python-packaging | 132 | 0 | ✓ | ✓ | ✓ | none | **✓ Fits — leave alone** |
| ios-capacitor-build | 287 | 2 | **ERROR (FM001)** | ✓ | ✓ | none | **Defect: YAML** |

**Healthy-library check:** if every row is "✓ Fits — leave alone", the library needs no changes. Report that to the user and offer early exit at the Phase 3→4 gate.

## Trigger precision audit

**filePattern uses gitignore semantics (not shell glob).** Key rules:
- `*.py` matches ONLY top-level Python files (not recursive) — patterns without `/` match at the current directory level per gitignore.
- `**/*.py` matches Python files anywhere in the tree (recursive).
- Patterns with `/` anchor to specific paths.

Audit flags (rule IDs match `audit.sh` exactly — the script is canonical):
- **TR001 — recursive-wildcard overreach:** `**/*.py`, `**/*.js`, `**/*.ts`, `**/*.md` — matches entire project. Rarely appropriate; replace with directory-convention patterns (`**/widgets/*.py`) or named-file patterns (`**/pyproject.toml`).
- **TR002 — bashPattern too common:** `python`, `pip`, `npm`, `git` — fires on every shell session. Narrow to specific subcommands.
- **TR003 — cross-skill filePattern overlap:** two skills declare the identical pattern; Defect: overlap unless explicitly paired.
- **TR004 — no triggers declared:** empty filePattern + empty bashPattern = command-invoked-only skill (like skill-forge itself). This is **intentional** for slash-command skills; not a defect — confirm the choice, don't "fix" it.

Do **not** flag `*.py` as too-broad by default — per gitignore semantics it's scoped to top-level. Only flag if the top-level layout means it still matches many files.

## Cross-skill overlap
<matrix of which skills match the same files — if cells > 1 skill, list them>

## Stale content flags
<list rules/sections with year markers > 12 months old or deprecated references>

## Recommendations
1. <concrete action items, ordered by impact>
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then — **in interactive mode** — call `AskUserQuestion` as below (never a text prompt — users skim and miss them); in autopilot this is an auto-advance transition (SKILL.md mode table), so print the summary and continue to Phase 3:

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
