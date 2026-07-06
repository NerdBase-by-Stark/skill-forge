# Changelog

All notable changes to this project will be documented in this file. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] — 2026-07-06

### Theme
**Post-audit hardening.** Driven by a 430-agent adversarial audit (87 confirmed findings) plus a 32-gap analysis. No new pipeline phases — this release closes consent, correctness, and installer gaps across the existing nine.

### Added
- **Fifth mandatory consent gate (6→7).** Autopilot now stops at five `AskUserQuestion` gates: 3→4 first-pass approval, 4→5 cost, post-5 rogue-agent, 5→6 second-pass approval, and the NEW 6→7 structure/QA write gate. Phase 7/8 writes are consent-gated via `.skill-forge/consent-phase7.ok` markers.
- **New audit rules in `scripts/audit.sh`:** FM004 (description missing when-NOT-to-use), FM005 (description not third person), FM006 (always-invoke language), FM007 (destructive keywords without `disable-model-invocation`), RI003 (nested references), SS007 (long reference file without a TOC).
- **`audit.sh --format json`** — machine-readable output, implemented (previously documented but absent).
- **`audit.sh --self`** — install self-check; verifies the installed copy is complete and runnable.
- **`scripts/validate-profile.sh` + `schemas/profile.schema.json`** — Phase 1 profile validation; `profile_schema_version` field added to the profile.
- **`install.sh`: `--check` drift detection, `--uninstall`, `.install-manifest` provenance, backup pruning.** Installer now also ships `schemas/` and `hooks/`.
- **`hooks/skill-write-gate.sh`** — opt-in PreToolUse hook that blocks un-consented writes to `~/.claude/skills/`.
- **Phase 1 usage-telemetry inventory** — profile field `usage_telemetry`; Phase 2 §2.1b consumes it, including the new verdict "Candidate: archive (unused)".

### Changed
- **Empty `AskUserQuestion` answer = STOP** — hard rule at every gate; an empty answer is never treated as consent.
- **Critique pass resequenced** — the Phase 6 Sonnet critique now runs on the *proposed* change set before the 5→6 approval gate presents it, not after edits are applied; supervisor verification (grep-based false-positive/diligence checks) added before folding critique findings into the gate.
- **`--budget=low` no longer skips the mandatory security stream** — only the explicit `--skip-security-stream` flag can.
- **Skill-split threshold unified at >500 lines** (audit.sh SS001); ~1,500-2,500 tokens is now only the post-refactor main-body target, not the split trigger.
- **Phase 3 install command corrected** — `npx skills add <owner>/<repo> --skill <skill-name> -y`, project-local by default; the `<pkg>@<skill>` suffix form is `use`-only and would install every skill in the repo under `add`.
- **`version: 0.3.0` in `skill-forge/SKILL.md` frontmatter** is now the version single source of truth.

### Fixed
- **3-agent cap rationale corrected** — the cap is a safety margin under the ~10-concurrent threshold documented in `docs/skill-research/03-subagent-orchestration.md`; the old "compliance hook warns at 5" claim was wrong.
- Documentation drift: removed the never-implemented `--no-backup` flag from the README; checkpoint behavior docs now match autopilot reality.

## [0.2.2] — 2026-04-19

(G-numbers reference the internal v0-2-2 planning doc: docs/skill-research/v0-2-2-plan-2026-04-19.md.)

### Theme
**System-aware Phase 1.** Triggered by a Q-SYS-plugins dry-run (Lua monorepo, completely different stack from prior biltong run) that surfaced 12 gaps centred on a single root cause: Phase 1 only inventoried `~/.claude/skills/`, ignoring the rest of the developer surface (hooks, MCP servers, local knowledge bases, non-JS/Python stacks, monorepos, project-local skills). Same philosophy as 0.2.1 — process fixes over new models. Written for an intelligent agent to execute, not as a prescriptive script.

