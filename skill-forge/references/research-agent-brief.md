# Research Agent Brief Template

Every Phase 5 research agent uses this template. Fill in the bracketed sections before spawning.

## Spawn parameters

```
subagent_type: search-specialist   # or "general-purpose" if search-specialist isn't available
description: <stream N: short title — max 5 words>
run_in_background: true
```

Check available subagent types first — `search-specialist` is ideal but not universal. `general-purpose` works in any Claude Code setup.

### Permission-mode safety rail (CRITICAL)

If the supervisor is running with `bypassPermissions`, `acceptEdits`, or `auto` permission mode, **sub-agents inherit that mode unconditionally and it cannot be overridden per sub-agent** (per Anthropic's official sub-agent docs, 2026). In those modes, a denylist in the brief is NOT sufficient — the sub-agent can auto-approve any tool that isn't explicitly forbidden.

**Use a `tools:` allowlist** in every sub-agent spawn when any permissive parent mode might be active:

```yaml
tools: Read, Grep, Glob, WebSearch, WebFetch, Firecrawl, Write
```

This is enforced at the Claude Code layer (not just in the prompt), so a compromised or misled sub-agent cannot exceed the allowlist. Denylists (`disallowedTools:`) are insufficient under `bypassPermissions` — always prefer the allowlist when the parent is permissive.

### Plugin-skill AskUserQuestion bug (note for users)

A known bug (GitHub Issue #29547) causes `AskUserQuestion` to silently return empty answers when called from inside a Claude Code *plugin* skill — the permission evaluator bypasses the user-interaction check. **Users who install skill-forge as a plugin (not a regular user-space skill) may find consent gates silently return empty answers with Claude hallucinating selections.** Test consent gates outside plugin context before relying on them. As of 2026-04-19, user-space skills at `~/.claude/skills/<name>/` (the default install path) are not affected; only plugin-packaged skills trigger the bug.

## Prompt template (copy then fill)

> **Every filled brief MUST contain the Strict Scope block verbatim.** Phase 5's pre-spawn assertion grep's for the literal phrase `STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.`; spawn aborts if missing. Do not reword.

````
You are researching <TOPIC> to add verified rules to a <SKILL-TARGET> skill.

## STRICT SCOPE — OUTPUT IS FILE-WRITE ONLY.

Your deliverable is exactly one markdown file at the output path specified below. You MUST NOT:

- Run `git` (any subcommand) — no `git checkout`, `git branch`, `git commit`, `git push`, `git fetch`, `git merge`, `git rebase`, `git tag`, `git reset`, `git stash`, `git remote`, nothing.
- Run `gh` (any subcommand) — no PR creation, no issue creation, no releases, no workflow triggers.
- Create, switch to, or push any branch (local or remote).
- Create any commit under any name or author.
- Open, comment on, or modify any pull request or issue.
- Trigger any remote write (CI, webhooks, deployments).
- Modify any file outside the specified output path.
- Call any other Agent / sub-agent — no recursive spawning.

If during research you believe a git/gh action would be useful (e.g. "this project should have a PR opened for X"), STOP and record the recommendation in your research doc under a heading `## Escalations — supervisor decides`. The supervisor will decide whether to execute; you do not.

You **cannot** spawn sub-sub-agents — this is a system-enforced limitation in Claude Code per Anthropic's official sub-agent documentation. `Agent(agent_type)` has no effect when called from inside a sub-agent. If you need parallel work, STOP and record the recommendation under Escalations for the supervisor to fan out.

You **cannot** call `AskUserQuestion` — the tool is unavailable to sub-agents (ref: GitHub Issue #18721). If you encounter a decision that needs human input (e.g. "should we include this source despite its paywall?"), record the options and your recommendation under Escalations; the supervisor will present the choice to the user.

Violating this scope causes the supervisor's post-Phase-5 rogue-agent check to flag your output and potentially close/delete whatever you created. Stay in your lane.

## Project context
<PROJECT NAME> is a <STACK SUMMARY: language, framework, purpose>. Version <X.Y.Z>, preparing <NEXT VERSION>. Primary platform: <Windows/macOS/Linux/etc>.

Already known (do NOT re-research or re-explain):
- <BULLET 1: known fact the user's skill already covers>
- <BULLET 2>
- <BULLET 3>

Pain points we want solved:
- <CONCRETE PAIN 1>
- <CONCRETE PAIN 2>

## Your research task
Find **verified, non-obvious** information on:

1. <NARROW TOPIC 1> — focus on <specific angle>
2. <NARROW TOPIC 2>
3. <NARROW TOPIC 3>
4. <NARROW TOPIC 4>
5. <NARROW TOPIC 5>
6-10. <additional topics, each as narrow as above>

For each: <primary verification criterion — official docs, confirmed GitHub issues, CA docs, etc.>

## Verification requirements
- **Every factual claim must cite an authoritative source** (URL + access date)
- Accept: official project docs, GitHub issues with confirmed resolution (not just "someone said"), vendor documentation, authoritative blogs by domain experts
- Reject: speculative forum posts, single-source blog claims without corroboration, advice over 3 years old without re-verification
- If you can't verify, label the claim `UNVERIFIED` and explain why — do NOT silently drop or omit

## Do NOT fabricate
If an API/flag/tool doesn't exist in the docs you can find, say so. Don't invent plausible-looking names. Don't assume version-specific behavior without version-specific citations. When in doubt, say "couldn't verify" rather than guess.

## Output format
Write findings to `<ABSOLUTE OUTPUT PATH>` using this structure:

```markdown
# Stream <N>: <Title>

## Research Summary
<what was researched, what was verified, what was skipped and why>

## Verified Gems
### Gem 1: <short title>
<finding with concrete code/config if relevant>
**Source:** [Title](URL) (accessed YYYY-MM-DD)

### Gem 2: ...

## Proposed Skill Rules
Ready-to-paste rules in this format:

### Rule: <title>
<one paragraph prose>
```code if relevant```
**Source:** <URL>

## Anti-Patterns / Folklore to Ignore
<things repeated widely but unsupported by evidence>

## Open Questions / Unverified
<things worth revisiting, explicitly marked>

## Sources
<numbered list of URLs with 1-line descriptions + access dates>
```

## Scope
Target <5-10> verified gems, <3-8> proposed rules. Better to have 5 solid rules than 15 speculative ones. Maximum <600-700> lines total.

## Tools

**Check local tools first.** The Phase 1 profile lists MCP servers (`profile.available_mcp_servers`) and local knowledge bases (`profile.local_knowledge_bases`) already available in this environment. A code-index MCP that already knows the target repo, a docs-index MCP, a domain KB, or a memory MCP that may contain prior findings — all of these are cheaper and more reliable than web research. Try them before reaching for the web. An MCP-derived answer is still a cited answer (record the MCP name + the path/result it returned).

If the relevant local tool is unavailable or doesn't cover the question, proceed to web research. Preference order: `firecrawl` MCP → `WebSearch`+`WebFetch` → other web MCPs. Quality over breadth. Grep GitHub issues for confirmed-fix; read official docs for primary-source API behavior.
````

## Filling checklist

Before spawning, verify:

- [ ] `<TOPIC>` is narrow enough that an agent can finish in one session
- [ ] `<PROJECT NAME>`, `<STACK SUMMARY>`, `<VERSION>` are taken from Phase 1 profile
- [ ] `Already known` bullets come from the user's existing skills (Phase 2 audit)
- [ ] `Pain points` are real (from user's memory or CLAUDE.md — not invented)
- [ ] Each numbered topic is a distinct angle (no duplication with other streams)
- [ ] Output path is under `<project>/docs/skill-research/0N-<slug>.md` with the right N
- [ ] Gem/rule targets are realistic for the topic breadth

## Example filled brief

See the `example-research/` directory in the skill-forge repo (https://github.com/NerdBase-by-Stark/skill-forge/tree/main/example-research) for 7 concrete output examples produced from this template. Each is a complete, verified-source research doc covering a distinct domain — use them to calibrate what "good" Phase 5 output looks like.
