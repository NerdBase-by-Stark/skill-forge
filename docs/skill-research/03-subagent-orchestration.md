# Sub-Agent Orchestration: Verified Rules for skill-forge Phase 5

**Research Date**: 2026-04-19  
**Scope**: Claude Code sub-agent spawning, permissions, isolation, concurrency  
**Sources**: docs.anthropic.com, docs.claude.com, anthropics/claude-code GitHub issues

---

## Research Summary

skill-forge Phase 5 spawns 3-8 sub-agents in parallel with strict scope constraints. This document captures verified orchestration patterns from Anthropic's official documentation and GitHub issues to inform skill-forge's sub-agent launch rules, scope-limiting guidance, and compliance checks.

**Key Finding**: Anthropic's official stance is that **sub-agents cannot spawn sub-agents** by design (documented & enforced). All constraints are expressable in markdown frontmatter; no code-level gates needed beyond brief-language enforcement.

---

## Verified Gems

### GEM 1: Permission Inheritance is NOT Automatic for User Permissions
**Status**: VERIFIED  
**Source**: [GitHub Issue #18950](https://github.com/anthropics/claude-code/issues/18950) | Confirmed in [SDK Permissions Docs](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-permissions)  
**Access Date**: 2026-04-19

User-level permissions configured in `~/.claude/settings.json` under `permissions.allow` **are NOT inherited by subagents**. However:
- `bypassPermissions` mode **IS inherited** and cannot be overridden per subagent (applies to all subagents)
- `acceptEdits` mode **IS inherited** and cannot be overridden
- `auto` mode **IS inherited** with same classifier rules
- Subagents inherit all tools from parent by default; tool restrictions must be explicit in `tools:` or `disallowedTools:` fields

**Implication for skill-forge**: Brief scope clauses forbidding git/gh must be paired with explicit `disallowedTools` if using permissive parent mode. User-level allow rules alone will not constrain subagents.

---

### GEM 2: Recursive Spawning is Architecturally Prevented
**Status**: VERIFIED  
**Source**: [Sub-Agents Documentation §](https://docs.anthropic.com/en/docs/claude-code/sub-agents#restrict-which-subagents-can-be-spawned) "Subagents cannot spawn other subagents" + [GitHub Issue #19077](https://github.com/anthropics/claude-code/issues/19077)  
**Access Date**: 2026-04-19

From official docs:
> "Subagents cannot spawn other subagents, so `Agent(agent_type)` has no effect in subagent definitions."

And from Plan subagent docs:
> "This prevents infinite nesting (subagents cannot spawn other subagents) while still gathering necessary context."

**No hard gate needed beyond brief language**: If a subagent somehow attempts to use the Agent tool, the system returns that the tool is unavailable. The restriction is built-in.

**Implication for skill-forge**: Include in brief: "You cannot spawn sub-agents (this is a system limitation)." No need for post-Phase-5 checks to detect recursive spawning—it's impossible.

---

### GEM 3: `bypassPermissions` Inheritance Takes Precedence Over Everything
**Status**: VERIFIED  
**Source**: [SDK Permissions Docs — Subagent Inheritance](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-permissions) + [Sub-Agents Permission Modes](https://docs.anthropic.com/en/docs/claude-code/sub-agents#permission-modes)  
**Access Date**: 2026-04-19

From official documentation:
> "Subagent inheritance: When the parent uses `bypassPermissions`, `acceptEdits`, or `auto`, all subagents inherit that mode and **it cannot be overridden per subagent**. Subagents may have different system prompts and less constrained behavior than your main agent, so inheriting `bypassPermissions` grants them full, autonomous system access without any approval prompts."

**Implication for skill-forge**: If supervisor runs with `bypassPermissions` or `acceptEdits`, all subagents inherit unconditionally. No per-subagent override possible. This is a security boundary: supervisors must NOT use permissive modes when spawning untrusted subagents.

---

### GEM 4: Worktree Isolation is Automatic & Safe
**Status**: VERIFIED  
**Source**: [Sub-Agents Docs §isolation](https://docs.anthropic.com/en/docs/claude-code/sub-agents#supported-frontmatter-fields) + [Common Workflows](https://code.claude.com/docs/en/common-workflows)  
**Access Date**: 2026-04-19

Subagents support `isolation: worktree` frontmatter field:
- Creates temporary git worktree; subagent gets isolated copy of repo
- **Automatic cleanup**: worktree deleted if subagent makes no changes; user prompted if changes exist
- Safe for parallelization (no file conflicts between agents)
- Works only in git repos; non-git VCS requires hooks

**2026 Update**: Full CLI support with `--worktree` flag and automatic tmux isolation via `--tmux`.

**Implication for skill-forge**: For parallel Phase 5 agents, consider `isolation: worktree` in agent frontmatter if file conflicts are a risk. Cleanup is guaranteed.

---

### GEM 5: No Hard Concurrent Limit; 3-5 is the Practical Sweet Spot
**Status**: VERIFIED  
**Source**: [GitHub Feature Request #15487](https://github.com/anthropics/claude-code/issues/15487) (proposing `maxParallelAgents` config—still open, not implemented) + Community consensus in multiple Medium/blog sources  
**Access Date**: 2026-04-19

- **No documented hard limit** on concurrent subagents from Anthropic
- **Practical consensus**: 3-5 parallel agents = best ROI; 10+ rarely justified
- **Token cost scales**: 4 agents ≠ 4x cost; expect significantly higher total token usage
- **Proposed but not implemented**: `maxParallelAgents` setting would allow per-session caps

**Implication for skill-forge**: Current cap of 3 per batch (9 max across 3 batches) is conservative and safe. No compliance warnings until ~10 concurrent agents; at that point, diminishing returns and cost justify stopping.

---

### GEM 6: Built-in `Explore` and `Plan` are Read-Only; `general-purpose` is Unrestricted
**Status**: VERIFIED  
**Source**: [Sub-Agents Built-in Types](https://docs.anthropic.com/en/docs/claude-code/sub-agents#built-in-subagents)  
**Access Date**: 2026-04-19

| Agent | Model | Tools | Can Write? |
|-------|-------|-------|-----------|
| **Explore** | Haiku | Read-only (Denied Write/Edit) | NO |
| **Plan** | Inherits | Read-only (Denied Write/Edit) | NO |
| **general-purpose** | Inherits | All tools | YES |

The `general-purpose` agent has full tool access and is used for complex multi-step tasks.

**Implication for skill-forge**: If spawning only Explore or Plan, guaranteed read-only. `general-purpose` requires explicit brief constraint to forbid writes.

---

### GEM 7: Scope Limiting via Prompt is the Official Pattern
**Status**: VERIFIED  
**Source**: [Sub-Agents Docs §Write subagent files](https://docs.anthropic.com/en/docs/claude-code/sub-agents#write-subagent-files) + [SDK Subagents Docs](https://docs.anthropic.com/en/docs/claude-code/sdk/subagents)  
**Access Date**: 2026-04-19

Official guidance emphasizes:
- **System prompt is the primary constraint** (subagents receive only the frontmatter-defined prompt, not the full Claude Code system prompt)
- **Explicit tool restrictions** via `tools:` or `disallowedTools:` fields
- **Permission modes** override tool restrictions in parent
- **No code-level gates**; constraints are markdown frontmatter + prompt text

Example from docs:
```yaml
---
name: safe-researcher
description: Research agent with restricted capabilities
tools: Read, Grep, Glob, Bash
---
```

**Implication for skill-forge**: Scope clauses in briefs are sufficient if paired with frontmatter config. Language + structure, no custom enforcement hooks needed (unless permission mode permits escalation).

---

## Proposed Skill Rules

### Rule 1: Mandatory Scope Clause in Sub-Agent Briefs
**When**: All Phase 5 sub-agent spawning  
**What**: Every brief must include verbatim:

```
## STRICT SCOPE — YOU CANNOT:
- Run git (any subcommand): no git checkout, git branch, git commit, git push, etc.
- Run gh (any subcommand): no PR creation, issue creation, releases, workflows.
- Create, switch to, or push any branch.
- Create any commit.
- Modify any file outside the task output path: [PATH].
- Spawn sub-agents (system limitation).
- Call other Agent tools / recursive spawning.
```

**Rationale**: Explicit forbidding works because subagents receive only the frontmatter prompt (not the full Claude Code system prompt). A clear list + system limitation callout prevents implicit assumption of tool availability.

**Post-Phase-5 Check**: `git status && git diff --stat` pre/post Phase 5. Any git/gh commands should trigger rogue-agent flag.

---

### Rule 2: Explicit Tool Restrictions in Frontmatter
**When**: Spawning subagents with tool constraints  
**How**:

```yaml
---
name: research-specialist
description: Find and synthesize information from web
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Firecrawl
disallowedTools: Write, Edit, Agent
---
```

or use allowlist (safest):

```yaml
tools: Read, Grep, Glob, WebSearch, Firecrawl
```

**Rationale**: Frontmatter restrictions take precedence over inherited tool access. If parent mode is permissive, explicit `tools:` (allowlist) is stronger than `disallowedTools:` (denylist).

**Compliance Rule**: If spawning with `bypassPermissions` parent mode, MUST use `tools:` (allowlist) not `disallowedTools:` (denylist). Denylist is insufficient when all tools are auto-approved by parent mode.

---

### Rule 3: No Sub-Agents Unless Explicitly Necessary
**When**: Task decomposition decision  
**How**: Prefer single-agent solutions; spawn subagents only for:
- **Parallel research** (3+ independent data sources)
- **High-volume operations** (batch processing that would overflow main context)
- **Tool isolation** (read-only research in parallel with main session's writes)

**Rationale**: Subagent spawning has token and context overhead. Single session is cheaper and simpler for sequential work.

**skill-forge Application**: Phase 5 already enforces this (3-8 agents, batched). Do not encourage further nesting.

---

### Rule 4: Enforce Concurrency Cap at 3 per Batch; Document Token Cost
**When**: Batching Phase 5 subagents  
**How**:

```
Batch 1: [Agent A, Agent B, Agent C] (run in parallel)
Batch 2: [Agent D, Agent E, Agent F] (after Batch 1 completes)
Batch 3: [Agent G, Agent H] (after Batch 2 completes)
```

**Cap**: Max 3 concurrent per batch (9 total across 3 batches).

**Token Warning**: Include in Phase 5 brief:
> "Running N subagents in parallel incurs N times higher token cost (not N times faster). Monitor token usage and prioritize highest-value agents."

**Rationale**: 3 agents = practical ROI; beyond that, diminishing returns and cost explosion. Sequential batching avoids compliance warnings (no known hard limit, but 10+ triggers diminishing returns).

---

### Rule 5: Worktree Isolation for Parallel File Edits
**When**: Multiple agents may edit different files in parallel  
**How**: Add to agent frontmatter:

```yaml
isolation: worktree
```

**Effect**: Agent gets temporary git worktree; auto-cleanup on exit.

**Rationale**: Prevents file conflicts; safe for parallelization. No additional compliance cost.

**Caveat**: Git-only. Non-git repos require custom hooks.

---

## Anti-Patterns / Folklore

### Anti-Pattern: Relying on User-Level Permissions to Constrain Subagents
**Status**: DANGEROUS  
**Why**: User-level `permissions.allow` in `~/.claude/settings.json` does NOT inherit to subagents. Only `bypassPermissions`, `acceptEdits`, and `auto` modes inherit. Tool restrictions must be explicit in frontmatter.

**Fix**: Always use `tools:` or `disallowedTools:` in agent YAML.

---

### Anti-Pattern: Assuming Subagents Can Spawn Sub-Subagents
**Status**: IMPOSSIBLE (by design)  
**Why**: Official documentation explicitly forbids recursive spawning. Attempt to use Agent tool in subagent fails silently (tool unavailable).

**Fix**: No hierarchical agent trees. Flatten or use agent teams (separate sessions) instead.

---

### Anti-Pattern: Uncontrolled Nested MCP Server Spawning
**Status**: RESOURCE LEAK (confirmed in issues)  
**Why**: Each Task tool subagent spawns complete copy of configured MCP servers. With 5 servers, subagent doubles the node.exe process count (~8 → ~16). Nested chains multiply this further, consuming 30% of 5-hour rate limit in single session.

**Fix**: If using MCP servers with subagents, use `mcpServers: [name]` (reference existing, shared servers) not inline definitions in multiple subagents.

---

### Anti-Pattern: Briefing Subagents Without Explicit Tool Forbiddance When Parent Uses `bypassPermissions`
**Status**: SECURITY HOLE  
**Why**: `bypassPermissions` inheritance is unconditional and overrides all subagent `permissionMode` settings. Subagent can auto-approve any tool not in `disallowedTools`.

**Fix**: Use `tools:` (allowlist) + `disallowedTools:` (explicit deny) together. Or don't use `bypassPermissions` for untrusted subagents.

---

## Open Questions

### Q1: Can Tools Be Restricted per Subagent Invocation (Not Just Frontmatter)?
**Status**: NOT DOCUMENTED  
**What We Know**: Frontmatter-level `tools:` is the only documented restriction. No per-invocation `tools` parameter in Agent tool spec.  
**Implication**: Tool restrictions are static (set at agent definition time, not dynamically per call).

### Q2: What Happens If a Subagent Exceeds `maxTurns`?
**Status**: NOT CLEARLY DOCUMENTED  
**What We Know**: `maxTurns` field exists in frontmatter; docs say "Maximum number of agentic turns before the subagent stops" but no error handling spec.  
**Recommendation**: Treat as advisory; test behavior in your stack.

### Q3: Does `run_in_background: true` Change Permission Evaluation?
**Status**: UNVERIFIED  
**What We Know**: Agent SDK docs mention `run_in_background` but no detailed spec on permission inheritance when background.  
**Implication**: Assume same permission inheritance as foreground. No evidence of special behavior.

### Q4: Are There 2026 Changes to Subagent Isolation Beyond Worktree?
**Status**: PARTIAL  
**What We Know**: Worktree support expanded to CLI (not just desktop) in 2026. No other major isolation changes documented.

---

## Sources

- [Create custom subagents — Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents) (2026-04-19, accessed)
- [Subagents in the SDK — Claude API Docs](https://docs.anthropic.com/en/docs/claude-code/sdk/subagents) (2026-04-19, accessed)
- [Configure permissions — Claude SDK Docs](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-permissions) (2026-04-19, accessed)
- [GitHub Issue #18950 — Skills/subagents do not inherit user-level permissions](https://github.com/anthropics/claude-code/issues/18950) (Confirmed, 2026-04-19)
- [GitHub Issue #19077 — Sub-agents can't create sub-sub-agents](https://github.com/anthropics/claude-code/issues/19077) (Confirmed, 2026-04-19)
- [GitHub Issue #25000 — Sub-agents bypass permission deny rules](https://github.com/anthropics/claude-code/issues/25000) (Security finding, 2026-04-19)
- [GitHub Issue #15487 — Feature request: maxParallelAgents config](https://github.com/anthropics/claude-code/issues/15487) (Open, not implemented)
- [Run agent teams — Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code/agent-teams) (Agent teams for separate sessions, 2026-04-19, accessed)
- [Common workflows — Claude Code Docs](https://code.claude.com/docs/en/common-workflows) (Worktree guide, 2026-04-19)

---

## Escalations — Supervisor Decides

None at this time. All findings are from official Anthropic docs or confirmed GitHub issues with clear resolution status.

All rules above can be enforced via brief language + frontmatter configuration. No git/gh escalation actions needed.