### Added
- **TR004 audit rule** in `scripts/audit.sh` — SUGGESTION when a skill declares no `filePattern` AND no `bashPattern` (description-only discovery). Gently prompts the author to add triggers if the skill is meant to auto-fire on specific file types or commands. (Closes G4/G5.)
- **Phase 1 rewritten around a full developer-surface profile.** A single section (§1.4) instructs the agent to inventory hooks (`~/.claude/settings.json`), MCP servers (`~/.claude.json`, project `.mcp.json`), and local knowledge bases as first-class parts of the stack. Later phases (2 audit, 5 research, 6 extraction) consume `active_hooks[]`, `available_mcp_servers[]`, `local_knowledge_bases[]` from the profile. (Closes G12, G13, G14.)
- **Project-local skills inventory** — §1.3 now also scans `<project>/.claude/skills/` and nested sub-project skill dirs. Project-local skills get priority in Phase 2 audit. (Closes G6.)
- **Monorepo / sparse-root handling** — §1.1 defaults to profiling the whole monorepo with `sub_projects[]` populated so Phase 5 stream planning knows each stack; no user question required. (Closes G1, G7.)
- **Lua / Q-SYS stack support** — §1.2 lists `.qplug` / `.rockspec` / `qpdk` as first-class stack markers. §1.6 completeness check tells the agent to measure *actual API surface usage* for stacks where dependencies are built-in runtime namespaces (Q-SYS: `Controls.`, `Component.`, `Timer.`, etc.), rather than assuming a package-manifest-based grep suffices. (Closes G2, G3.)
- **Description-keyword-fallback relevance** — §1.3 relevance algorithm now matches description-only skills via keyword overlap with stack tags or heavy-API-surface entries, closing the blind spot where triggerless Q-SYS skills scored zero relevance against a Q-SYS project.
- **Research-agent brief: check local tools first** (`references/research-agent-brief.md`). A trimmed paragraph instructs Phase 5 agents to try code-index / docs-index / memory MCPs and local KBs before web research. An MCP-derived answer is still cited. (Closes G13 downstream.)
- **Phase 3 niche-stack guidance** (`references/phase-3-find-candidates.md`). New section documents that reputation-by-installs *inverts* for niche / commercial-AV stacks (Q-SYS, Crestron, Extron, BSS, etc.); expert-authored skills are often the low-install ones. Short-circuit rule prevents wasted agent time. Hook / MCP authorship surfaced as alternative gap-fillers (out of skill-forge scope). (Closes G8, G9.)

### Changed
- **Phase 1 reference file** rewritten in agent-guidance style rather than prescriptive bash/jq recipes. The earlier draft prescribed exact commands for the agent to run; this release trusts the agent to figure out *how* once it knows *what* matters. Hard security constraints (don't Read settings.json / .claude.json in full — they contain API tokens) are retained as explicit rules. Fixes a pre-existing duplicate §1.5 numbering bug.
- **`SKILL.md` phase table** Phase 1 summary updated to reflect full-system profiling.

### Security
- `~/.claude/settings.json` and `~/.claude.json` called out as DO-NOT-READ files (contain API tokens). Phase 1 inventory uses `jq` to extract structure only, never values.

### Known limitations
- Hook↔skill redundancy detection is not yet automated. Phase 2 audit surfaces `active_hooks` in the profile but doesn't auto-flag "skill X is redundant with hook Y" — deferred; needs design work.
- Phase 3 niche-stack short-circuit suggests hook or MCP authorship as alternatives but does not author them; out of scope.

## [0.2.1] — 2026-04-19 (retroactive entry)

- Dual-model strategy — targeted, not everywhere. Introduced the Sonnet critique pass where a second model demonstrably adds value, rather than dual-modelling every phase.

## [0.2.0] — 2026-04-19 (retroactive entry)

- Consent gates, rogue-agent check, 2026-aligned audit. First release of the mandatory `AskUserQuestion` write-consent gates and the post-Phase-5 rogue-agent check.

## [0.1.1] — 2026-04-19 (retroactive entry)

- Autopilot default + install-directly disposition for Phase 3.

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
