# skill-forge — Architecture

How the pieces fit together, for contributors and curious users.

## The two components

### 1. `/skill-forge` slash command (`command/skill-forge.md`)
- Entry point
- Parses `$ARGUMENTS` into a path + flags
- Invokes the `skill-forge` skill
- Orchestrates the 9 phases, honoring `--phase=`, `--from-phase=`, `--skip-*` flags
- Owns the safety rails (no auto-install, parallelism cap, checkpoint gating)

### 2. `skill-forge` skill (`skill-forge/`)
- The methodology
- Dogfoods progressive disclosure (brief main SKILL.md + 10 reference files)
- Referenced by the slash command AND auto-loaded if Claude decides it's relevant

## Phase reference files

The main `SKILL.md` contains the high-level phase table. Each phase's detailed steps live in `skill-forge/references/phase-N-<name>.md`.

**Why split?** Loading all 9 phases at once into context would be ~10k tokens of instructions Claude has to hold. Loading them one at a time as execution progresses keeps the active context focused on *the current step*.

Claude reads a phase's reference file immediately before executing that phase, executes the phase, prints the checkpoint, then (on user consent) reads the next phase's reference.

## Data flow

```
User runs: /skill-forge

  ↓
Slash command parses args
  ↓
Loads skill-forge/SKILL.md (phase table + principles)
  ↓
Phase 1: Read references/phase-1-discover.md
         Execute → write <project>/.skill-forge/profile.json
         Print checkpoint → wait for user
  ↓
Phase 2: Read references/phase-2-audit.md
         Run scripts/audit.sh → write <project>/.skill-forge/audit-report.md
         Print checkpoint → wait for user
  ↓
  ... (phases 3-8)
  ↓
Phase 5 (expensive): Use references/research-agent-brief.md as template
         Spawn 3-agent batches of search-specialist agents
         Each writes <project>/docs/skill-research/0N-<slug>.md
  ↓
Phase 9: Read references/phase-9-memory.md
         Diff memory → write new entries to ~/.claude/projects/<slug>/memory/
         Print final summary
```

## Per-project artifacts (not in this repo)

Everything `skill-forge` produces lands in the *target project*, not this repo:

```
<target-project>/
├── .skill-forge/              ← tool state (gitignored)
│   ├── profile.json
│   ├── audit-report.md
│   ├── first-pass-changes.md
│   ├── second-pass-changes.md
│   ├── qa-report.md
│   ├── rejections.md
│   ├── run-log.md
│   └── backup-<ts>.tar.gz
├── docs/skill-research/       ← verified research (not gitignored; keep)
│   ├── INDEX.md
│   └── 0N-<topic>.md
└── skill-review/              ← cloned candidates (gitignored)
```

The intent: research docs are persistent (they're source-of-truth citations); working state is transient.

## Audit script design

`skill-forge/scripts/audit.sh` is bash + embedded Python (for YAML parsing). It checks:

- YAML frontmatter parses (required: `name`, `description`)
- `name` matches directory
- Description ≤ 300 chars
- Main SKILL.md ≤ 2,500 tokens (warning threshold)
- Rule number duplicates (understanding progressive disclosure — inline + reference is OK; same rule in two reference files is NOT)
- References mentioned in main actually exist
- references/*.md files are all mentioned in main (no orphans)
- Cross-skill filePattern overlap matrix

Designed to be called directly or from `/skill-forge --phase=audit`. Zero dependencies beyond `python3 + pyyaml`.

## Safety rails (hardcoded)

These aren't configurable — they're commitments:

| Rail | Where enforced |
|---|---|
| Never auto-install third-party skills | Phase 3 reference file; slash command step 4 |
| Max 3 concurrent agents | Phase 5 reference file |
| QA always runs | Slash command step 4 |
| Consent before Phase 5 | Phase 5 reference file |
| Backup before Phase 4 edits | Phase 4 reference file |

Changing any of these requires a design-rationale PR, not a drive-by.

## Extending

### Adding a phase

1. Write `skill-forge/references/phase-N-<name>.md`
2. Add it to the phase table in `skill-forge/SKILL.md`
3. Reference it from the slash command's step listing
4. Decide: is it cost-bearing? Cheap? (Affects checkpoint phrasing.)
5. Add a flag like `--skip-<name>` if it's skippable
6. Update `README.md` phase table

### Adding an audit check

1. Add the check logic to `skill-forge/scripts/audit.sh`
2. Decide: error (fails the run) or warning (notes but continues)?
3. Add a line to `skill-forge/references/phase-8-qa.md` documenting it
4. Test on staged repo (run `audit.sh` on `skill-forge/`)

### Porting to another agent harness

The slash command is Claude-Code-specific. To port:

1. Rewrite `command/skill-forge.md` in the target harness's command format
2. Preserve the phase sequencing and checkpoint gating
3. Map `Skill` tool to the harness equivalent (or inline the methodology)
4. `audit.sh` is harness-agnostic — keep as-is
5. Phase reference files are readable markdown — keep as-is
6. Submit as a sibling repo; link from this README
