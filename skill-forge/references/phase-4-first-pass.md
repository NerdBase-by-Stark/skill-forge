# Phase 4 — First-Pass Edits

**Goal:** Apply the **high-confidence clear wins that the user approved** at the Phase 3→4 gate. Typos, broken cross-references, scope clarifications, overdue corrections, candidate installs.

**Depends on:** Phase 2 audit + Phase 3 candidate review + **user approval via `AskUserQuestion` at the Phase 3→4 gate** (see `references/phase-3-find-candidates.md §Checkpoint`).

## Scope

This phase only executes changes the user already approved. The plain-English change blocks, justification bar, and approval dialog all happen at the end of Phase 3 — not here. By the time Phase 4 starts, the edit set is frozen.

If the user chose **Cancel** at the gate, Phase 4 is a no-op: skip straight to the Phase 4→5 cost gate. The backup tarball is still NOT created (nothing to back up).

## Rule of thumb for this phase

If a change would require web research to justify, defer it to Phase 6. If you can verify the change with existing project files, project memory, or a single docs URL you already know is authoritative, it belonged in the Phase 3→4 gate. No new changes get invented in this phase — only approved ones execute.

## Before executing approved edits

Snapshot the user's skills directory (only if the approved set is non-empty):

```bash
cd ~/.claude/skills
tar czf <target-project>/.skill-forge/backup-$(date +%Y%m%d-%H%M%S).tar.gz .
```

The backup is defence-in-depth. The primary safety rail is that the user already saw and approved every change.

## Typical first-pass edits

### 4.1 Description tightening
- Any skill with description > 300 chars: shorten
- Any skill with vague description (`Python development rules`): make specific to the actual content

### 4.2 filePattern narrowing
- Any skill with `**/*.py` or similar catch-all: replace with convention-based patterns (`**/pages/*.py`, `**/widgets/*.py`, etc.) inferred from actual target-project layout
- Any skill with bashPattern on a generic command (`python`, `pip`, `git`): narrow to the actual trigger phrase that matters

### 4.3 Cross-reference additions
- If Phase 2 found two skills that should cite each other (e.g. `python-packaging` vs `pyside6-desktop`), add the mutual reference in each one's main SKILL.md
- If project CLAUDE.md points to a skill that doesn't explicitly mention the project's conventions, add a "Used by <project>" note

### 4.4 Broken links
- Check all `references/X.md` mentions resolve to actual files
- Check all external URLs return 200 (use `curl -sI -o /dev/null -w "%{http_code}" <url>` in a loop)

### 4.5 Known corrections
- If project memory contains a `gotcha_*.md` that contradicts a skill, update the skill to reflect the project learning (with source cited as the memory file)
- If a skill claims behavior for a framework version and the project is on a newer version, flag for Phase 6 (don't guess)

## What NOT to do in this phase

- Don't add new rules sourced from memory alone — wait for Phase 6 which has research context
- Don't delete rules without user confirmation
- Don't refactor structure (that's Phase 7)
- Don't change rule numbering or IDs (breaks cross-references)

## Produce a change log

Write to `<project>/.skill-forge/first-pass-changes.md`:

```markdown
# First-Pass Changes — <date>

## Per-skill changes

### pyside6-desktop
- Description shortened 355 → 239 chars
- filePattern narrowed: removed `**/*.py`, added Qt-convention patterns
- Added cross-reference to mass-deploy-ux

### network-device-discovery
- Added URL to GBL protocol memory file in vendor-broadcast section

### python-packaging
- Added explicit scope-boundary note + pointer to pyside6-desktop for exe bundling
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "First-pass edits done — research next? (~$3-8)"
Header:   "Phase 4 → 5"
Options:
  - Label: `Run deep research (~$3-8)`
    Description: Spawn 5-8 search-specialist agents in batches of 3
  - Label: `Skip research`
    Description: Jump to Phase 7 — structural cleanup only
  - Label: `Explain more`
    Description: Describe what Phase 5 does + cost breakdown, then re-ask
  - Label: `Stop`
    Description: Exit; first-pass changes preserved
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 5 spawns 5-8 parallel research agents (batched 3 at a time for compliance) — typically the `search-specialist` subagent if available, or `general-purpose` otherwise. Each produces a verified-source research doc covering a specific gap from Phase 2, using whatever web-research tools are installed (firecrawl, built-in WebSearch/WebFetch, Tavily, etc.) and citing every claim. Cost: ~$0.50-1 per agent in tokens ≈ $3-8 total. Output: `<project>/docs/skill-research/0N-<topic>.md` files. Takes 10-20 minutes wall time.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

`--skip-first-pass` — if nothing worth doing turned up in audit. Uncommon.
