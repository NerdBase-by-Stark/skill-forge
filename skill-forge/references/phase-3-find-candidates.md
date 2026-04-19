# Phase 3 — Find Candidates

**Goal:** Discover and review external skills from the community registry. Never auto-install.

**Depends on:** Phase 1 profile (for search queries).

## Steps

### 3.1 Derive search queries from the profile

Use the profile's `tech_stack_tags` and `frameworks` to build 3-5 query lines. Example for a PySide6 project:

- `npx skills find "pyside6 qt desktop"`
- `npx skills find "pyinstaller packaging windows"`
- `npx skills find "network device discovery scanning"`
- `npx skills find "code signing smartscreen"`
- `npx skills find "github actions python release"`

Run them in parallel Bash calls (separate tool calls in the same message).

### 3.2 Parse results into a candidate table

For each query, the output lists `<owner>/<repo>@<skill-name>` with install counts. Rank candidates by:
- Install count (popularity = crude proxy for quality)
- Alignment with a gap identified in Phase 2 audit
- Owner reputation (prefer `vercel-labs`, `github`, `anthropic-*`, known orgs over unknown)

Reject outright:
- Skills with 0 installs and no recognized owner
- Skills whose description reads as gibberish or AI-slop
- Skills that duplicate functionality already covered by user's existing skills (Phase 2 identified these)

### 3.3 Clone top 3-5 for review

**At this stage, clone — don't install.** Decisions about whether to install directly, extract gems, or skip happen AFTER you've read the candidate's actual content (step 3.5). Clone to a review area first:

```bash
mkdir -p <project>/skill-review
cd <project>/skill-review
git clone --depth 1 https://github.com/<owner>/<repo>.git <owner>-<repo>
```

Add `skill-review/` to the target project's `.gitignore` if not already there.

### 3.4 Locate each candidate's SKILL.md

The `@<skill-name>` in `owner/repo@skill-name` is fuzzy-matched. Find the actual SKILL.md:

```bash
find <project>/skill-review/<owner>-<repo> -name "SKILL.md"
```

Plugins may contain many skills — identify the one(s) matching the search.

### 3.5 Review each candidate and pick a disposition

For each candidate, read the full SKILL.md and assess:

| Dimension | Question |
|---|---|
| **Scope fit** | Does it cover what we need, or is it adjacent? |
| **Overlap** | Does it duplicate a user skill? (From Phase 2 inventory) |
| **Quality** | Are claims sourced? Are examples concrete? Is the prose AI-slop? |
| **Freshness** | When was it last updated? Any stale-looking content? |
| **Version fit** | Does its claimed framework version match the target project's stack? |
| **Unique value** | What gems would we extract that aren't already in user's skills? |

Based on the assessment, pick **one of three dispositions** per candidate:

| Disposition | When it's the right call | Action |
|---|---|---|
| **Install directly** | Perfect-match stack + actively maintained + official/reputable owner + zero overlap with existing user skills + content is current | `npx skills add <owner>/<repo>@<skill> -g -y` in Phase 4 |
| **Extract gems** | Partial fit — useful chunks exist but the whole skill doesn't fit, OR content needs project-specific tailoring, OR you want user-owned evolution | Extract cited rules into the user's existing skills (or a new project-specific skill) in Phase 6 |
| **Skip** | Irrelevant, duplicate of user skill, low quality, stale, or wrong version | No action; log the reason |

**The old rule was "never install directly, always extract".** That's been relaxed: if a candidate passes all five dimensions above AND the user wants upstream updates (via `npx skills update`), installing directly is the right call. The extract-gems path is for when you need *partial* content or *project-specific* tailoring.

In **autopilot mode**, the Phase 3 agent's per-candidate disposition is applied without confirmation. In **interactive mode**, the user sees each recommendation and can override via `AskUserQuestion`.

### 3.6 Produce the candidate review

Append to `<project>/.skill-forge/audit-report.md`:

```markdown
## Phase 3 — External Candidate Review

### Candidate: l3digital-net/claude-code-plugins@qt-packaging
- **Quality**: Good — references/qt-packaging.md has concrete signtool + spec file examples
- **Fit for us**: Partially duplicates pyside6-desktop/references/pyinstaller.md
- **Unique gems**: macOS notarization workflow (not currently covered)
- **Verdict**: Extract the notarization section → propose as a new rule in Phase 6. Do NOT install.

### Candidate: sharex/xerahs@build-windows-exe
- **Quality**: Good for .NET but irrelevant — we're Python
- **Fit for us**: Zero — mislabeled match
- **Verdict**: Skip entirely.

### Candidate: sickn33/antigravity-awesome-skills@scanning-tools
- **Quality**: Surface-level cheat sheet; red-team focused
- **Fit for us**: Zero — we do device discovery, not pentesting
- **Verdict**: Skip.
```

