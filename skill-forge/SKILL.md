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
8. **Bias toward no-change — but don't conflate "don't edit" with "don't research".** A skill that already passes audit, has accurate content, and fits its scope is a success — *not an edit target*. Do not rewrite descriptions that parse and trigger correctly just because shorter is possible. Do not split skills under budget. Do not add rules that merely duplicate existing ones with different wording. Default action on existing content = **acknowledge and leave alone**. Editing requires a named, concrete gain, not a possible one.

   **However: "Fits — leave alone" does NOT exclude a skill from Phase 5 research.** Research streams are driven by the project's tech stack and pain points, not by whether the existing skill looks broken. A healthy skill can still benefit from a newly verified gem that the wider world has learned since the skill was last touched. If Phase 5 surfaces a genuine verified rule that the skill doesn't cover, Phase 6 proposes the *addition* via the approval gate — existing wording untouched, new rule appended with source. User approves per-change.

   If second-run audit finds no defects AND no Phase 5 research is requested (or none proposed gems that pass the justification bar), report "library is healthy" and exit — produce no changes.
9. **Every proposed change carries a justification in plain English.** Before any write to `~/.claude/skills/`, the user sees a block per skill: *what changes / what you gain / what the risks are / where the evidence came from / how to revert*. The user approves via `AskUserQuestion` before any edit lands. Post-hoc summaries are not consent.
10. **Sub-agents are output-only.** Research agents write files, nothing else. No `git`, no `gh`, no branches, no commits, no PRs. See `references/research-agent-brief.md` for the mandatory scope clause.

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

## On invocation — confirm intent first

skill-forge has a large blast radius: it audits skills, spawns paid research agents, and proposes writes to `~/.claude/skills/`. Claude may auto-trigger this skill on broad matches like *"can you check my skills?"* or *"audit the skill library"* — both of which could plausibly mean "have a look" rather than "run the full 9-phase pipeline."

**Before executing Phase 1, check how you were invoked:**

- **Explicit invocation** (user typed `/skill-forge` or `/skill-forge <path>`) — proceed directly to Phase 1. The user has already declared intent.
- **Model-invoked match** (you triggered this skill via description matching, not via the slash command) — **STOP. Call `AskUserQuestion` first** to confirm the user wants the full 9-phase audit pipeline, not just a quick conversation about skills.

Example intent-confirmation gate:

```
Question: "Run the full skill-forge 9-phase audit? (~30 min, may spend $3-8 on research)"
Header:   "Intent check"
Options:
  - Label: `Yes, run full audit`
    Description: 9 phases: discover, audit, candidates, first-pass edits, deep research, second-pass edits, structure, QA, memory
  - Label: `Just a quick look`
    Description: Skip pipeline; I'll answer your question about skills in conversation instead
  - Label: `Audit only (no research)`
    Description: Run Phases 1-4 + 7-9 only; skip paid Phase 5 research
  - Label: `Explain more`
    Description: Describe what each phase does, then re-ask
```

On **Just a quick look**: acknowledge and exit the skill; Claude answers conversationally.
On **Audit only (no research)**: proceed but pass `--skip-research` through.
On **Yes, run full audit**: proceed to Phase 1.

This preserves the ability for Claude to surface skill-forge on broad matches (discoverability) while preventing accidental full-pipeline runs that spend tokens without clear consent. Complements Operating Principle #9 (every write gated) by extending the consent principle to the skill's own invocation when intent is ambiguous.

## Modes and checkpoint protocol

Two modes, set by the invoking slash command:

### Autopilot (default for `/skill-forge`)

Fast where safe, but **writes to `~/.claude/skills/` are always consent-gated** — the user sees the full change set in plain English and approves via `AskUserQuestion` before any skill file is touched. Progress summaries between non-write phases print as text (no stop).

**Autopilot has four mandatory `AskUserQuestion` stops:**

1. **Phase 3 → 4 (first-pass approval gate)** — present every proposed Phase 4 edit and every install with its plain-English change block (see `references/phase-4-first-pass.md §4.0`). No edits land without approval.
2. **Phase 4 → 5 (cost gate)** — spawning research agents spends real tokens. Always ask.
3. **After Phase 5 (rogue-agent check)** — diff git/PR state from the pre-Phase-5 snapshot; if a sub-agent created branches, commits, or PRs during research, stop and let the user decide. See `references/phase-5-research.md §5.9`.
4. **Phase 5 → 6 (second-pass approval gate)** — present every proposed Phase 6 edit and every new-skill creation with its plain-English change block (see `references/phase-6-second-pass.md §6.0`). No edits land without approval.

**One terminal summary: Phase 9.** The star-ask dialog. Natural end.

Auto-advances (no stop) between phases where nothing is being written to `~/.claude/skills/`:
- Phase 1→2, 2→3, 6→7, 7→8, 8→9

**Healthy-library early exit.** If Phase 2 audit produces a classification where every in-scope skill is verdict "Fits — leave alone" AND Phase 3 finds no install-worthy candidates, Phase 4 prints *"Library is healthy — no changes proposed"* and `AskUserQuestion` offers `[Exit to summary / Run Phase 5 research anyway / Stop]`. No edits, no tarball, straight to Phase 9.

The backup tarball still exists as a defence-in-depth safety rail. The **primary** safety rail is the consent gate.

### Interactive (`/skill-forge --interactive`)

The cautious version. `AskUserQuestion` after every phase. Each phase reference file defines the exact question + 3-4 short options, always including "Explain more" for detail on demand.

Use interactive when: first-time user, reviewing a contributor's skills, running on a project you're not familiar with, or you want to see each decision before it lands.

### When to call `AskUserQuestion` — quick reference

| Phase | Autopilot | Interactive |
|---|---|---|
| 1→2 | auto-advance | ask |
| 2→3 | auto-advance | ask |
| 3 (per-candidate disposition) | apply agent's recommendation (consented at 3→4 gate) | ask per candidate |
| **3→4 (first-pass approval gate)** | **ASK — show every change in plain English** | **ASK** |
| **4→5 (cost gate)** | **ASK** | **ASK** |
| **After Phase 5 (rogue-agent check)** | **ASK if anomalies detected** | **ASK if anomalies detected** |
| **5→6 (second-pass approval gate)** | **ASK — show every change in plain English** | **ASK** |
| 6→7 | auto-advance | ask |
| 7→8 | auto-advance | ask |
| 8→9 | auto-advance | ask |
| 9 (star-ask) | ask | ask |

**Design principle:** writes to `~/.claude/skills/` are user territory and require explicit, informed consent. The backup tarball is defence-in-depth, not the primary rail. Research-token spend stays consent-gated because it's the only irreversible cost. Rogue-agent check catches sub-agents that stepped outside their output-only scope before the next phase compounds the blast radius.

**Every stop uses `AskUserQuestion`.** Never print "Proceed? [yes/no]" as text — users skim and miss them. Short option labels (2-5 words), descriptions carry the detail.

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
