# Changelog

All notable changes to this project will be documented in this file. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [0.2.2] — 2026-04-19

### Theme
**System-aware Phase 1.** Triggered by a Q-SYS-plugins dry-run (Lua monorepo, completely different stack from prior biltong run) that surfaced 12 gaps centred on a single root cause: Phase 1 only inventoried `~/.claude/skills/`, ignoring the rest of the developer surface (hooks, MCP servers, local knowledge bases, non-JS/Python stacks, sparse-root monorepos, project-local skills). Same philosophy as 0.2.1 — process fixes over new models.

### Added
- **TR004 audit rule** in `scripts/audit.sh` — WARNING when a skill declares no `filePattern` AND no `bashPattern` (description-only discovery). Fires on all 6 triggerless skills in a typical user library on first run; author decides per-skill whether to add triggers or acknowledge intent. Shipped without escape hatch; retroactive only if false positives surface. (Closes G4/G5.)
- **Phase 1.1a sparse-root / monorepo detection.** If root has `.git/` but no top-level manifest, depth-1 scan; if ≥2 sub-projects each have their own manifest, `AskUserQuestion` lets the user target the whole monorepo (with `sub_projects[]` in profile) or re-enter against one sub-project. (Closes G1/G7.)
- **Phase 1.2 Lua / Q-SYS stack detection.** New manifest table row recognises `*.qplug`, `*.rockspec`, and `qpdk` as Q-SYS markers. (Closes G2.)
- **Phase 1.3 keyword-fallback relevance algorithm.** Skills with no filePattern/bashPattern match via description-keyword overlap against `tech_stack_tags` or `heavy_api_surface`. Hook-adjacent matches marked with `match_reason: "hook-adjacent"` so they don't drive Phase 3/5 targeting alone.
- **Phase 1.3a project-local skills inventory** — `find <project> -path '*/.claude/skills/*/SKILL.md'`, adds them to profile's `project_local_skills[]`. Project-local skills get priority in Phase 2 audit. (Closes G6.)
- **Phase 1.4a active-hooks inventory** — extracts `~/.claude/settings.json` hook structure via `jq` (keys only, never values — contains secrets). Adds `active_hooks[]` to profile. (Closes G12.)
- **Phase 1.4b MCP-server inventory** — names-only extraction from `~/.claude.json` (connection values may be tokens, never read). Adds `available_mcp_servers[]` to profile. (Closes G13.)
- **Phase 1.4c local-knowledge-base inventory** — scans `~/ai/*knowledge*`, `~/ai/*-kb`, `~/ai/*ingestion`, project-local equivalents. Adds `local_knowledge_bases[]` to profile. (Closes G14.)
- **Phase 1.6 language dispatch for profile-completeness grep** — JS/TS branch (existing), Python branch (existing), **new Lua/Q-SYS branch** measures API-surface usage (`Controls.`, `Component.`, `Timer.`, `TcpSocket`, `SSH.`, `HttpClient.`) since runtime namespaces aren't declared deps, plus `require()` for LuaRocks. Unrecognised-stack fallback records `grep_skipped_reason` instead of silently pretending verification. (Closes G3.)
- **Research-agent brief MCP awareness** (`references/research-agent-brief.md`). New "Check local tools FIRST" section instructs agents to query `jcodemunch` / `jdocmunch` / `open-brain` / etc. and local KBs before web research. An MCP-derived answer is still cited (MCP name + repo/doc path). (Closes G13 downstream.)
- **Phase 3 niche-stack guidance** (`references/phase-3-find-candidates.md`). New "When no candidates are install-worthy" section documents that reputation-by-installs *inverts* for niche / commercial-AV stacks (Q-SYS, Crestron, Extron, BSS, etc.); expert-authored skills are often the low-install ones. Short-circuit rule prevents wasted agent time. Alternative gap-fillers surfaced (hook authorship, MCP wrapper) — out of skill-forge scope but noted. (Closes G8/G9.)

### Changed
- **`profile.json` schema v2.** New `profile_schema_version: 2` field. Migration from v1 populates new fields (`active_hooks`, `available_mcp_servers`, `local_knowledge_bases`, `project_local_skills`, `sub_projects`, `profile_completeness.heavy_api_surface`) with safe defaults. `--from-phase=N` with an old profile triggers inline migration.
- **Phase 1 reference file renumbered** — fixed a pre-existing duplicate-section bug where two `§1.5` headings coexisted. Now §1.5 (Read project memory) and §1.6 (Profile-completeness grep) are distinct.
- **`SKILL.md` phase table** Phase 1 summary updated to reflect full-system profiling.

### Security
- `~/.claude/settings.json` and `~/.claude.json` are called out in the Phase 1 reference as DO-NOT-READ files (contain API tokens). Hook and MCP inventories use `jq` to extract structure only, never values.

### Known limitations
- Hook↔skill redundancy detection is not yet automated. Phase 2 audit surfaces `active_hooks` in the profile but doesn't auto-flag "skill X is made redundant by hook Y" — deferred to a later release; needs design work.
- Phase 3 niche-stack short-circuit suggests authoring a hook or MCP wrapper but does not author them; out of scope.

## [0.1.0] — 2026-04-16

### Added
- Initial public release
- `/skill-forge` slash command with full 9-phase pipeline (discover → audit → find-candidates → first-pass → research → second-pass → structure → QA → memory)
- `skill-forge` skill with progressive-disclosure methodology (main SKILL.md + 10 reference files)
- `audit.sh` — static-analysis script for skill libraries (YAML validity, rule coverage, filePattern overlap, progressive-disclosure detection)
- `install.sh` — one-line installer that copies skill + command into `~/.claude/`
- Five worked example skills produced by the methodology (pyside6-desktop, network-device-discovery, windows-release-pipeline, mass-deploy-ux, python-packaging)
- Seven verified-source research documents produced by Phase 5 agents
- Documentation: README, INSTALL, CONTRIBUTING, architecture notes, AI-discoverability note

### Safety rails
- Never auto-install third-party skills (clone-to-review only)
- Parallelism cap of 3 concurrent agents (stay under Anthropic compliance thresholds)
- Phase 4 creates backup tarball before any edits
- Phase 5 (cost-bearing) requires explicit user consent
- Every added rule must cite a source URL or project-memory reference

### Known limitations
- `audit.sh` requires Python 3 + PyYAML (documented in INSTALL)
- Windows-native shell compatibility untested (WSL works)
- Phase 5 cost estimate is heuristic; actual token usage may vary
