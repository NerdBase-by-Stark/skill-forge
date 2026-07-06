---
allowed-tools: Skill, Read, Write, Edit, Bash, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, WebFetch
argument-hint: [project-path | --interactive | --phase=<N|name> | --from-phase=<N> | --profile=<path> | --skip-research | --skip-audit | --skip-structure | --skip-find | --skip-first-pass | --dual-research | --budget=low | --skip-critique | --skip-security-stream]
description: Disciplined 9-phase pipeline to audit, research, and improve a project's skill library. Single-model by default; --dual-research opts into topic-partitioned Opus+Sonnet streams. Automatic cheap Sonnet critique pass after extraction.
---

# /skill-forge

Argument: `$ARGUMENTS`

Runs the `skill-forge` skill's full 9-phase pipeline on a target project.

## Step 1: Parse arguments

Parse `$ARGUMENTS` into:
- `project_path` — a filesystem path, or empty (default to cwd)
- Flags — the full recognized set (identical to the frontmatter argument-hint; anything else is an error, say so):
  `--interactive`, `--phase=<1-9 or name>`, `--from-phase=<N>`, `--profile=<path>`, `--skip-research`, `--skip-audit`, `--skip-structure`, `--skip-find`, `--skip-first-pass`, `--dual-research`, `--budget=low`, `--skip-critique`, `--skip-security-stream`

Examples:
- `/skill-forge` → full pipeline on cwd (single-model, auto-critique on, auto-security-stream if triggered)
- `/skill-forge ~/code/my-other-project` → full pipeline on a specific project path
- `/skill-forge --phase=audit` → just Phase 2 (audit)
- `/skill-forge --from-phase=6` → resume from Phase 6 (requires existing research docs)
- `/skill-forge --skip-research` → full pipeline minus Phase 5 (reuses existing research if present)
- `/skill-forge --skip-find` / `--skip-first-pass` → skip Phase 3 / Phase 4 respectively
- `/skill-forge --dual-research` → Phase 5 uses topic-partitioned Opus + Sonnet streams (+$1.50-2.50); see `phase-5-research.md`
- `/skill-forge --budget=low` → skip Phase 6 critique pass; minimal-cost run. Does NOT skip the mandatory security stream — only the explicit `--skip-security-stream` can do that
- `/skill-forge --skip-critique` → skip Sonnet read-only critique pass after Phase 6 primary extraction
- `/skill-forge --skip-security-stream` → skip the mandatory security stream even if profile triggers it (warns loudly)

If the argument is empty, confirm the target: `Run skill-forge against $(pwd)?` — don't assume.

## Step 2: Invoke the skill-forge skill

Use the Skill tool to load the skill-forge methodology:

```
Skill(skill="skill-forge")
```

This loads the main `SKILL.md` with the phase table. Do NOT preload all phase reference files — the skill's operating protocol is to read them on demand, one per phase.

## Step 3: Run the pipeline (autopilot by default)

Default mode is **autopilot** — fast where safe, but every write to `~/.claude/skills/` is consent-gated. The pipeline auto-advances between non-write phases, printing concise summaries. Writes are always preceded by a plain-English change-block presentation + `AskUserQuestion`.

**Five mandatory `AskUserQuestion` stops in autopilot:**

1. **Phase 3 → 4 (first-pass approval gate)** — every proposed edit and install shown with plain-English *what changes / what you gain / risks / source / reversibility*. No edits land without approval. See `references/phase-3-find-candidates.md §Checkpoint`. On approval: `touch .skill-forge/consent-phase4.ok`; delete it when Phase 4 ends.
2. **Phase 4 → 5 (cost gate)** — research spawns paid agents. Always ask.
3. **After Phase 5 (rogue-agent check)** — diff git/PR state vs. pre-Phase-5 snapshot; if a sub-agent created branches, commits, or PRs during research, stop and let the user choose close/keep/investigate. See `references/phase-5-research.md §5.9`.
4. **Phase 5 → 6 (second-pass approval gate)** — every proposed new rule and new-skill shown with plain-English justification. No edits land without approval. See `references/phase-6-second-pass.md §6.0`. On approval: `touch .skill-forge/consent-phase6.ok`; delete it when Phase 6 ends.
5. **Phase 6 → 7 (structure/QA write gate)** — Phases 7 and 8 also write to `~/.claude/skills/`. Present the planned refactors and QA fix policy; skip the ask only if neither phase will write anything (and say so). On approval: `touch .skill-forge/consent-phase7.ok`; delete it when Phase 8 ends.

