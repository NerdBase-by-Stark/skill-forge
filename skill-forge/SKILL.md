---
name: skill-forge
description: Disciplined 9-phase workflow for auditing and improving a project's skill library — discover, audit, candidates, edits, research, structure, QA, memory. Invoked by /skill-forge or when user asks to improve/audit/tune skills.
filePattern: []
bashPattern: []
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - TaskCreate
  - TaskUpdate
  - TaskList
  - AskUserQuestion
---

# skill-forge — Disciplined skill-library improvement

End-to-end workflow for improving a project's skill library. Entry point is the `/skill-forge` slash command; this skill defines the methodology the command follows.

## Operating principles (never violate)

1. **No fabrication.** Every rule added to a skill must cite a source (URL, git commit, existing project memory, reverse-engineered artifact). If a research agent returns an unverified claim, mark it `UNVERIFIED` and do not merge it inline.
2. **Progressive disclosure default.** Any skill whose main SKILL.md exceeds ~2,000 tokens gets split into a brief main + `references/*.md`. See `references/phase-7-structure.md`.
3. **Never auto-install third-party skills.** Clone to a review directory (`skill-review/` under the target project), inspect, then copy only the verified gems into the user's active skills.
4. **Cap parallelism at 3 concurrent agents.** The Anthropic compliance hook warns at 5 concurrent Claude processes; research batches are sized to stay under.
5. **Checkpoint after every phase.** Each phase ends with a one-screen summary and an explicit go/no-go. The user can stop the pipeline at any point without losing completed work.
6. **Idempotent.** Re-running the command preserves previous research docs and audit reports. Edits are safe to re-run.
7. **Target one project at a time.** "All my projects" is an anti-pattern — each project has different conventions. Run against cwd or an explicit `--project=` argument.

## The 9 phases

| # | Phase | Output | Reference |
|---|---|---|---|
| 1 | **Discover** | Project profile: tech stack, existing skills, CLAUDE.md rules | `references/phase-1-discover.md` |
| 2 | **Audit** | Size / trigger / overlap report on existing project-relevant skills | `references/phase-2-audit.md` |
| 3 | **Find Candidates** | 3-5 external skills cloned to `skill-review/`, reviewed, gap analysis | `references/phase-3-find-candidates.md` |
| 4 | **First-Pass Edits** | Clear wins applied (cross-refs, scope clarifications, known corrections) | `references/phase-4-first-pass.md` |
| 5 | **Deep Research** | 5-8 search-specialist agents write verified-source docs to `docs/skill-research/` | `references/phase-5-research.md` (uses `references/research-agent-brief.md` template) |
| 6 | **Second-Pass Edits** | Verified gems extracted into skills; new skills created if warranted | `references/phase-6-second-pass.md` |
| 7 | **Structure** | Progressive disclosure refactor for oversized skills; filePattern tightening | `references/phase-7-structure.md` |
| 8 | **QA** | Automated audit: YAML, rule coverage, descriptions, filePattern overlap, reference existence | `references/phase-8-qa.md` + `scripts/audit.sh` |
| 9 | **Memory** | Persist architectural decisions, preferences, skill inventory to project memory | `references/phase-9-memory.md` |

## Modes and checkpoint protocol

Two modes, set by the invoking slash command:

### Autopilot (default for `/skill-forge`)

Fast. Skill-forge gets on with it. Claude still prints concise per-phase summaries (what was done, counts, notable findings) so the user sees progress, but does NOT stop for approval between phases.

**One mandatory stop: Phase 4 → 5 (cost gate).** Spawning research agents spends real tokens — always consent-gate. `AskUserQuestion` there; never auto-spend.

**One terminal summary: Phase 9.** The star-ask dialog. Natural end.

Everything else auto-advances:
- Phase 3 candidate decisions use the agent's recommendation (install-directly / extract-gems / skip per candidate) without per-candidate confirmation
- Phase 4 edits proceed after the backup tarball is created
- Phase 6 new-skill creation proceeds (backup from Phase 4 protects you)
- Phase 7 structural refactor proceeds
- Phase 8 QA proceeds
- Phase 9 memory writes happen, then the star-ask

