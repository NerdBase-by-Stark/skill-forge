# Phase 1 — Discover

**Goal:** Understand the target project **as a full developer system** — skill library, hooks, MCP servers, local knowledge bases, language stack, sub-projects — not just the skill files under `~/.claude/skills/`. Output is a profile the other phases consume.

**Depends on:** nothing (entry phase).

## Steps

### 1.1 Identify the target project

- If `/skill-forge` was invoked with `--project=<path>`, use that path
- Otherwise use the current working directory
- Verify the directory exists and looks like a project (has at least one of: `CLAUDE.md`, `pyproject.toml`, `package.json`, `.git/`, `README.md`)
- If ambiguous, ask the user: `Run skill-forge against <cwd>? (or provide --project=<path>)`

#### 1.1a Sparse-root / monorepo detection

If the target root has `.git/` but NO `CLAUDE.md`/`README.md`/`package.json`/`pyproject.toml`/`Cargo.toml`/`go.mod` at root level, scan depth-1 for sub-project manifests. If ≥2 sub-projects each have their own manifest, this is a **heterogeneous monorepo** — a single project profile cannot honestly describe it.

Call `AskUserQuestion`:

```
Question: "Root has no top-level project markers. <N> sub-projects found. How to target?"
Header:   "Phase 1 — monorepo detected"
Options:
  - Label: `Run against whole monorepo`
    Description: One profile with sub_projects[] — Phase 5 streams cover all stacks
  - Label: `Target one sub-project`
    Description: Re-enter with --project=<path/to/sub>; skill-forge exits
  - Label: `Explain more`
    Description: Describe monorepo handling in detail, then re-ask
  - Label: `Stop`
    Description: Abort Phase 1
```

On **Run against whole monorepo**: populate `sub_projects[]` in profile (§1.7). On **Target one sub-project**: exit with instruction to re-invoke with a specific sub-path.

### 1.2 Read project signals

Read in parallel (single message with multiple Read calls):

- `<project>/CLAUDE.md` — project instructions (if present)
- `<project>/README.md` — first 100 lines
- Manifest files — stack + version:

| Stack | Manifest | Detection |
|---|---|---|
| JS/TS | `package.json` | dependencies + devDependencies |
| Python | `pyproject.toml` / `setup.py` / `requirements*.txt` | project.dependencies |
| Rust | `Cargo.toml` | [dependencies] |
| Go | `go.mod` | require blocks |
| **Lua / Q-SYS** | `*.rockspec` (LuaRocks) **and/or** presence of `*.qplug` files | `.qplug` → Q-SYS plugin stack; `.rockspec` → LuaRocks deps |
| **Q-SYS tooling** | `qpdk/` directory or `qpdk validate` in scripts | marks a Q-SYS dev-tooling sub-project |

- Python version marker (`__version__`) from `src/**/__init__.py`

Grep for:
- Dominant language (`.py`, `.ts`, `.lua`, `.qplug`, `.go`, `.rs` file counts)
- Frameworks (PySide6, React, FastAPI, etc.) by import lines
- Test framework (`pytest`, `jest`, `cargo test`, `qpdk validate`)
- CI config (`.github/workflows/*.yml`)

### 1.3 Inventory existing skills

List `~/.claude/skills/*/SKILL.md` and parse frontmatter for each. For each skill, capture:

- Name
- Description
- filePattern and bashPattern
- Size (lines, ~tokens)
- Whether it has a `references/` subdirectory

**Relevance algorithm (updated).** A skill is relevant to the target project if ANY of:

1. **Trigger match**: `filePattern` glob matches ≥1 file in the target
2. **Shell trigger**: `bashPattern` appears in any recent shell history or scripts under the project
3. **Keyword fallback (NEW)**: if the skill declares no filePattern AND no bashPattern (i.e., the skill is description-only — see TR004 in `scripts/audit.sh`), match description keywords against `tech_stack_tags` OR `profile_completeness.heavy_api_surface` (§1.6). Require ≥2 keyword overlaps to flag as relevant.
4. **Hook coverage (NEW, soft signal)**: if an active hook (§1.4a) matches a file pattern plausibly associated with the skill's topic (e.g., `qplug-validate.sh` on `*.qplug` + `qsys-plugin-patterns` skill about Q-SYS), note the relevance but record `match_reason: "hook-adjacent"` so it doesn't count toward Phase 3/5 targeting without corroboration.
5. **User assertion**: the user explicitly lists the skill as relevant

