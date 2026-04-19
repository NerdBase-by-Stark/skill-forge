# Phase 1 — Discover

**Goal:** Understand the target project **as a full developer system** — skill library, hooks, MCP servers, local knowledge bases, language stack, sub-projects — not just the skill files under `~/.claude/skills/`. Output is a profile the other phases consume.

**Depends on:** nothing (entry phase).

## Steps

### 1.1 Identify the target project

- If `/skill-forge` was invoked with `--project=<path>`, use that path
- Otherwise use the current working directory
- Verify the directory exists and looks like a project (has `.git/`, a top-level `CLAUDE.md`/`README.md`, or a manifest file)
- **Monorepo / sparse root:** if the root has no top-level manifest but `.git/` exists and depth-1 sub-directories each have their own manifests (`package.json`, `pyproject.toml`, `CLAUDE.md`, etc.), profile the whole monorepo — populate `sub_projects[]` (§1.7) so Phase 5 stream planning knows each stack. Do not ask the user which sub-project to target; skill-forge can handle heterogeneous stacks in one pass.

### 1.2 Read project signals

Read relevant manifests, CLAUDE.md, README, and scan the dominant languages.

Stacks skill-forge has first-class support for:

| Stack | Markers |
|---|---|
| JS/TS | `package.json`, `tsconfig.json` |
| Python | `pyproject.toml`, `setup.py`, `requirements*.txt` |
| Rust | `Cargo.toml` |
| Go | `go.mod` |
| **Lua / Q-SYS** | `*.qplug` files, `*.rockspec`, or a `qpdk` tool directory |

If the target is a stack not listed (Elixir, Haskell, Zig, commercial-AV platform, etc.), profile it anyway — the agent can identify languages from file extensions and imports. Note the stack in `tech_stack_tags` so later phases can adapt.

### 1.3 Inventory existing skills

List `~/.claude/skills/*/SKILL.md` and parse frontmatter (name, description, filePattern, bashPattern, size, references/).

**Also check for project-local skills** under `<project>/.claude/skills/*/SKILL.md` and any nested `<project>/*/.claude/skills/*/SKILL.md` (common in monorepos). Project-local skills are usually the most stack-specific source of truth and get priority in Phase 2 audit.

**Relevance algorithm.** A skill is relevant to the target project if ANY of:

1. Its `filePattern` matches ≥1 file in the target
2. Its `bashPattern` appears in any script or recent shell history under the project
3. The skill declares no `filePattern` and no `bashPattern` (description-only — see TR004) but its description/keywords clearly overlap the project's stack or the actually-used API surface from §1.6
4. The user explicitly lists it as relevant

Record `match_reason` on each relevant skill so downstream phases know whether the match was a hard trigger or a soft keyword overlap.

### 1.4 Inventory the developer surface (hooks, MCPs, KBs)

Skills are not the whole story. A Claude Code environment usually includes:

- **Hooks** — declared in `~/.claude/settings.json`. A `PostToolUse` hook that validates `.qplug` files or a `UserPromptSubmit` hook that injects KB context on keyword matches is load-bearing infrastructure that later phases need to know about (Phase 2 audit should not flag a skill as redundant without also considering adjacent hooks; Phase 5 research agents should not duplicate work a hook already enforces).
- **MCP servers** — declared in `~/.claude.json` and `<project>/.mcp.json`. A local code-index MCP (e.g., `jcodemunch`) that already indexes the target repo can answer Phase 5 research questions much faster and cheaper than web search. The Phase 5 research-agent brief pulls from this list.
- **Local knowledge bases** — Neo4j/Qdrant/plain-docs directories (often under `~/ai/`) that feed KB-search hooks or MCPs. If the user's environment has already ingested the domain knowledge, Phase 5 should use it rather than re-research from the web.

**SECURITY — HARD CONSTRAINT.** `~/.claude/settings.json` and `~/.claude.json` contain API tokens (`GITHUB_PERSONAL_ACCESS_TOKEN`, `N8N_API_KEY`, MCP connection strings, etc.). **Do not Read these files in full.** Use `jq` to extract only the structural fields you need (hook events + matchers + command strings; MCP server *names* only) and never dump values that could be secret. If unsure whether a field is safe, don't include it.

Record what you find under `active_hooks[]`, `available_mcp_servers[]`, and `local_knowledge_bases[]` in the profile. If any of these are empty for this environment, the fields are empty — that's fine.

