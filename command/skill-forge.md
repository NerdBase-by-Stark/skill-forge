---
allowed-tools: Skill, Read, Write, Edit, Bash, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, WebFetch
argument-hint: [project-path | --phase=<name> | --skip-research | --skip-audit]
description: Disciplined 9-phase pipeline to audit, research, and improve a project's skill library (discover → audit → find candidates → first-pass → research → second-pass → structure → QA → memory)
---

# /skill-forge

Argument: `$ARGUMENTS`

Runs the `skill-forge` skill's full 9-phase pipeline on a target project.

## Step 1: Parse arguments

Parse `$ARGUMENTS` into:
- `project_path` — a filesystem path, or empty (default to cwd)
- Flags — `--phase=<1-9 or name>`, `--skip-research`, `--skip-audit`, `--skip-structure`, `--from-phase=<N>`, `--profile=<path>`

Examples:
- `/skill-forge` → full pipeline on cwd
- `/skill-forge ~/code/my-other-project` → full pipeline on a specific project path
- `/skill-forge --phase=audit` → just Phase 2 (audit)
- `/skill-forge --from-phase=6` → resume from Phase 6 (requires existing research docs)
- `/skill-forge --skip-research` → full pipeline minus Phase 5 (reuses existing research if present)

If the argument is empty, confirm the target: `Run skill-forge against $(pwd)?` — don't assume.

## Step 2: Invoke the skill-forge skill

Use the Skill tool to load the skill-forge methodology:

```
Skill(skill="skill-forge")
```

This loads the main `SKILL.md` with the phase table. Do NOT preload all phase reference files — the skill's operating protocol is to read them on demand, one per phase.

## Step 3: Run the pipeline

Follow the 9 phases in the skill's table. For each phase:

1. Read the matching `references/phase-N-<name>.md` reference file via the Read tool
2. Execute the phase steps
3. Print a concise phase summary as plain text (what was done, counts, notable findings)
4. **Call the `AskUserQuestion` tool** — NOT a text prompt — to gate the next phase. Each phase reference file specifies the exact question, header, and options to pass. Text prompts like "Proceed? [yes/no]" get missed by users skimming output; `AskUserQuestion` presents a clickable multi-choice dialog that blocks until selection.

Honor user flags:
- `--phase=N` or `--phase=<name>` → run ONLY that phase; **no AskUserQuestion at the end** (the single-phase mode is explicit about its scope)
- `--from-phase=N` → start at phase N, run through Phase 9 with full checkpoint gating between phases
- `--skip-<name>` → execute everything but skip named phases (still present `AskUserQuestion` on Phase 5 if research isn't skipped)

## Step 4: Critical safety rules

These are hard stops — do NOT violate:

1. **Never install third-party skills** to `~/.claude/skills/` from Phase 3. Clone for review only. Gems are extracted manually in Phase 6.
2. **Never spawn > 3 agents concurrently** in Phase 5. Batch them. The compliance hook flags at 5 concurrent Claude processes.
3. **Never skip Phase 8 (QA)** even if the user passes `--skip-*` flags.
4. **Never proceed from Phase 4 to Phase 5 without consent** — research costs real money.
5. **Never commit on the user's behalf** — edits happen but git commits are the user's call.
6. **Always create a backup tarball** in Phase 4 before making any edits to `~/.claude/skills/`.

## Step 5: Progress tracking

Use TaskCreate to create one task per phase at pipeline start. Mark them in_progress/completed as you advance. Surfaces progress to the user and makes mid-run resumption clean.

## Step 6: On failure

If any phase fails (audit script non-zero, agent output rejected, user stops):
- Preserve all artifacts written so far (research docs, audit reports, first-pass edits)
- Print a concise failure summary with recovery options
- Offer: `resume with --from-phase=<N>` or `rollback from backup tarball`
- Do not auto-rollback — user decides

## Step 7: Completion

Phase 9 is terminal. After it runs, print a final summary (see `references/phase-9-memory.md` for format) and stop. Do not continue past Phase 9.

---

**Invoke the skill-forge skill now and begin Phase 1.**