Record the reason a skill matched — downstream phases (2 audit, 5 research planning) treat a hook-adjacent match differently from a direct filePattern match.

#### 1.3a Inventory project-local skills (NEW)

Beyond `~/.claude/skills/`, skills can live under the project itself:

```bash
find <project> -path '*/.claude/skills/*/SKILL.md' -not -path '*/node_modules/*' -not -path '*/worktrees/*'
```

For each match, parse frontmatter the same way. Project-local skills are **highly stack-specific** — they're usually the best source of domain truth and should get priority in Phase 2 audit. Record under `project_local_skills[]` in the profile.

### 1.4 Check for prior skill-forge runs

- Does `<project>/docs/skill-research/` exist? List files and their mtimes.
- Does `<project>/.skill-forge/profile.json` exist? If so:
  - Check `profile_schema_version` — if missing or `< 2`, warn: *"Prior profile predates v0.2.2 schema; will regenerate with migration defaults for new fields."*
  - Warn the user the project has been run before; show last run date; offer to reuse research (`--skip-research`) or start fresh.

#### 1.4a Inventory active hooks (NEW)

Hooks run outside the skill system but shape what the system needs. A `PostToolUse` hook on `*.qplug` files that runs `qpdk validate` is load-bearing infrastructure — any skill advice about `.qplug` files must know this hook exists.

**CRITICAL SECURITY CONSTRAINT.** `~/.claude/settings.json` contains API tokens (e.g., `GITHUB_PERSONAL_ACCESS_TOKEN`). **Never Read the full file.** Use `jq` to extract structure only, never values that might be secrets.

```bash
# Extract hook structure only — never secret values
jq '.hooks | to_entries | map({
  event: .key,
  hooks: .value | map({
    matcher: .matcher,
    commands: (.hooks // []) | map(.command)
  })
})' ~/.claude/settings.json 2>/dev/null
```

Record under `active_hooks[]`. If `~/.claude/settings.json` doesn't exist or `.hooks` is null, record `"active_hooks": []`.

#### 1.4b Inventory available MCP servers (NEW)

MCP servers provide tools agents can call. For niche-stack research (Phase 5), a locally indexed codebase (e.g., `jcodemunch`) may answer a question that would otherwise cost an agent several web fetches.

**CRITICAL SECURITY CONSTRAINT.** `~/.claude.json` contains MCP server API keys and tokens. **Never Read the full file.** Extract server names only, never connection values.

```bash
# Names only — never connection details (may contain tokens)
jq -r '.mcpServers | keys[]' ~/.claude.json 2>/dev/null | sort
```

Also scan for project-local MCP config:
```bash
test -f "<project>/.mcp.json" && jq -r '.mcpServers | keys[]' "<project>/.mcp.json" 2>/dev/null
```

Record under `available_mcp_servers[]` — just names, never connection strings. This field feeds the Phase 5 research-agent brief (`references/research-agent-brief.md`) so agents know what local tools they can use before reaching for the web.

#### 1.4c Inventory local knowledge bases (NEW)

Local KBs (Neo4j/Qdrant/plain docs directories) may already answer questions that Phase 5 would otherwise research from the web. They're often paired with a `UserPromptSubmit` hook (e.g., `qsys-kb-search.sh` injects context when Q-SYS keywords appear).

Detect:

```bash
# KB-ish directories adjacent to ~/ai/ and under the project
for d in ~/ai/*knowledge* ~/ai/*-kb ~/ai/*ingestion "<project>"/*knowledge* "<project>"/*-kb; do
  [ -d "$d" ] && echo "$d"
done
```

For each candidate, record path + first README line (if any) as `hint`. Cross-reference against `active_hooks[]` — note whether any hook already surfaces this KB automatically. Record under `local_knowledge_bases[]`.

### 1.5 Read project memory

