# skill-forge dry-run — qsys-plugins (2026-04-19)

Target: `~/ai/qsys-plugins`. Ran phases 1, 1.5, 2, 3 read-only. Stopped before Phase 4 (writes) and Phase 5 (paid research). Meta-goal: find gaps in skill-forge on a Lua/Q-SYS stack.

## Target shape (why this is a good stress test)

- Monorepo, heterogeneous: 15+ sub-projects, each a separate Q-SYS plugin with its own CLAUDE.md/README
- **No root-level project markers**: no `CLAUDE.md`, `README.md`, `package.json`, `pyproject.toml` at root (only `.git/`)
- File mix: 1,021 `.md`, 118 `.qplug`, 68 `.lua`, 42 `.py` (qpdk tool), 1 `.js`
- Stack: Q-SYS built-in Lua API (`Controls.` 13,664 uses, `SSH.` 889, `Timer.` 877, `TcpSocket` 35, `Component.` 28) + sparse `require("rapidjson")`
- **Nested project-local skills** under `cisco-modular-plugin/.claude/skills/` (3 skills skill-forge would never see)

Completely different stack profile from biltong (React/Next.js/Supabase). Good for surfacing JS/Python-centric assumptions.

---

## Gaps found — ranked by blast radius

### HIGH — breaks Phase 1 correctness

**G1. Phase 1.1 tolerates but doesn't flag "sparse root" monorepos.**
`.git/` alone satisfies the project-exists check, so the phase proceeds — but with nothing meaningful at root. No CLAUDE.md, no package.json. All signal is under sub-dirs.
- Current behaviour: silently proceeds, profile comes out anaemic
- Proposed fix: if no manifest files at root, scan depth-1 for sub-projects and ask user *"Target this sub-project or run against the monorepo as one profile?"*

**G2. Phase 1.2 hardcodes JS/Python/Rust manifests; no Lua/Q-SYS detection.**
Reference file at line 22 reads `pyproject.toml`/`package.json`/`Cargo.toml` only. Would not detect:
- `.qplug` files (Q-SYS plugin manifest + Lua in one file)
- `.rockspec` (LuaRocks)
- `Lua` as a first-class language
- Q-SYS API surface (built-in, not a declared dependency)

Proposed fix: add Lua/Q-SYS lane to the detection table.

**G3. Phase 1.5 profile-completeness grep is JS/Python only.**
Recipe hard-codes `jq` over `package.json` and `pip list`. No Lua equivalent. Evidence:
- Q-SYS stack API surface (13k `Controls.`, 900 `SSH.`, etc.) would never appear in a dependency-based grep — it's the *language runtime*, not a declared package
- Would report "grep_verified: true, heavy_imports_not_in_stack_tags: []" even though the *entire Q-SYS API surface* is undeclared

