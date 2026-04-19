# Phase 1 — Discover

**Goal:** Understand the target project well enough to make good decisions in every later phase. Output is a profile the other phases consume.

**Depends on:** nothing (entry phase).

## Steps

### 1.1 Identify the target project

- If `/skill-forge` was invoked with `--project=<path>`, use that path
- Otherwise use the current working directory
- Verify the directory exists and looks like a project (has at least one of: `CLAUDE.md`, `pyproject.toml`, `package.json`, `.git/`, `README.md`)
- If ambiguous, ask the user: `Run skill-forge against <cwd>? (or provide --project=<path>)`

### 1.2 Read project signals

Read in parallel (single message with multiple Read calls):

- `<project>/CLAUDE.md` — project instructions (if present)
- `<project>/README.md` — first 100 lines
- `<project>/pyproject.toml` / `package.json` / `Cargo.toml` — stack + version
- `<project>/src/**/__init__.py` — Python version marker (`__version__`)

Grep for:
- Dominant language (`.py`, `.ts`, `.go`, `.rs` file counts)
- Frameworks (PySide6, React, FastAPI, etc.) by import lines
- Test framework (`pytest`, `jest`, `cargo test`)
- CI config (`.github/workflows/*.yml`)

### 1.3 Inventory existing skills

List `~/.claude/skills/*/SKILL.md` and parse frontmatter for each. For each skill, capture:

- Name
- Description
- filePattern and bashPattern
- Size (lines, ~tokens)
- Whether it has a `references/` subdirectory
- Whether it matches files in the target project (glob-test each filePattern against the project)

**Relevant skills** = skills whose filePattern matches ≥1 file in the target, OR whose bashPattern appears in any recent shell history or scripts under the project, OR the user lists it as relevant.

### 1.4 Check for prior skill-forge runs

- Does `<project>/docs/skill-research/` exist? List files and their mtimes.
- Does `<project>/.skill-forge/profile.json` exist? If so, warn the user the project has been run before; show last run date; offer to reuse research (`--skip-research`) or start fresh.

### 1.5 Read project memory

Look for memory files under `~/.claude/projects/<project-path-slug>/memory/`:
- Read `MEMORY.md` to understand what's already known
- Note any `feedback_*.md` files — user preferences that affect how this project is handled

### 1.5 Profile-completeness grep (catch stack misses before Phase 5)

A structured stack profile from reading `package.json` / `pyproject.toml` is not sufficient. Declared dependencies may be unused; actual imports may reveal stack components the profile missed. Before finalising the profile, run a **grep-based completeness check** — it's free, runs in ~30 seconds, and catches misses that would otherwise cascade into Phase 5 as uncovered research topics.

For JS/TS projects:

```bash
cd <project>
jq -r '.dependencies // {} | keys[]' package.json | while read pkg; do
  count=$(grep -rEc "from [\"']$pkg" src/ 2>/dev/null | awk -F: '{s+=$2} END {print s}')
  echo "$count $pkg"
done | sort -rn | awk '$1 > 10 {print}'
```

For Python projects: equivalent with `pip list` + `grep -rEc "^import $pkg|^from $pkg" src/`.

**Cross-reference against the profile's `tech_stack_tags`.** Any package with >10 import sites that isn't represented in the profile's stack is a **flag** — add it to the profile and to Phase 5 stream planning.

Real example (2026-04-19 biltong-buddy run): a package.json-derived profile missed `zustand` entirely because the tag list was based on framework detection. Grep showed 40+ imports across `ProtectedRoute.tsx`, `OnboardingChecklist.tsx`, several pages. Major stack component missed. Adding it to the profile prevented a downstream Phase 5 coverage gap.

**Output:** append to `profile.json` a `profile_completeness` block:

```json
"profile_completeness": {
  "grep_verified": true,
  "heavy_imports_not_in_stack_tags": [],
  "new_tags_added_from_grep": ["zustand", "dexie"]
}
```

If `heavy_imports_not_in_stack_tags` is non-empty after reconciliation, the profile is lying to downstream phases — resolve before proceeding.

### 1.6 Produce the profile

Write to `<project>/.skill-forge/profile.json`:

```json
{
  "project_root": "/home/alice/code/my-webapp",
  "project_name": "my-webapp",
  "languages": ["typescript", "python"],
  "frameworks": ["nextjs", "fastapi"],
  "tech_stack_tags": ["webapp", "fullstack"],
  "relevant_skills": [
    {"name": "vercel-react-best-practices", "tokens": 1800, "has_references": false},
    {"name": "python-packaging", "tokens": 1320, "has_references": false}
  ],
  "memory_files": [
    "feedback_skill_progressive_disclosure.md"
  ],
  "last_run": null,
  "prior_research_count": 0
}
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Discovery complete — next step?"
Header:   "Phase 1 → 2"
Options:
  - Label: `Audit existing skills`
    Description: Check size, overlap, description quality, rule coverage
  - Label: `Explain more`
    Description: Describe what Phase 2 does in detail, then re-ask
  - Label: `Stop`
    Description: Exit; profile saved for later --from-phase resume
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 2 runs scripts/audit.sh on your existing skills — checks YAML validity, main SKILL.md size (flags >2.5k tokens), description length (≤300 chars), rule coverage for progressive-disclosure skills, cross-skill filePattern overlap, and orphan reference files. Produces audit-report.md. Takes ~10 seconds. No edits made.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

If `--profile=<path-to-existing-profile.json>` is passed, load it and skip discovery. Useful for repeated runs in the same session.