Look for memory files under `~/.claude/projects/<project-path-slug>/memory/`:
- Read `MEMORY.md` to understand what's already known
- Note any `feedback_*.md` files — user preferences that affect how this project is handled

### 1.6 Profile-completeness grep (catch stack misses before Phase 5)

A structured stack profile from reading `package.json` / `pyproject.toml` is not sufficient. Declared dependencies may be unused; actual imports may reveal stack components the profile missed. Before finalising the profile, run a **grep-based completeness check** — it's free, runs in ~30 seconds, and catches misses that would otherwise cascade into Phase 5 as uncovered research topics.

**Language dispatch** — pick the branch that matches the target's detected stack:

#### JS/TS

```bash
cd <project>
jq -r '.dependencies // {} | keys[]' package.json | while read pkg; do
  count=$(grep -rEc "from [\"']$pkg" src/ 2>/dev/null | awk -F: '{s+=$2} END {print s}')
  echo "$count $pkg"
done | sort -rn | awk '$1 > 10 {print}'
```

#### Python

```bash
cd <project>
pip list --format=freeze 2>/dev/null | cut -d= -f1 | while read pkg; do
  count=$(grep -rEc "^import ${pkg}($|[. ])|^from ${pkg}($|[. ])" src/ 2>/dev/null | awk -F: '{s+=$2} END {print s}')
  echo "$count $pkg"
done | sort -rn | awk '$1 > 10 {print}'
```

#### Lua / Q-SYS (NEW)

Q-SYS stacks don't declare most of their "dependencies" — the runtime API surface (`Controls.`, `Component.`, `Timer.`, `TcpSocket`, `SSH.`, `HttpClient.`) is built-in, not a package. For Lua/Q-SYS, measure **API surface usage** instead of package imports:

```bash
cd <project>

# Q-SYS built-in API namespaces — the actual "stack"
grep -rEoh --include="*.qplug" --include="*.lua" \
  "^[[:space:]]*(Controls|Component|Timer|TcpSocket|SSH|HttpClient|Design|System|Socket|Properties)\." \
  2>/dev/null | awk '{gsub(/^[ \t]+/,""); print}' | cut -d. -f1 | sort | uniq -c | sort -rn

# LuaRocks / require() dependencies — often sparse
grep -rEoh --include="*.qplug" --include="*.lua" \
  "require[[:space:]]*\(?[\"'][^\"']+[\"']" \
  2>/dev/null | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/" | sort | uniq -c | sort -rn
```

Top namespaces (e.g., `Controls` with 13,664 uses) become `heavy_api_surface` in the profile — the Lua/Q-SYS analogue of `heavy_imports_not_in_stack_tags`.

#### Fallback (unrecognised stack)

If none of the above dispatch branches match, skip the grep and record:

```json
"profile_completeness": {
  "grep_verified": false,
  "grep_skipped_reason": "unrecognised_stack: <detected-languages>"
}
```

**Cross-reference check.** Any package with >10 import sites (JS/Python) OR any API namespace with >50 use-sites (Lua/Q-SYS) that isn't represented in `tech_stack_tags` is a **flag** — add it to the profile and to Phase 5 stream planning.

Real examples:
- 2026-04-19 biltong-buddy: `zustand` had 40+ imports but was missing from tag list. Added via grep reconciliation.
- 2026-04-19 qsys-plugins: `Controls.` had 13,664 uses; a dependency-based completeness check would have reported empty. API-surface grep surfaced the actual Q-SYS stack.

**Output:** append to `profile.json` a `profile_completeness` block:

```json
"profile_completeness": {
  "grep_verified": true,
  "dispatch": "lua-qsys",
  "heavy_imports_not_in_stack_tags": [],
  "heavy_api_surface": [
    {"namespace": "Controls", "count": 13664},
    {"namespace": "SSH", "count": 889},
    {"namespace": "Timer", "count": 877}
  ],
  "new_tags_added_from_grep": ["qsys-plugin", "qsys-controls"]
}
```

If `heavy_imports_not_in_stack_tags` is non-empty after reconciliation, the profile is lying to downstream phases — resolve before proceeding.