## Gap analysis

Also document **what's missing** — things the project needs that neither user's skills nor candidate skills cover:

```markdown
### Gaps (no existing skill covers)
1. **macOS notarization for Qt apps** — worth adding to pyside6-desktop references
2. **Driver signing workflows** — not needed now; flag for future
```

## Checkpoint — Phase 3 → 4 first-pass approval gate (MANDATORY in autopilot)

This is the **first write-consent gate**. Before any edit lands in `~/.claude/skills/`, the user sees every proposed Phase 4 change in plain English and approves via `AskUserQuestion`.

### Step A: Build the proposed change set

Combine:
- Every Phase 2 skill with a **Defect:** verdict → edit proposal
- Every Phase 3 candidate with disposition **install directly** → install proposal
- Every Phase 3 candidate with disposition **extract gems** → deferred to Phase 6 (NOT in this gate)

**"✓ Fits — leave alone" skills are excluded from the change set** — they become zero entries in this gate. (They remain in scope for Phase 5 research; research findings go through the Phase 5→6 gate.)

### Step B: Print the plain-English change blocks

For each proposed change, print:

```
┌─ Change <N> of <TOTAL> ───────────────────────────────────────┐
│ Skill:     <skill-name>
│ Action:    <Edit description | Fix YAML | Narrow filePattern | Add cross-ref | Install from <owner/repo> | …>
│
│ What this changes:
│   <1-3 bullets describing the concrete diff — before → after where useful>
│
│ What you gain:
│   <concrete observable benefit — "skill will now actually load (YAML currently broken)"
│    NOT "description will be shorter">
│
│ Risks:
│   <honest downsides — "description wording is subjective", "install brings upstream
│    updates outside your direct control", "new filePattern might miss edge-case files">
│
│ Source of this proposal:
│   <Phase 2 audit ID, Phase 3 candidate review, project memory file, etc.>
│
│ Reversible:
│   <yes via backup tarball / yes via git / no — destructive>
└───────────────────────────────────────────────────────────────┘
```

If there are zero changes after filtering, skip to Step D (healthy-library exit).

### Step C: Ask for approval via `AskUserQuestion`

```
Question: "<N> changes proposed — approve?"
Header:   "Phase 3 → 4 approval"
Options:
  - Label: `Approve all`
    Description: Apply all <N> changes; creates backup tarball first
  - Label: `Review each`
    Description: Walk change-by-change with approve/skip
  - Label: `Skip installs only`
    Description: Apply edits to existing skills; skip the <K> new installs
  - Label: `Cancel`
    Description: Make no changes; advance to Phase 5 decision
```

If **Review each**, loop one `AskUserQuestion` per change with options `[Approve / Skip / Show more / Cancel review]`. "Show more" prints the full diff for that skill then re-asks.

### Step D: Healthy-library early exit

If the change set is empty (all skills "Fits — leave alone" AND no install-worthy candidates):

```
Question: "Library is healthy — no edits proposed. Next?"
Header:   "Phase 3 → 4 (healthy)"
Options:
  - Label: `Run Phase 5 research anyway`
    Description: Research may surface new verified rules to add to existing skills
  - Label: `Exit to summary`
    Description: Skip to Phase 9; no changes, no tarball
  - Label: `Explain more`
    Description: What Phase 5 research looks like when nothing needs fixing
```

### Justification bar — reject weak gains BEFORE presenting

Before Step B, filter the proposed change set. A change must state a **named, observable gain**. Reject (and drop silently — don't burden the user with choices that shouldn't exist):

| Weak justification | What to do |
|---|---|
| "Shorter description" | Drop unless current description is >300 chars or triggers false-positives |
| "Clearer formatting" | Drop unless current format breaks loader or produces a parse error |
| "More consistent with other skills" | Drop unless inconsistency caused a real confusion reported in memory |
| "Could be more specific" | Drop unless current is vague enough to false-trigger |

If you can't fill the `What you gain` line with a concrete observable benefit, the change doesn't belong in the gate. Don't pad the list.


## Skipping this phase

`--skip-find` — useful if the project's domain is so specific that no community skills apply.

## Cleanup

After Phase 6 has extracted any gems, delete `<project>/skill-review/`. Keep `audit-report.md` for provenance.
