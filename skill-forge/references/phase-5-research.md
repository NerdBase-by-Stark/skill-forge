# Phase 5 — Deep Research

**Goal:** Ground-truth facts from authoritative sources for gaps identified in Phase 2 + candidates from Phase 3. This is the expensive phase.

**Depends on:** Phases 1-4.

## Consent before spending

Before spawning any agents, print the research plan and get explicit user consent:

```
Phase 5 will spawn search-specialist agents to produce verified-source research docs.

Proposed streams (5):
  1. PyInstaller 6.x edge cases (focus: hiddenimports, Windows DLL bugs)
  2. Code signing updates (focus: Azure Trusted Signing, post-2024 SmartScreen)
  3. Qt 6 threading patterns (focus: QtAsyncio maturity, lambda GC)
  4. Windows CI/CD for Python (focus: GitHub Actions, OIDC signing)
  5. [Candidate gem] macOS notarization for Qt (from Phase 3 candidate review)

Estimated cost: ~$3-5 in agent tokens.
Output: <project>/docs/skill-research/0N-<topic>.md (5 files)
Parallelism: batches of 3 (compliance cap).

Proceed? [yes / fewer streams / custom streams / stop]
```

Never proceed without consent.

## Stream design principles

Each stream should be:
- **Narrow enough to research in one session** (not "all of Python packaging" — rather "PyInstaller 6.x edge cases affecting PySide6 apps on Windows 11")
- **Backed by a gap in Phase 2 or a candidate in Phase 3** (no speculative streams)
- **Distinct from other streams** (overlap = duplicated research cost)
- **Have a clear verification criterion** — what sources will count as "verified"?

## Use the agent brief template

See `references/research-agent-brief.md` for the fill-in-the-blank template. Every research agent gets:

1. Project context (from Phase 1 profile — stack, version, pain points)
2. The specific research question (narrow, one stream)
3. What the agent should find (list of sub-topics)
4. Verification requirements (authoritative sources required; mark `UNVERIFIED` otherwise)
5. Output format (our standard markdown structure with Gems, Rules, Anti-Patterns, Sources)
6. Output file path (`<project>/docs/skill-research/0N-<slug>.md`)
7. Length cap (typically 500-700 lines)

## Spawning discipline

- **Batches of 3, run in parallel within a batch** — multiple Agent tool calls in a single message
- **Sequential across batches** — wait for Batch 1 to finish before Batch 2
- **`search-specialist` subagent type if available** — it's the best fit for this task. If that subagent isn't registered in the user's setup, fall back to `general-purpose`. Either one uses whatever web-research tools are available (`firecrawl` MCP, built-in `WebSearch`/`WebFetch`, Tavily, Perplexity, etc.) plus multi-source verification.
- **`run_in_background: true`** — so the main thread can continue doing other things while agents work
- **Single-sentence telemetry description** per agent — so we know what's running

## While agents run

The main Claude context shouldn't sit idle. Use the time for:
- Reading Phase 3 candidate gems for things to manually extract
- Preparing Phase 6 edit scaffolds (where will each type of finding go?)
- Updating the audit report with Phase 4 changes

But don't spawn more agents, edit active skills, or do anything that might conflict.

## On agent completion

For each completed agent:
1. Verify the file was written at the expected path
2. Quick-read the "Research Summary" section — did it cover the right scope?
3. If summary indicates a wrong turn or low-quality output, spawn a REPLACEMENT agent with a tighter brief (document in log)
4. If summary looks good, proceed

## Reject agent output if

- The "Sources" section is missing or has <3 distinct domains
- Verified Gems count is < 3 (not enough signal)
- Most claims are marked `UNVERIFIED` (agent went off-mission)
- The doc mentions libraries or versions that don't exist (fabrication — check by curl-ing the PyPI/GitHub URL)

Replacement agents don't cost 3× — they usually resolve in 1 retry because the first agent mapped the space.

## Produce the research index

After all agents complete, write `<project>/docs/skill-research/INDEX.md`:

```markdown
# Research Docs Index — <date>

| # | Topic | Gems | Rules proposed | File |
|---|---|---|---|---|
| 1 | PyInstaller 6.x edges | 9 | 8 | [01-pyinstaller-edges.md](01-pyinstaller-edges.md) |
| 2 | Code signing | 10 | 6 | [02-code-signing.md](02-code-signing.md) |
| ... | | | | |

## Stream quality
- Gems with full source verification: 42/47
- Gems marked UNVERIFIED: 5
- Rejected agent outputs: 0
```

## Checkpoint — call `AskUserQuestion`

Print the phase summary as text (5-10 lines — what was done, counts, notable findings). Keep it short. Then **call `AskUserQuestion`** (never a text prompt — users skim and miss them):

```
Question: "Research complete — apply findings?"
Header:   "Phase 5 → 6"
Options:
  - Label: `Apply findings to skills`
    Description: Phase 6: extract verified gems into existing or new skills
  - Label: `Show research index`
    Description: Print summary of what each doc found before advancing
  - Label: `Explain more`
    Description: Describe what Phase 6 does in detail, then re-ask
  - Label: `Stop`
    Description: Exit; research docs preserved for later --from-phase
```

Option labels are short on purpose — users shouldn't have to read a paragraph to pick. Descriptions show below each label in the dialog.

### If user picks "Explain more"

Print this detailed explanation to the user, then **re-call `AskUserQuestion` with the same options** (the user will pick one of the non-Explain-more options the second time):

> Phase 6 reads all research docs, classifies each proposed rule (ADD to existing / ADD as new skill / FIX stale content / REJECT / DEFER), applies the changes with source citations, and logs rejections with reasons. May create new skills for cohesive rule sets that don't fit existing scopes. Produces second-pass-changes.md + rejections.md. Takes 3-5 minutes.

Never loop more than twice — if they pick "Explain more" again, default to "Stop" and ask them what they'd actually like to do.


## Skipping this phase

`--skip-research` — uses existing `docs/skill-research/*.md` if present. Warns if those are older than 90 days.
