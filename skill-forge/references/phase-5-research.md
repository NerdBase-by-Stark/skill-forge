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

## Mandatory security stream (auto-added for authenticated backends)

Before freeform stream planning, check Phase 1 profile for authenticated-backend triggers:

```
Triggers → always add a security-audit stream:
  supabase, firebase, auth0, jwt, express-session, passport, clerk,
  lucia, next-auth, nextauth, iron-session, cookie-session
```

If any trigger is present, inject a non-optional security stream:

- **Topic:** Authentication + session-token handling + RLS / authorization policies specific to the detected backend
- **Model:** Opus (higher verification rate on security-critical claims per 2026-04-19 cross-model evidence)
- **Priority:** Stream #1 in the plan — never deferred, never skipped

Rationale: The `getSession()` trust bug and RLS indexing requirement (biltong-buddy run) are security findings that compromise production if missed. Model choice is secondary to stream inclusion — the failure mode is "no stream covered this," not "the wrong model ran this stream."

Users can override via `--skip-security-stream` but the CLI warns loudly. This is an epistemic safety rail, not a cost preference.

## Dual-research opt-in (--dual-research)

By default, Phase 5 runs single-model research (supervisor's model, typically Opus). The `--dual-research` flag enables topic-partitioned dual-model research:

**How the split works:**

| Stream type | Default model | Rationale |
|---|---|---|
| Core framework/library rules (React, Vite, Tailwind, Capacitor, Supabase) | Opus | Verification-critical; 100% source-verification rate matters |
| Security / auth / session handling | Opus | High-stakes, documentation precision required |
| Deployment / CDN / build config (Cloudflare, Vercel, Railway, CI/CD) | Sonnet | Breadth sweep; target-codebase examination strength |
| Platform / App Store / vendor deadlines | Sonnet | Fresh-docs discovery strength |
| State management / component-level regressions | Sonnet | Codebase-grep strength on actual usage patterns |
| Testing frameworks | Either (supervisor picks) | Both work well |

**Hard rule:** topic partition must be complete before any brief is written. No overlap between Opus and Sonnet streams. The same topic must never be assigned to both models — that's wasted tokens for no new coverage.

**Cost expectation:** +$1.50-2.50 over single-model research, depending on stream counts.

**Evidence base:** 2026-04-19 biltong-buddy cross-model comparison showed zero topic overlap between model-assigned streams produced complementary findings (Sonnet surfaced 7 project-specific bugs Opus missed; Opus surfaced 4 security/framework bugs Sonnet missed). The complementarity comes from topic assignment, not parallel-same-stream runs — which the justification bar would reject as redundant.

Present the split at the Phase 4→5 cost gate as part of the cost breakdown:

```
Phase 5 research plan (--dual-research enabled):
  Opus streams (4): Supabase auth+RLS (mandatory-security), React19 rules, Playwright, Vitest
  Sonnet streams (3): Cloudflare Pages CSP, Zustand v5 patterns, App Store preflight
  Estimated cost: ~$5-7 ( ~$3-4 Opus + ~$2-3 Sonnet )
```

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

## Pre-spawn git state snapshot (MANDATORY)

Because agents run in background, their tool calls (including any `git`/`gh`) are invisible to the supervisor until completion. To detect sub-agents that step outside their output-only scope, snapshot git/PR state **before** spawning.

In the target project directory:

```bash
cd <project_root>
mkdir -p .skill-forge
{
  echo "### HEAD"
  git rev-parse HEAD
  echo
  echo "### local branches"
  git branch --format '%(refname:short)'
  echo
  echo "### remote branches"
  git branch -r --format '%(refname:short)'
  echo
  echo "### open PRs authored by @me"
  gh pr list --author @me --state open --json number,headRefName,title --jq '.[]' 2>/dev/null || echo "(gh not available or no auth)"
} > .skill-forge/git-snapshot-pre-phase5.txt
```

Do this **before any Agent tool call in Phase 5**. The snapshot is the baseline for §5.9's rogue-agent check.

## Mandatory scope clause in every agent brief

Every filled research brief MUST contain this verbatim clause (copied from `references/research-agent-brief.md §Strict scope`):

```
STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.
Do NOT run: git (any subcommand), gh (any subcommand), branch creation,
commit, push, fetch, merge, rebase, PR creation, issue creation, or any
command that writes to a remote. Do NOT modify any file outside the
specified output path. If you believe a git/gh action would be useful,
STOP and record the recommendation in your research doc under an
"Escalations" heading. The supervisor will decide, not you.
```

Before calling the Agent tool, assert the prompt string contains the phrase `STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.` verbatim. If missing, abort spawn and fix the prompt.

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

## 5.9 Rogue-agent check (MANDATORY before Phase 6)

After all agents complete and the research index is written, diff current git/PR state against the pre-Phase-5 snapshot:

```bash
cd <project_root>
{
  echo "### HEAD"
  git rev-parse HEAD
  echo
  echo "### local branches"
  git branch --format '%(refname:short)'
  echo
  echo "### remote branches"
  git branch -r --format '%(refname:short)'
  echo
  echo "### open PRs authored by @me"
  gh pr list --author @me --state open --json number,headRefName,title --jq '.[]' 2>/dev/null || echo "(gh not available or no auth)"
} > .skill-forge/git-snapshot-post-phase5.txt

diff -u .skill-forge/git-snapshot-pre-phase5.txt .skill-forge/git-snapshot-post-phase5.txt > .skill-forge/git-snapshot-diff.txt || true
```

**Trigger conditions for an anomaly:**
- HEAD moved (a commit landed on the checked-out branch)
- New local branch appeared
- New remote branch appeared
- New open PR by `@me` appeared
- Any pre-existing branch's head moved (new commit pushed)

If any condition matches, **do not advance to Phase 6**. Call `AskUserQuestion`:

```
Question: "Research agent(s) modified git/PR state — review?"
Header:   "Phase 5 — unauthorized activity"
Options:
  - Label: `Show the diff`
    Description: Print the pre/post snapshot diff so you can see what happened
  - Label: `Close & delete (recommended)`
    Description: Close any new PRs, delete any new branches (local + remote), reset HEAD if moved
  - Label: `Keep`
    Description: Leave the new branches/PRs in place; note in run-log; continue to Phase 6
  - Label: `Investigate before continuing`
    Description: Pause pipeline; user inspects manually before deciding
```

On **Close & delete**, for each new branch / PR:
- `gh pr close <N> --comment "Closed — opened by skill-forge research sub-agent outside scope." --delete-branch`
- `git branch -D <local-branch>` (if exists locally)
- `git push origin --delete <remote-branch>` (if `--delete-branch` didn't already)
- If HEAD moved on the working branch, show the offending commit(s) and ask: `[revert / reset / keep]` — never auto-reset.

Log the anomaly and the chosen resolution to `.skill-forge/rogue-agent-log.md` regardless of choice.

**Why this check exists:** `run_in_background: true` makes sub-agent tool calls invisible to the supervisor until completion. Without this diff, a sub-agent that ignored the scope clause (or was mis-briefed) can silently commit, push, or open PRs — discovered only at Phase 9 write-up. This check catches it before Phase 6 compounds the blast radius.

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

## Checkpoint — advance to Phase 6

Phase 5 has two mandatory stops:
1. **Rogue-agent check (§5.9)** — runs immediately after all research agents complete. If clean, advance silently. If anomalies, ask and resolve before proceeding.
2. **Phase 5 → 6 approval gate** — lives at the top of Phase 6 (see `references/phase-6-second-pass.md §6.0`). The gate presents every proposed Phase 6 change in plain English with justification before any edit to `~/.claude/skills/`.

Once §5.9 is clean and the research index is written, auto-advance to Phase 6's §6.0 gate. Do not ask a separate "apply findings?" question here — that was always redundant with the gate.

If the user Cancels at §5.9, pipeline stops; research docs preserved; user can resume with `--from-phase=5` after manual cleanup.


## Skipping this phase

`--skip-research` — uses existing `docs/skill-research/*.md` if present. Warns if those are older than 90 days.