Proposed fix: the completeness check needs a language-specific dispatch. For Lua it's `grep -rEoh "^\s*require\s*\(?[\"'][^\"']+[\"']" + "^(Controls|Component|Timer|TcpSocket|SSH|HttpClient)\\."` → list top namespaces. For Q-SYS, the "stack" is the API surface used, not a dependency list.

### HIGH — silent mis-triage

**G4. Phase 1.3 relevance-match via filePattern returns ZERO hits for description-only skills.**
Of the 4 Q-SYS-relevant skills (`qsys-plugin-patterns`, `qsys-search`, `luacheck`, `cisco-codec-search`), **none declare `filePattern` or `bashPattern`**. Phase 1.3 filters skills by "filePattern matches ≥1 file in the target OR bashPattern fires" — all 4 fail this filter.

So the profile would record **zero relevant skills** for a project where four skills apply perfectly. Downstream effect: Phase 2 audit sees no in-scope skills, Phase 3 candidate queries are generic rather than gap-targeted, Phase 5 streams wouldn't use them.

Proposed fix (two options):
- **Immediate**: add a keyword fallback — if skill has no filePattern/bashPattern, match description keywords against profile tech_stack_tags
- **Better**: audit rule (new **TR004**) flagging any skill with neither filePattern nor bashPattern as "description-only — add triggers". This would push skills to add `filePattern: ["**/*.qplug", "**/*.lua"]`.

**G5. Audit has no rule for "skill missing all triggers".**
`audit.sh` TR001/TR002/TR003 check for over-broad or overlapping triggers, but nothing catches *absence*. Description-only triggering is lexically fragile and invisible to Phase 1 relevance matching. This is a silent-failure class.

### MEDIUM — monorepo blindness

**G6. Phase 1.3 only reads `~/.claude/skills/*/SKILL.md`; ignores project-local `.claude/skills/`.**
`cisco-modular-plugin/.claude/skills/` contains 3 skills (`qsys-plugin-development`, `qsys-lua-scripting`, `manufacturer-knowledge`) that are invisible to skill-forge.

For a monorepo, project-local skills are the most specific and most actionable to improve. Proposed fix: Phase 1 also scans `<project>/.claude/skills/` and sub-project `<project>/*/.claude/skills/` when the root has no single stack signature.

**G7. No monorepo-aware profile.**
`profile.json` is single-project. For this target, each sub-project has its own stack (one has Python for the QPDK tool, rest are Lua/Q-SYS). A single profile can't describe them honestly.

Proposed fix: optional `sub_projects: [{path, stack_tags, relevant_skills}, …]` structure when depth-1 scan finds multiple manifests.

### MEDIUM — Phase 3 noise

**G8. Phase 3 produces 100% false-positive candidates on niche stacks.**
Ran the three queries `"qsys lua plugin"`, `"lua static analysis luacheck"`, `"audio dsp matrix mixer"`:
- Q-SYS: top hits are neovim, OBS-Qt, FiveM/QBox (GTA5 mod), Hammerspoon (macOS automation) — all lexical collisions on "lua" or "q…"
- Lua static analysis: all hits are Roblox Luau (different language) or FiveM
- Audio DSP: Godot / Unreal Engine MetaSound / general mixing — nothing in the Q-SYS or commercial-AV space

Proposed fix: after step 3.1, if the top 5 candidates across all queries have owner reputation score = 0 AND install count < 100 AND no description overlap with profile keywords, short-circuit: print *"No install-worthy candidates — niche stack, consider authoring the gap yourself"* and skip to Phase 4. Phase 3 currently eats ~5 minutes of agent time evaluating nothing.

**G9. Reputation heuristic doesn't transfer to niche stacks.**
Phase 3 prefers `vercel-labs`, `github`, `anthropic-*`. For Q-SYS, there is no equivalent brand — the domain-expert skill is whichever individual wrote it. Popularity is an inverted signal here. Needs a per-stack override or a note in the reference.

### LOW — already works, worth noting

**G10. `scripts/audit.sh` works cleanly on Q-SYS skills.** Ran against 4 Q-SYS skills:
- `qsys-plugin-patterns`: 2× RI002 orphan references — real findings
- `qsys-search`: FM003 description 337 chars (over 300) — real finding
- `qsys-search`: 386 lines / ~2542 tokens — at progressive-disclosure threshold
- `cisco-codec-search`: 425 lines / ~3024 tokens — **over** 2,500-token guidance, candidate for split
- `luacheck`: clean

Audit is stack-agnostic and caught real issues. Keep.

**G11. Memory system picked up prior runs correctly.** MEMORY.md index loaded, prior biltong run context visible. No regression.

---

## Recommendations — in priority order

| # | Gap | Patch | Effort | Cost |
|---|-----|-------|--------|------|
| 1 | G4/G5 | New audit rule **TR004** — skill has no filePattern AND no bashPattern → WARNING; Phase 1.3 keyword-fallback to description | 30 min | 0 |
| 2 | G3 | Phase 1.5 language dispatch — add Lua branch grepping API namespaces + require() | 20 min | 0 |
| 3 | G1/G7 | Phase 1.1 monorepo detection — if sparse root, depth-1 scan and ask | 30 min | 0 |
| 4 | G6 | Phase 1.3 also inventories `<project>/.claude/skills/` and sub-project skills | 15 min | 0 |
| 5 | G8 | Phase 3 niche-stack short-circuit — if top hits have no owner rep + no keyword overlap, skip | 15 min | 0 |
| 6 | G2 | Phase 1.2 add Lua/Q-SYS manifest detection row | 10 min | 0 |
| 7 | G9 | Phase 3 reference doc — note reputation signal inverts for niche stacks | 5 min | 0 |

All cheap. Same pattern as the 2026-04-19 biltong evolution: *process fixes, not new models*.

## What skill-forge does NOT need

- Audit Army on this stack (same reasoning as biltong post-mortem — process > model)
- Dual-research (no framework/security+deployment/platform split for Q-SYS; it's one domain)
- A "Q-SYS research stream" added to the mandatory list — the existing `qsys-search` skill is the canonical source; Phase 5 would duplicate

## Non-findings (verified clean)

- `scripts/audit.sh` is stack-agnostic — no Lua-specific path needed, passed on 4 Q-SYS skills
- Rogue-agent check still applies — sub-agent scope clause is language-neutral
- Backup tarball / consent gates are stack-neutral — no changes needed

---

## Addendum (2026-04-19, added after user review)

Initial report treated the skill library as the whole developer surface. For Q-SYS that is materially wrong — hooks, MCP servers, and local knowledge bases are first-class parts of the stack. Verified active infrastructure:

- **PostToolUse hook** `~/.claude/hooks/qplug-validate.sh` → runs `qpdk validate` on every `.qplug` edit
- **UserPromptSubmit hook** `~/.claude/hooks/qsys-kb-search.sh` → injects KB context when prompt matches Q-SYS keywords (qplug, Controls., timer.new, SSH.new, dante, aes67, gpio, etc.)
- **MCP servers**: `open-brain` (agent memory with capture_thought/search_thoughts), `jcodemunch` (indexes `~/ai/qsys-plugins`), `jdocmunch` (docs index)
- **Local KBs**: `~/ai/qsys-kb`, `~/ai/qsys-ingestion`, `~/ai/knowledge-base` — Neo4j + Qdrant pipelines feeding `qsys-search` and `cisco-codec-search`
- **qpdk CLI** — the Q-SYS Plugin Development Kit under `~/ai/qsys-plugins/qpdk`

### Additional gaps from this blind spot

**G12 — Phase 1 doesn't inventory hooks.**
`~/.claude/settings.json` declares PostToolUse / UserPromptSubmit / SessionStart hooks. For Q-SYS, `qplug-validate.sh` is load-bearing — it's the audit-on-edit that complements `qsys-plugin-patterns`. Phase 1 profile doesn't read hooks; Phase 2 can't judge whether a skill is redundant with a hook or complementary; Phase 5 research agents may propose rules that duplicate what a hook already enforces.
- Proposed fix: Phase 1 adds `active_hooks: [{event, matcher, command}]` to profile.json from `settings.json`. Phase 2 audit notes "X is enforced by hook Y — consider if skill Z rule is redundant". Phase 5 research briefs include this so agents don't duplicate.

**G13 — Phase 1 doesn't inventory MCP servers.**
`~/.claude.json` `mcpServers` includes `jcodemunch` (code index), `jdocmunch` (docs), `open-brain` (memory), plus domain MCPs (n8n, notion, pencil, etc.). For Q-SYS, `jcodemunch` already indexes `~/ai/qsys-plugins` — a Phase 5 research stream that didn't know this would spend tokens doing discovery that's a single MCP call away.
- Proposed fix: Phase 1 adds `available_mcp_servers: [names]`. Research-agent brief template (`references/research-agent-brief.md`) mentions them so agents reach for the index first.

**G14 — Phase 1 doesn't inventory local knowledge bases.**
The `qsys-kb-search.sh` hook injects KB context at prompt-submit time — meaning a Q-SYS Lua question already gets KB hits before any skill fires. If skill-forge proposed a rule that's already in the KB, it's duplicating source-of-truth. Phase 1 should discover `~/ai/*knowledge*` / `~/ai/qsys-kb/` style dirs and note them in the profile.
- Proposed fix: Phase 1.5 completeness check extends to "are there local KBs that could answer this instead of a new skill rule?"

### Revisions to existing gaps

**G4 revisited.** I said Q-SYS skills have no filePattern/bashPattern and should get them. That's still true for relevance-matching purposes — but for `qsys-plugin-patterns` specifically, the validate-hook *is* the file-level trigger mechanism. The skill's job is "teach the LLM before it edits"; the hook's job is "catch what leaked through." Adding `filePattern: ["**/*.qplug"]` to the skill is still worth doing for Phase 1.3 relevance, but the recommended audit rule TR004 should also recognise *"no triggers but an active hook covers the file pattern"* as a valid configuration rather than flagging it redundantly.

**G8 revisited.** I said Phase 3 candidate search is ~useless on niche stacks. Bigger point: for Q-SYS, the gap Phase 3 is trying to fill is often better filled by a **new hook or MCP wrapper**, not a new skill. Phase 3 can only propose skills — it's blind to the "build a hook" alternative. This isn't a patch so much as a reference-doc note in `phase-3-find-candidates.md` — for niche stacks with rich custom infrastructure, Phase 3's absence of candidates may mean "consider authoring a hook/MCP" rather than "nothing to do."

### Updated priority list

| # | Gap | Patch | Effort |
|---|-----|-------|--------|
| 1 | G4/G5 (refined) | Audit rule TR004, Phase 1.3 keyword fallback, recognise hook-covered file patterns | 45 min |
| 2 | **G12** | Phase 1 reads `~/.claude/settings.json` hooks → profile.json `active_hooks` | 20 min |
| 3 | **G13** | Phase 1 reads `~/.claude.json` MCP servers → profile.json `available_mcp_servers` + research-brief template | 25 min |
| 4 | G3 | Phase 1.5 Lua language dispatch | 20 min |
| 5 | G1/G7 | Monorepo detection + optional `sub_projects` | 30 min |
| 6 | G6 | Phase 1.3 scans project-local `.claude/skills/` | 15 min |
| 7 | **G14** | Phase 1.5 KB inventory | 15 min |
| 8 | G8 (refined) | Phase 3 reference doc: "for niche stacks, absence of candidates may mean consider hook/MCP authorship" | 5 min |
| 9 | G2 | Phase 1.2 Lua/Q-SYS manifest detection | 10 min |
| 10 | G9 | Phase 3 reference doc: reputation signal inverts for niche stacks | 5 min |

### What I got wrong, explicitly

1. Framed "skill-forge is stack-neutral after Phase 2" as a non-finding — it's only stack-neutral for the skill files themselves, not for the *system of skills + hooks + MCPs + KBs* that actually serves the user.
2. Missed that for Q-SYS, the most impactful gap-filling action is often not a skill edit at all.
3. Under-counted infrastructure: report had 9 gaps, should have had 12 from the start.