### 1.5 Check for prior runs and read project memory

- `<project>/docs/skill-research/` — list existing research docs with mtimes (skip-research decision data)
- `<project>/.skill-forge/profile.json` — if present from a prior run, reuse what's still valid and regenerate the rest. Don't agonise over schema migration; just refresh anything that looks outdated or missing.
- `~/.claude/projects/<project-slug>/memory/MEMORY.md` — load prior context; note any `feedback_*.md` entries that should shape later phases.

### 1.6 Profile-completeness check

A manifest-based stack profile is often incomplete. Declared dependencies may be unused; what's *actually used* reveals what the skills need to cover. Before finalising the profile, verify the stack by sampling actual code — don't trust `package.json`/`pyproject.toml` alone.

For each stack the agent can do this by whatever method fits:

- **JS/TS / Python / Rust / Go:** count imports of declared deps — anything with heavy usage that isn't tagged is a gap to add
- **Lua / Q-SYS (or any stack where the "dependencies" are built-in runtime APIs):** count the API surface actually used — Q-SYS plugins live inside `Controls.`, `Component.`, `Timer.`, `TcpSocket`, `SSH.`, `HttpClient.` etc. None of those are declared in a manifest; they are the stack. Sample the codebase to find the namespaces that matter for this project and record them as `heavy_api_surface` so later phases plan research around what's used, not what's declared.
- **Unrecognised stack:** scan files, identify the languages, note the top symbols/patterns the codebase actually uses. Record the method used in `profile_completeness.dispatch` so the result is auditable.

The goal is catching "there's a stack component nothing covers" *before* Phase 5 wastes a research stream on dead deps. Real example: 2026-04-19 biltong-buddy run — a framework-detection profile missed `zustand` (40+ imports). A second example from the 2026-04-19 qsys-plugins dry-run: dependency-based completeness would have reported empty for a project where `Controls.` has 13,664 uses, because none of that is a declared package.

If any heavy-usage component is not already in `tech_stack_tags`, add it and note in `profile_completeness.new_tags_added_from_grep`.

### 1.7 Produce the profile

Write to `<project>/.skill-forge/profile.json`. Target schema (agent fills what applies to this project; empty arrays are fine):

```json
{
  "project_root": "/home/alice/code/my-webapp",
  "project_name": "my-webapp",
  "languages": ["typescript", "python"],
  "frameworks": ["nextjs", "fastapi"],
  "tech_stack_tags": ["webapp", "fullstack"],
  "relevant_skills": [
    {"name": "vercel-react-best-practices", "match_reason": "filePattern"},
    {"name": "qsys-plugin-patterns", "match_reason": "keyword-fallback"}
  ],
  "project_local_skills": [],
  "active_hooks": [
    {"event": "PostToolUse", "matcher": "Write|Edit", "commands": ["bash ~/.claude/hooks/qplug-validate.sh"]}
  ],
  "available_mcp_servers": ["jcodemunch", "jdocmunch", "open-brain"],
  "local_knowledge_bases": [
    {"path": "~/ai/qsys-kb", "hint": "Q-SYS Neo4j + Qdrant"}
  ],
  "sub_projects": [],
  "memory_files": [],
  "profile_completeness": {
    "verified": true,
    "dispatch": "lua-qsys",
    "heavy_api_surface": [{"namespace": "Controls", "count": 13664}],
    "new_tags_added": []
  },
  "last_run": null,
  "prior_research_count": 0
}
```

Profile is the agent's honest snapshot of what's here — not every field will be populated on every project. Missing fields are missing; don't invent data.

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`**:

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

### If user picks "Explain more"

> Phase 2 runs scripts/audit.sh on your existing skills — YAML validity, main SKILL.md size (≤500 lines per 2026 Anthropic guidance), description length, rule coverage for progressive-disclosure skills, cross-skill filePattern overlap, trigger presence (TR004), orphan reference files. Produces audit-report.md. ~10 seconds. No edits.

Never loop "Explain more" more than twice — default to "Stop" and ask what they actually want.

## Skipping this phase

If `--profile=<path-to-existing-profile.json>` is passed, load it and skip discovery. If the loaded profile looks stale or incomplete (missing fields, old mtime, project structure has changed), just regenerate it.
