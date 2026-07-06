# Phase 5 — Deep Research

**Goal:** Ground-truth facts from authoritative sources for gaps identified in Phase 2 + candidates from Phase 3. This is the expensive phase.

**Depends on:** Phases 1-4.

## Consent before spending

Before spawning any agents: **print the research plan as text** (streams, foci, cost estimate, output paths, parallelism — like the example below), then **get consent via `AskUserQuestion`** — never a text "Proceed?" prompt (SKILL.md checkpoint protocol).

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
```

```
Question: "Run this research plan? (~$3-5)"
Header:   "Phase 4 → 5"
Options:
  - Label: `Run all streams`
    Description: Spawn the full plan above, batched 3 at a time
  - Label: `Fewer streams`
    Description: You pick which streams to keep; the rest are dropped
  - Label: `Custom streams`
    Description: You describe changes (add/replace topics); plan is revised and re-asked
  - Label: `Stop`
    Description: Skip research entirely; pipeline continues to Phase 7
```

Defined follow-ups (do not improvise):
- **Fewer streams** → ask one follow-up `AskUserQuestion` listing each stream as an option (multi-select semantics via "keep/drop" labels, or numbered options in batches of 4); rebuild the plan from the kept set, print it, and re-ask this gate once.
- **Custom streams** → take the user's free-text change request, revise the plan, print the revised plan, and re-ask this gate once. If it still isn't right, iterate — but each iteration re-asks; never spawn on an unconfirmed plan.
- **Empty/missing answer** → STOP per SKILL.md's empty-answer rule. Never spawn agents on inferred consent.

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
7. Length cap (700 lines maximum — `validate-research.sh` enforces it)

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
  echo "### all refs with SHAs (branch-head moves are only detectable if SHAs are recorded)"
  git for-each-ref --format '%(refname) %(objectname)' refs/heads refs/remotes
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

**The check is a command, not a mental note.** Write every filled brief to disk before spawning, then gate on grep:

```bash
mkdir -p .skill-forge/briefs
# ... write the filled brief to .skill-forge/briefs/stream-N.md ...
grep -qF 'STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.' .skill-forge/briefs/stream-N.md \
  || { echo "ABORT spawn: scope clause missing from stream-N brief"; }
```

The Agent prompt is then the brief file's content, so the checked artifact and the spawned prompt cannot diverge. Persisted briefs also make post-hoc audit of what each agent was told possible.

**Tools allowlist is mandatory on every spawn** (not just under permissive modes — you often can't verify the mode): pass an explicit read-and-research allowlist per `research-agent-brief.md §Permission-mode safety rail` (e.g. `Read, Grep, Glob, WebSearch, WebFetch, Write`). The allowlist is enforced by the harness; the scope clause is enforced by nothing.

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

**Hang handling:** research agents normally finish in 10-20 minutes. If an agent has been running more than 40 minutes (2× the upper expectation) with no output file, treat it as hung: mark the stream failed in the run log, do not wait further, and decide replacement per the cap below. Never let one hung agent stall the phase indefinitely.

## On agent completion

For each completed agent:
1. Verify the file was written at the expected path
2. **Run the deterministic validator — rejection is an exit code, not a vibe:**
   ```bash
   bash ~/.claude/skills/skill-forge/scripts/validate-research.sh docs/skill-research/0N-<slug>.md
   ```
   Non-zero exit = the doc fails the acceptance criteria below → automatic reject.
3. Quick-read the "Research Summary" section — did it cover the right scope? (The validator can't judge scope.)
4. Rejected or off-scope → spawn a REPLACEMENT agent with a tighter brief (document in log). **Hard cap: one replacement per stream.** If the replacement also fails, drop the stream, record it as a coverage gap for §5.5, and move on — no unbounded retry loops.
5. Validator passed and scope is right → proceed

## Reject agent output if (what the validator enforces)

- The "Sources" section is missing or has <3 distinct domains
- Verified Gems count is < 3 (not enough signal)
- Most claims are marked `UNVERIFIED` (agent went off-mission)
- Over the length cap
- The doc mentions libraries or versions that don't exist (fabrication — check by curl-ing the PyPI/GitHub URL; this one stays manual)

Replacement agents don't cost 3× — they usually resolve in 1 retry because the first agent mapped the space.

## 5.9 Rogue-agent check (MANDATORY before Phase 6)

After all agents complete and the research index is written, diff current git/PR state against the pre-Phase-5 snapshot:

```bash
cd <project_root>
{
  echo "### HEAD"
  git rev-parse HEAD
  echo
  echo "### all refs with SHAs (branch-head moves are only detectable if SHAs are recorded)"
  git for-each-ref --format '%(refname) %(objectname)' refs/heads refs/remotes
  echo
  echo "### open PRs authored by @me"
  gh pr list --author @me --state open --json number,headRefName,title --jq '.[]' 2>/dev/null || echo "(gh not available or no auth)"
} > .skill-forge/git-snapshot-post-phase5.txt

diff -u .skill-forge/git-snapshot-pre-phase5.txt .skill-forge/git-snapshot-post-phase5.txt > .skill-forge/git-snapshot-diff.txt || true
```

**Trigger conditions for an anomaly** (all derivable from the ref+SHA snapshot):
- HEAD moved (a commit landed on the checked-out branch)
- New local or remote ref appeared
- New open PR by `@me` appeared
- Any pre-existing ref's SHA changed (new commit pushed to an existing branch)

If any condition matches, **do not advance to Phase 6**. First classify the anomaly, then ask the question that matches it:

**Case A — new branches and/or PRs appeared** (with or without a HEAD move). Call `AskUserQuestion`:

```
Question: "Research agent(s) modified git/PR state — review?"
Header:   "Rogue check"
Options:
  - Label: `Show the diff`
    Description: Print the pre/post snapshot diff, then re-ask this question
  - Label: `Close & delete`
    Description: Recommended. Close new PRs, delete new branches (local + remote). If HEAD also moved, a follow-up question handles that separately
  - Label: `Keep`
    Description: Leave the new branches/PRs in place; note in run-log; continue to Phase 6
  - Label: `Investigate`
    Description: Pause pipeline; you inspect manually before deciding
```

On **Close & delete**, for each new branch / PR:
- `gh pr close <N> --comment "Closed — opened by skill-forge research sub-agent outside scope." --delete-branch`
- `git branch -D <local-branch>` (if exists locally)
- `git push origin --delete <remote-branch>` (if `--delete-branch` didn't already)

**Case B — HEAD (or a pre-existing branch's SHA) moved** — whether alone or after Case A cleanup. This always gets its own question; the Case A options do not cover it:

```
Question: "Commit(s) landed on <branch> during research — what now?"
Header:   "HEAD moved"
Options:
  - Label: `Show commits`
    Description: git log <old-sha>..<new-sha> --stat, then re-ask
  - Label: `Revert`
    Description: git revert the offending commit(s) — history preserved
  - Label: `Reset`
    Description: git reset --hard <old-sha> — history rewritten; only for unpushed commits
  - Label: `Keep`
    Description: Accept the commits; note in run-log; continue
```

Never auto-revert or auto-reset.

Log the anomaly and the chosen resolution to `.skill-forge/rogue-agent-log.md` regardless of choice.

**This check also applies to every later sub-agent spawn:** §5.5 catch-up research streams and the Phase 6 critique agent run in background too — snapshot before, check after, same procedure (see `phase-6-second-pass.md`).

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
