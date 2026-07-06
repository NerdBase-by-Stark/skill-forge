# AskUserQuestion UX Patterns & Consent-Gate Design for skill-forge

**Research Date:** 2026-04-19  
**Scope:** Verified UX patterns for Claude Code `AskUserQuestion` tool in Phase 3→6 consent gates.

---

## Research Summary

The `AskUserQuestion` tool is Claude Code's structured mechanism for presenting multiple-choice questions to users. It powers approval dialogs and specification interviews. However, **adoption without understanding the schema, failure modes, and UX constraints leads to silent approval-skips, subagent deadlocks, and UI truncation**. This document synthesizes official Anthropic docs, GitHub issues, and real-world skill patterns to establish verified rules for skill-forge.

---

## Verified Gems

### 1. Official Schema & Limits (Verified: code.claude.com/docs)

From [Handle approvals and user input - Claude Code Docs](https://code.claude.com/docs/en/agent-sdk/user-input):

- **Questions per call:** 1–4 questions
- **Options per question:** 2–4 choices
- **Header field:** Short label, max **12 characters** ✓
- **Option label:** Concise text, **1–5 words** ✓
- **Option description:** 1–2 sentences (shorter is safer for UI rendering)
- **multiSelect:** Boolean flag; enables comma-separated multi-choice

**Why this matters:** Exceeding these limits causes Claude to silently fall back to text input, breaking the intended dialog UX.

---

### 2. Preview Field (TypeScript Only, HTML/Markdown)

From [code.claude.com user-input docs](https://code.claude.com/docs/en/agent-sdk/user-input) — "Option previews (TypeScript)":

- **Requires:** `toolConfig.askUserQuestion.previewFormat: "html"` or `"markdown"`
- **Format:**
  - `"html"` → styled `<div>` fragments (no `<script>`, `<style>`, `<!DOCTYPE>`)
  - `"markdown"` → ASCII art and fenced code blocks
- **Behavior:** Claude includes `preview` on options where visual comparison helps (layouts, colors); omits it for text-only choices
- **Verification:** Check for `undefined` before rendering

**Why this matters:** Preview enables side-by-side design comparisons for Phase 5 verification checkpoints. SDK rejects hostile markup.

---

### 3. Critical Failure Mode: Silent Empty Answers in Plugin Skills

**GitHub Issue:** [#29547 - AskUserQuestion silently returns empty answers when called inside plugin skills](https://github.com/anthropics/claude-code/issues/29547)

**Root Cause:** Permission evaluator early-returns for allowed tools before the `requiresUserInteraction()` guard is checked.

**Symptom:** User never sees the dialog. Tool returns empty `answers` object. Claude hallucinates user selections and proceeds. **Approval is bypassed silently.**

**Suggested Fix:** Add `requiresUserInteraction()` check to `alwaysAllowRules` early return.

**Impact on skill-forge:** If Phase 3 approval is wrapped in a Skill tool, users may not see the consent dialog at all. Must test consent gates outside skill context in Phase 3 validation.

---

### 4. Subagent Escalation Pattern (Not Direct Support)

**GitHub Issue:** [#18721 - Missing warning and workflow guidance for AskUserQuestion limitation in Subagents](https://github.com/anthropics/claude-code/issues/18721)

**Limitation:** `AskUserQuestion` is not available in subagents (Task tool).

**Recommended Escalation Pattern:**
1. Subagent encounters decision requiring human input
2. Subagent returns structured result with options/clarification needed
3. Main agent receives result
4. Main agent uses `AskUserQuestion` to get user input
5. Main agent spawns new subagent task with clarified parameters

**Impact on skill-forge:** Phase 4→5 cost gate (spawns research agents) must **not delegate approval to subagents**. Approval questions must run in main agent context.

---

### 5. UI Truncation: Long Descriptions Get Cut Off

**GitHub Issues:**
- [#29125 - AskUserQuestion dialog truncates long option descriptions in terminal TUI](https://github.com/anthropics/claude-code/issues/29125)
- [#39867 - AskUserQuestion options with long descriptions get visually cut off](https://github.com/anthropics/claude-code/issues/39867)

**Problem:** Option descriptions exceeding ~1–2 sentences are clipped without scroll support in terminal UI.

**Workaround:** Present detailed comparison/context as markdown text **before** the AskUserQuestion call. Keep option descriptions to single sentences.

---

### 6. Don't Use AskUserQuestion for Binary Yes/No

From [code.claude.com best-practices](https://code.claude.com/docs/en/best-practices) — interview-driven pattern:

- For "plan ready?" / "should I proceed?" prompts, use **ExitPlanMode** tool instead
- AskUserQuestion is designed for multi-choice trade-offs (3+ options), not binary approval
- Text-prompt "y/n" checkpoints get missed; dialogs are mandatory (confirmed in skill-forge context)

---

### 7. Timeout Behavior: 60-Second Unattended Approval

From [issue #29889](https://github.com/anthropics/claude-code/issues/29889) and field testing:

- **Timeout:** 60 seconds (if user doesn't interact)
- **Outcome:** Tool returns successfully with empty answers; Claude proceeds, hallucinating user intent
- **Critical for Phase 3 gate:** If unattended, user misses approval entirely

---

## Proposed Skill Rules for skill-forge

### Rule 1: Schema Validation
Every AskUserQuestion call in skill-forge must validate:
- [ ] Questions: 1–4 count
- [ ] Options: 2–4 per question
- [ ] Header: ≤12 chars
- [ ] Label: ≤5 words (1–5 ideally concise action words)
- [ ] Description: ≤100 chars (typically 1–2 sentences)

**Enforcement:** Add pre-hook validation in Phase 3 approval skill that rejects oversized inputs and logs violations.

---

### Rule 2: Context Before Dialog
Present visual/detailed information as **markdown before** the AskUserQuestion call, not inside option descriptions.

**Pattern:**
```
[Phase 3 context: show diff, show costs, show scope summary]

Now asking for approval:
- AskUserQuestion with 3-4 short options
- Each label: action verb + object (e.g., "Approve all", "Review each")
- Each description: 1 sentence max
```

---

### Rule 3: No Binary Prompts with AskUserQuestion
For simple yes/no gates, use **ExitPlanMode** (if in plan mode) or gate the entire workflow differently. Reserve AskUserQuestion for 3+ distinct paths.

---

### Rule 4: Never Use in Subagents
Phase 4→5 research spawning (Phase 4 → async agents) must **not delegate approval logic to subagents**. All consent gates run in main agent context. If a subagent needs human input, it must escalate.

---

### Rule 5: Test Consent Gates Outside Skill Context
Phase 3 validation: test all consent gates **directly in normal mode** (not wrapped in Skill tool) to confirm dialogs appear. Document test evidence in Phase 3 audit log.

---

### Rule 6: Use Preview for Visual Comparisons (Phase 5 Only)
Phase 5 rogue-agent check: if showing side-by-side visual comparisons (before/after code, design layout options), enable `previewFormat: "html"` in toolConfig and include HTML strings in option `preview` fields.

---

## Anti-Patterns & Folklore

### ❌ "Just Ask Yes/No"
**Anti-pattern:** Use AskUserQuestion for binary approval ("Is my plan ready?")  
**Why it fails:** Schema overkill; ExitPlanMode exists for plan approval. User skips text prompts by default.  
**Correct approach:** ExitPlanMode for plan approval; AskUserQuestion only for 3+ trade-offs.

### ❌ "Pack Everything in Description"
**Anti-pattern:** Put comparison tables, code diffs, or detailed explanations inside option descriptions.  
**Why it fails:** UI truncates, no scroll; user can't see full context.  
**Correct approach:** Markdown before AskUserQuestion; descriptions are 1-sentence summaries only.

### ❌ "Skill-Wrapped Approval"
**Anti-pattern:** Wrap Phase 3 AskUserQuestion inside a Skill tool.  
**Why it fails:** Permission evaluator bug #29547 bypasses `requiresUserInteraction()` check; user never sees dialog.  
**Correct approach:** Run Phase 3 approval directly in main agent loop, outside Skill context.

### ❌ "Delegate Approval to Subagent"
**Anti-pattern:** Spawn a Phase 4→5 cost-approval subagent.  
**Why it fails:** Subagents don't support AskUserQuestion; main agent can't wait for user input.  
**Correct approach:** Escalation pattern: subagent returns decision data; main agent asks user.

### ❌ "Too Many Options"
**Anti-pattern:** 5+ options (e.g., "Pick a database: PostgreSQL, MySQL, MongoDB, SQLite, Cassandra, ElasticSearch, DynamoDB").  
**Why it fails:** Max 4 options hard limit; schema rejects overflow.  
**Correct approach:** Limit to 3–4 primary paths; use follow-up questions for sub-decisions.

---

## Open Questions & Research Gaps

1. **Timeout behavior documentation:** The 60-second timeout is confirmed via issues, but official SLA/configurable?  
   → Status: `UNVERIFIED` — Issue #29889 describes symptom but no published config option found.

2. **Plan approval vs. AskUserQuestion distinction:** ExitPlanMode docs don't explicitly forbid AskUserQuestion in plan mode; can they coexist?  
   → Status: `UNVERIFIED` — Inferred from system prompt; needs confirmation.

3. **Preview format limits:** Max characters for HTML preview? Limits on nested elements?  
   → Status: `UNVERIFIED` — Docs mention SDK rejects `<script>`, `<style>`, `<!DOCTYPE>` but no size limits documented.

4. **MultiSelect join separator:** Must join labels with `", "` (comma-space)? Or flexible?  
   → Status: `VERIFIED` — Confirmed in [code.claude.com example](https://code.claude.com/docs/en/agent-sdk/user-input).

5. **Other/custom-text support:** Does AskUserQuestion always offer "Other" for free text?  
   → Status: `VERIFIED` — Yes, always auto-injected per docs.

---

## Sources

| Source | URL | Access Date | Notes |
|--------|-----|-------------|-------|
| **Official Schema** | https://code.claude.com/docs/en/agent-sdk/user-input | 2026-04-19 | Complete question format, options, multiSelect, preview. |
| **Best Practices** | https://code.claude.com/docs/en/best-practices | 2026-04-19 | Interview pattern, AskUserQuestion use in plan mode. |
| **Issue #29547** | https://github.com/anthropics/claude-code/issues/29547 | 2026-04-19 | Silent empty-answers in plugin skills; root cause & fix. |
| **Issue #18721** | https://github.com/anthropics/claude-code/issues/18721 | 2026-04-19 | Subagent escalation pattern; documented limitation. |
| **Issue #29125** | https://github.com/anthropics/claude-code/issues/29125 | 2026-04-19 | UI truncation; terminal TUI clipping. |
| **Issue #39867** | https://github.com/anthropics/claude-code/issues/39867 | 2026-04-19 | UI truncation; no scroll support. |
| **Issue #12420** | https://github.com/anthropics/claude-code/issues/12420 | 2026-04-19 | 4-option hard limit. |
| **Issue #29889** | https://github.com/anthropics/claude-code/issues/29889 | 2026-04-19 | 60-second timeout; empty answers hallucination. |
| **Missing Docs** | https://github.com/anthropics/claude-code/issues/10346 | 2026-04-19 | Public docs gap; schema partly undiscovered until v2+. |
| **System Prompts** | https://github.com/Piebald-AI/claude-code-system-prompts | 2026-04-19 | Reverse-engineered system prompt; AskUserQuestion tool description. |

---

## Escalations — Supervisor Decides

None at this time. All findings are advisory rule proposals, not code changes or git operations required.
