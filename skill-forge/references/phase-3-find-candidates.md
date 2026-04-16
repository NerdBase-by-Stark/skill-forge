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

**Never use `npx skills add` at this phase.** Clone the source repos directly to a review area:

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

### 3.5 Review each candidate

For each candidate, read the full SKILL.md and assess:

| Dimension | Question |
|---|---|
| **Scope fit** | Does it cover what we need, or is it adjacent? |
| **Overlap** | Does it duplicate a user skill? (From Phase 2 inventory) |
| **Quality** | Are claims sourced? Are examples concrete? Is the prose AI-slop? |
| **Freshness** | When was it last updated? Any stale-looking content? |
| **Unique value** | What gems would we extract that aren't already in user's skills? |

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

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Candidates reviewed — next step?"
Header:   "Phase 3 → 4"
Options:
  - Label: `Apply clear wins`
    Description: Phase 4: description tightening, filePattern narrowing, cross-refs
  - Label: `Show candidate details`
    Description: Print the full candidate analysis before advancing
  - Label: `Explain more`
    Description: Describe what Phase 4 does in detail, then re-ask
  - Label: `Stop`
    Description: Exit; candidate review preserved
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 4 creates a backup tarball of ~/.claude/skills/ first, then applies high-confidence edits: shorten overlong descriptions, narrow overly-broad filePatterns, add cross-references between related skills, fix broken links. No new rules added (that's Phase 6 after research). Produces first-pass-changes.md. Takes ~1 minute.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

`--skip-find` — useful if the project's domain is so specific that no community skills apply.

## Cleanup

After Phase 6 has extracted any gems, delete `<project>/skill-review/`. Keep `audit-report.md` for provenance.