If something goes wrong, every edit can be reverted from `<project>/.skill-forge/backup-<timestamp>.tar.gz`. The safety rail is the backup, not the checkpoint.

### Interactive (`/skill-forge --interactive`)

The cautious version. `AskUserQuestion` after every phase. Each phase reference file defines the exact question + 3-4 short options, always including "Explain more" for detail on demand.

Use interactive when: first-time user, reviewing a contributor's skills, running on a project you're not familiar with, or you want to see each decision before it lands.

### When to call `AskUserQuestion` — quick reference

| Phase | Autopilot | Interactive |
|---|---|---|
| 1→2 | auto-advance | ask |
| 2→3 | auto-advance | ask |
| 3 (per-candidate decisions) | apply agent's recommendation | ask per candidate |
| 3→4 | auto-advance | ask |
| **4→5 (cost gate)** | **ASK** | **ASK** |
| 5→6 | auto-advance | ask |
| 6 (new-skill creation) | proceed (backup protects) | ask |
| 6→7 | auto-advance | ask |
| 7→8 | auto-advance | ask |
| 8→9 | auto-advance | ask |
| 9 (star-ask) | ask | ask |

**Design principle:** the one true hard-stop is Phase 4→5 because research is the only irreversible cost. Everything else is reversible via Phase 4's backup tarball or git — so the checkpoint is friction, not safety.

**Never print "Proceed? [yes/no]" as text** — use `AskUserQuestion` when you do stop. Text prompts get missed.

The user can also invoke `--phase=audit` or `--from-phase=5` to start mid-pipeline; single-phase mode has no checkpoints.

## Workspace layout (what gets created)

```
<target-project>/
├── docs/
│   └── skill-research/              ← created in Phase 5, persisted across runs
│       ├── 01-<topic>.md
│       ├── 02-<topic>.md
│       └── ...
└── skill-review/                    ← created in Phase 3, gitignored
    ├── <owner>-<repo>/
    └── ...

.skill-forge/                        ← under target project, gitignored
├── profile.json                     ← Phase 1 output
├── audit-report.md                  ← Phase 2 output
├── backup-<timestamp>.tar.gz        ← pre-edit snapshot of ~/.claude/skills/
└── last-run.log
```

## Cost expectations

| Phase | Typical cost | Notes |
|---|---|---|
| 1-4, 6-9 | Low (few tool calls, small edits) | < $0.50 equivalent |
| 5 | Medium-high | ~$0.50-1.00 per research agent × 5-8 streams. Batched in groups of 3. Consent-gated. |

Total pipeline run on a ~5-skill project: ~$3-8 in agent-time tokens. Skip Phase 5 if you only want structural maintenance.

## When NOT to run

- **Active development in progress** — this will edit `~/.claude/skills/`. Commit your work first.
- **Recent identical run** — if `docs/skill-research/` has docs from the last 7 days and nothing changed, skip Phase 5 (`--skip-research`).
- **No skills relevant to the current project** — the command will detect this and suggest running with `--create-from-scratch` to bootstrap skills instead.

## Reading order for Claude

When invoked via `/skill-forge`, read phases on demand, one at a time, in order. Do NOT preload all 9 reference files — that defeats progressive disclosure. The flow:

1. Read this SKILL.md (already in context)
2. Read `references/phase-1-discover.md` and execute Phase 1
3. Present summary, wait for go
4. Read `references/phase-2-audit.md` and execute Phase 2
5. Continue until stopped

For re-entry at `--phase=N`: read the target phase's reference file + any phases it depends on (indicated at the top of each reference).

## Pairs with

- `writing-skills` (Anthropic) — canonical guidance for skill structure. Pull from it when creating new skills in Phase 6.
- `skill-creator` (Anthropic) — interactive skill creation. Use when Phase 6 needs to spawn an entirely new skill.
- User's own skills — the target of this workflow.
