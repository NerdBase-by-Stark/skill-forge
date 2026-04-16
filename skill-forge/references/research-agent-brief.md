# Research Agent Brief Template

Every Phase 5 research agent uses this template. Fill in the bracketed sections before spawning.

## Spawn parameters

```
subagent_type: search-specialist   # or "general-purpose" if search-specialist isn't available
description: <stream N: short title — max 5 words>
run_in_background: true
```

Check available subagent types first — `search-specialist` is ideal but not universal. `general-purpose` works in any Claude Code setup.

## Prompt template (copy then fill)

````
You are researching <TOPIC> to add verified rules to a <SKILL-TARGET> skill.

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
Use whatever web-research tools you have available — in rough preference order:

1. **`firecrawl` MCP** (if installed — best markdown output for LLM context)
2. **`WebSearch` + `WebFetch`** (built-in Claude Code tools — universally available)
3. **Other web/search MCPs** (Tavily, Perplexity, Brave Search, etc. — use what you have)

Any of these work. Prioritize quality of sources over which tool you used. Grep GitHub issues for confirmed-closed-with-fix. Read official docs for the primary source of truth on API behavior.

Quality over breadth.
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