### 1.7 Produce the profile

Write to `<project>/.skill-forge/profile.json`:

```json
{
  "profile_schema_version": 2,
  "project_root": "/home/alice/code/my-webapp",
  "project_name": "my-webapp",
  "languages": ["typescript", "python"],
  "frameworks": ["nextjs", "fastapi"],
  "tech_stack_tags": ["webapp", "fullstack"],
  "relevant_skills": [
    {
      "name": "vercel-react-best-practices",
      "tokens": 1800,
      "has_references": false,
      "match_reason": "filePattern"
    },
    {
      "name": "qsys-plugin-patterns",
      "tokens": 1022,
      "has_references": true,
      "match_reason": "keyword-fallback"
    }
  ],
  "project_local_skills": [
    {
      "path": "cisco-modular-plugin/.claude/skills/qsys-plugin-development",
      "name": "qsys-plugin-development"
    }
  ],
  "active_hooks": [
    {
      "event": "PostToolUse",
      "matcher": "Write|Edit",
      "commands": ["bash ~/.claude/hooks/qplug-validate.sh"]
    },
    {
      "event": "UserPromptSubmit",
      "matcher": "*",
      "commands": ["bash ~/.claude/hooks/qsys-kb-search.sh"]
    }
  ],
  "available_mcp_servers": ["jcodemunch", "jdocmunch", "open-brain"],
  "local_knowledge_bases": [
    {"path": "/home/alice/ai/qsys-kb", "hint": "Q-SYS Neo4j + Qdrant"},
    {"path": "/home/alice/ai/knowledge-base", "hint": "general"}
  ],
  "sub_projects": [
    {
      "path": "cisco-modular-plugin",
      "languages": ["lua"],
      "stack_tags": ["qsys-plugin", "cisco-roomos"]
    },
    {
      "path": "qpdk",
      "languages": ["python"],
      "stack_tags": ["qsys-tooling", "lua-embed"]
    }
  ],
  "memory_files": [
    "feedback_skill_progressive_disclosure.md"
  ],
  "profile_completeness": {
    "grep_verified": true,
    "dispatch": "lua-qsys",
    "heavy_imports_not_in_stack_tags": [],
    "heavy_api_surface": [
      {"namespace": "Controls", "count": 13664}
    ],
    "new_tags_added_from_grep": []
  },
  "last_run": null,
  "prior_research_count": 0
}
```

**Field semantics:**

| Field | Populated when | Consumed by |
|---|---|---|
| `profile_schema_version` | always — currently `2` | `--from-phase=N` compatibility check |
| `sub_projects[]` | §1.1a monorepo detection found ≥2 depth-1 manifests | Phase 5 stream planning |
| `project_local_skills[]` | §1.3a found `.claude/skills/` under project | Phase 2 audit (priority scope) |
| `active_hooks[]` | §1.4a | Phase 2 (redundancy check), Phase 5 research brief |
| `available_mcp_servers[]` | §1.4b | Phase 5 research-agent brief |
| `local_knowledge_bases[]` | §1.4c | Phase 5 (don't redo web research if a local KB covers it) |
| `profile_completeness.heavy_api_surface` | §1.6 Lua/Q-SYS dispatch | Phase 1.3 keyword-fallback relevance |

**Migration from schema v1.** If a prior-run profile has no `profile_schema_version` field, treat it as v1 and populate the new fields with empty defaults (`[]` or `false`) before writing v2 back. Warn the user in the phase summary: *"Migrated profile from v1 → v2; new fields populated with defaults."*

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

> Phase 2 runs scripts/audit.sh on your existing skills — checks YAML validity, main SKILL.md size (flags >500 lines per 2026 Anthropic guidance), description length (≤300 chars), rule coverage for progressive-disclosure skills, cross-skill filePattern overlap, trigger presence (TR004), and orphan reference files. Produces audit-report.md. Takes ~10 seconds. No edits made.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

If `--profile=<path-to-existing-profile.json>` is passed, load it and skip discovery. Useful for repeated runs in the same session.

On load, check `profile_schema_version`. If `< 2`, run the schema migration inline and rewrite before proceeding.