Plus the terminal Phase 9 star-ask.

**Empty-answer = STOP.** If any `AskUserQuestion` returns empty/missing answers (unattended timeout or harness bug), never infer a selection and never proceed to a write or spend phase: re-ask once, then halt preserving artifacts.

For each phase:

1. Read the matching `references/phase-N-<name>.md` reference file
2. Execute the phase steps
3. Print a concise summary as plain text (what was done, counts, notable findings — 5-10 lines)
4. **If autopilot (default):** auto-advance to the next phase unless the phase hits one of the five gates above. Never text-prompt "Proceed?" — use `AskUserQuestion` at every stop.
5. **If `--interactive`:** call `AskUserQuestion` after every phase using the spec in that phase's reference file.

Flags:
- `--interactive` → full per-phase checkpoints (the cautious mode)
- `--phase=N` → run ONLY that phase; no end-of-phase AskUserQuestion
- `--from-phase=N` → start at phase N, run through Phase 9 (autopilot unless also `--interactive`)
- `--skip-<name>` → skip named phases; Phase 5 consent still required if research isn't skipped

## Step 4: Critical safety rules

These are hard stops — do NOT violate:

1. **Never spawn > 3 agents concurrently** in Phase 5. Batch them. (Deliberate safety margin under the ~10-concurrent warning threshold documented in `docs/skill-research/03-subagent-orchestration.md`.)
2. **Never skip Phase 8 (QA)** even if the user passes `--skip-*` flags.
3. **Never proceed from Phase 4 to Phase 5 without explicit consent** — research costs real money. `AskUserQuestion` cost gate is mandatory in both autopilot and interactive modes.
4. **Never write to `~/.claude/skills/` without explicit user approval via `AskUserQuestion`** — the Phase 3→4 and Phase 5→6 gates present every change in plain English and require approval. Post-hoc summaries are not consent.
5. **Never commit on the user's behalf** — edits happen but git commits are the user's call.
6. **Always create a backup tarball** in Phase 4 before making any edits to `~/.claude/skills/`. The backup is defence-in-depth; the primary safety rail is the approval gate.
7. **Phase 3 candidate dispositions** are the agent's *recommendations*; the user explicitly approves them at the Phase 3→4 gate. The gate lets the user approve all, skip installs only, review each, or cancel. Installing directly is a legitimate disposition if it clears the justification bar and the user approves.
8. **Sub-agents are output-only.** Research agents write files, not git/PR side effects. Enforce via the strict-scope clause in every brief + the post-Phase-5 rogue-agent check (`phase-5-research.md §5.9`).
9. **Bias toward no-change.** Agents have a strong bias toward finding things to edit. Skills marked "Fits — leave alone" in Phase 2 are excluded from Phase 4 edits (but NOT from Phase 5 research). A rewording with no concrete observable gain is dropped by the justification bar before the user ever sees it.

## Step 5: Progress tracking

Use TaskCreate to create one task per phase at pipeline start. Mark them in_progress/completed as you advance. Surfaces progress to the user and makes mid-run resumption clean.

## Step 6: On failure

If any phase fails (audit script non-zero, agent output rejected, user stops):
- Preserve all artifacts written so far (research docs, audit reports, first-pass edits)
- Print a concise failure summary with recovery options
- Offer: `resume with --from-phase=<N>`; additionally offer `rollback from backup tarball` ONLY if `.skill-forge/backup-*.tar.gz` exists (it is created at Phase 4 — earlier failures have nothing to roll back and nothing was written)
- Restore procedure (verbatim, do not improvise): `cd ~/.claude/skills && tar xzf <project>/.skill-forge/backup-<timestamp>.tar.gz`
- Do not auto-rollback — user decides

## Step 7: Completion

Phase 9 is terminal. After it runs, print a final summary (see `references/phase-9-memory.md` for format) and stop. Do not continue past Phase 9.

---

**Invoke the skill-forge skill now and begin Phase 1.**
