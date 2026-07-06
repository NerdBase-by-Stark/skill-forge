# Stream 1: Claude Code Skill Authoring — 2026

## Research Summary

This research verifies current (2026) best practices for Claude Code Agent Skill authoring by examining official Anthropic documentation, confirmed GitHub issues, and the public anthropic/skills repository. The goal was to identify verified practices for skill discovery, metadata fields, description patterns, filePattern semantics, progressive disclosure, and token budgeting.

**What was verified:**
- Official Anthropic skill best-practices documentation (docs.claude.com, redirects to platform.claude.com)
- Metadata fields: `name`, `description`, `filePattern`, `bashPattern`, `disable-model-invocation`, `user-invocable`, `allowed-tools`
- Progressive disclosure patterns and SKILL.md structure
- Description patterns and skill activation reliability
- Token budgets and file organization patterns
- filePattern glob semantics (gitignore-style)

**What was skipped and why:**
- Third-party tutorials from Medium without corroboration (not authoritative)
- Claimed features not present in official docs (e.g., `argument-hint` field appeared in some search results but not in official Anthropic docs)
- Pricing data (outside scope; not relevant to authoring rules)

---

## Verified Gems

### Gem 1: Description Must Include Both "What" and "When"
The description field in SKILL.md frontmatter is **critical for skill discovery** and must include:
1. What the skill does (action verbs, domain)
2. When to use it (trigger phrases, context keywords)

Official example from Anthropic docs:
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

**Why it matters:** Claude uses the description to choose from potentially 100+ installed skills. Vague descriptions like "Helps with documents" cause missed activations and false-fires.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) (accessed 2026-04-19)

---

### Gem 2: Descriptions Must Use Third Person to Prevent False-Fire
The description field is injected into the system prompt. Using first-person ("I can help...") or second-person ("You can use...") causes discovery problems.

**Correct:**
```yaml
description: Processes Excel files and generates reports
```

**Incorrect:**
```yaml
description: I can help you process Excel files
```

This is not a style preference—it directly affects skill selection reliability across multiple models.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) (accessed 2026-04-19)

---

### Gem 3: filePattern Uses gitignore Semantics (Not Typical Glob)
filePattern patterns follow **gitignore syntax**, not shell glob:
- `*.c` matches only files at the current directory level, not nested (e.g., `file.c` matches, `dir/file.c` does not)
- `**/*.c` matches anywhere in the tree (e.g., `file.c`, `dir/file.c`, `dir1/dir2/file.c` all match)
- Patterns without `/` match at any depth

**Important:** This differs from typical bash globbing and many developers' assumptions.

**Source:** [Claude Code Tool Search Explained](https://www.aifreeapi.com/en/posts/claude-code-tool-search) + [GitHub Issue #26338 - Glob tool ignores literal path prefixes](https://github.com/anthropics/claude-code/issues/26338) (verified via search, accessed 2026-04-19)

---

### Gem 4: Progressive Disclosure Has Three Levels
Official Anthropic architecture uses three progressive-disclosure levels:

| Level | When Loaded | Token Cost | Content |
|-------|-----------|-----------|---------|
| **Level 1: Metadata** | Always (at startup) | ~100 tokens per skill | name + description from YAML |
| **Level 2: Instructions** | When skill triggered | <5K tokens | SKILL.md body |
| **Level 3+: Resources** | As needed | Effectively unlimited | Bundled files, scripts (output only) |

This means: Installing many skills has negligible context cost (~100 tokens each). Only the triggered skill's SKILL.md body loads. Reference files and scripts load on-demand.

**Implication:** Keep SKILL.md body under 500 lines; split larger content into separate files linked from SKILL.md.

**Source:** [Agent Skills Overview - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) (accessed 2026-04-19)

---

### Gem 5: disable-model-invocation vs. user-invocable Are Separate Controls
Two distinct frontmatter fields control skill behavior:

- **`user-invocable: true|false`** — Controls whether the skill appears in `/` slash command menu (UI only). Does NOT prevent Claude from auto-triggering.
- **`disable-model-invocation: true`** — Prevents Claude from auto-triggering. Only user can invoke via `/` command.

Both can be true simultaneously (user can invoke, but Claude won't auto-trigger). This is unique to Claude Code and prevents accidentally exposing sensitive skills to autonomous decision-making.

**Example:**
```yaml
---
name: sensitive-operation
disable-model-invocation: true  # Claude must NOT auto-trigger
user-invocable: true             # But user can manually invoke via /
---
```

**Source:** [GitHub Issue #19141 - Clarify distinction between user-invocable and disable-model-invocation](https://github.com/anthropics/claude-code/issues/19141); [Issue #24826 - disable-model-invocation rejects](https://github.com/anthropics/claude-code/issues/24826) (accessed 2026-04-19)

---

### Gem 6: SKILL.md Body Token Budget Changed — Now 500 Lines (Not 2,500 Tokens)
Official 2026 guidance specifies: **Keep SKILL.md body under 500 lines**.

This is a **structural limit**, not a token count. Once Claude loads SKILL.md, every token competes with conversation history. The "2,500 token" budget from 2025 documentation has shifted to a clearer, more maintainable "500 lines" guideline.

The shift reflects that line count is easier to enforce and reason about than token estimates, which vary by content type.

**Implication:** If your SKILL.md approaches 500 lines, split content into referenced files (FORMS.md, REFERENCE.md, etc.) to keep token burden light once triggered.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Token budgets" (accessed 2026-04-19)

---

### Gem 7: Conciseness Assumes Claude Is "Already Very Smart"
Anthropic's core authoring principle: **"Only add context Claude doesn't already have."**

Challenge every sentence:
- "Does Claude really need this explanation?"
- "Can I assume Claude knows this?"

Example comparison from official docs:

**Bad (too verbose, ~150 tokens):**
```markdown
## Extract PDF text

PDF (Portable Document Format) files are a common file format that contains
text, images, and other content. To extract text from a PDF, you'll need to
use a library...
```

**Good (concise, ~50 tokens):**
```markdown
## Extract PDF text

Use pdfplumber for text extraction:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```
```

The concise version assumes Claude knows what PDFs are and how libraries work.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Core principles" (accessed 2026-04-19)

---

## Proposed Skill Rules

### Rule 1: Description = What + When + Trigger Phrases
**Prose:**
The description field must always include (1) what the skill does using action verbs, (2) when to use it with specific context or domain keywords, and (3) trigger phrases Claude should recognize. Write in third person (active voice, no "I" or "you"). Avoid vague descriptions like "Helps with documents" — be specific with file types, operations, and user intent patterns. Example: "Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing spreadsheets, tabular data, .xlsx files, or when the user asks for data analysis."

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Writing effective descriptions"

---

### Rule 2: Split SKILL.md at 500 Lines; Link References One Level Deep
Keep SKILL.md body under 500 lines. When approaching this limit, split detailed content into separate files (FORMS.md, REFERENCE.md, EXAMPLES.md, etc.) and link from SKILL.md using relative paths. Ensure all reference files are one level deep from SKILL.md—avoid chains like SKILL.md → advanced.md → details.md, as Claude may partially read nested references. For files >100 lines, include a table of contents at the top so Claude can see the full scope even with preview reads.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Progressive disclosure patterns" + "Avoid deeply nested references"

---

### Rule 3: filePattern Uses Gitignore Semantics — Prefix With ** for Recursive Match
filePattern patterns follow gitignore semantics, not shell glob. Patterns without `/` match at any depth, but `*.ext` matches only the top level. To match recursively, prefix with `**/`. Examples: `**/*.pdf` matches PDFs anywhere; `*.py` matches only top-level Python files. Document this assumption in SKILL.md to prevent user confusion.

**Source:** [Claude Code Tool Search Explained](https://www.aifreeapi.com/en/posts/claude-code-tool-search) + [GitHub Issue #26338](https://github.com/anthropics/claude-code/issues/26338)

---

### Rule 4: Use disable-model-invocation for High-Impact or Sensitive Workflows
When a skill performs destructive, high-impact, or sensitive operations (database migrations, bulk deletions, credential rotation), set `disable-model-invocation: true` in the frontmatter. This prevents Claude from auto-triggering the skill based on description match, requiring explicit user invocation via `/skill-name`. Optionally keep `user-invocable: true` to allow manual triggering. This is a unique safeguard in Claude Code; use it for risky operations.

**Source:** [GitHub Issue #19141](https://github.com/anthropics/claude-code/issues/19141) + Issue #24826

---

### Rule 5: Assume Claude Knows Domain Fundamentals — Don't Explain Concepts
Remove explanations of what PDFs, Excel, databases, etc., are. Instead, focus on your skill's unique workflow, gotchas, and non-obvious patterns. If your skill needs to explain a concept (e.g., "ORM relationship cardinality"), check if it's truly essential—often Claude already knows it. Every token you save in SKILL.md reduces context pressure once the skill is triggered.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Default assumption: Claude is already very smart"

---

## Anti-Patterns / Folklore to Ignore

### Anti-Pattern 1: "2,500 Token Budget for SKILL.md"
**Folklore:** Keep SKILL.md under 2,500 tokens.

**Reality (2026):** Official guidance is **500 lines**, not token count. This is a structural guideline that's easier to enforce and reason about. Token count varies by content type (code is dense, prose is sparse), so line count is a more stable metric.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

---

### Anti-Pattern 2: "Description Doesn't Matter if SKILL.md Is Good"
**Folklore:** Skill activation depends only on the instructions in SKILL.md.

**Reality:** The description is **critical for discovery**. Claude uses it to decide *whether* to trigger the skill before even reading SKILL.md. A vague description causes missed activations and false-fires. Poor descriptions may have activation rates as low as 20%; well-crafted descriptions can reach 90% reliability (tested across 200+ prompts in public research).

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Writing effective descriptions" + public skill research (2026)

---

### Anti-Pattern 3: "Testing a Skill With One Model Is Enough"
**Folklore:** If a skill works with Claude Opus, it works everywhere.

**Reality:** Skills behave differently across models. Claude Haiku may need more explicit guidance; Claude Opus may avoid over-explanation. Official guidance: **Test with all models you plan to use** (Haiku, Sonnet, Opus). A skill tuned only for Opus may fail with Haiku.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Test with all models you plan to use"

---

### Anti-Pattern 4: "Use Windows Paths in SKILL.md (Backslashes)"
**Folklore:** On Windows, use `reference\guide.md`.

**Reality:** Always use forward slashes (`reference/guide.md`). This works cross-platform; backslashes cause errors on Unix systems.

**Source:** [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) § "Anti-patterns to avoid"

---

### Anti-Pattern 5: "allowed-tools Field Is Fully Supported"
**Folklore:** Use `allowed-tools` freely to grant pre-approved tool access.

**Reality (confirmed 2026):** The `allowed-tools` field exists and is **experimental** (per GitHub Issue #26795). It accepts a space-delimited allowlist of tools, but vendor support is inconsistent across surfaces (Claude Code vs. Claude.ai vs. API). Exercise caution and test thoroughly before relying on it in production workflows.

**Source:** [GitHub Issue #26795 - allowed-tools validator reports unsupported despite valid per docs](https://github.com/anthropics/claude-code/issues/26795) (accessed 2026-04-19)

---

## Open Questions / Unverified

### Unverified 1: Exact Activation Reliability Metrics
Published research claims skill descriptions can improve activation from 20% → 90%, but these numbers come from third-party research (Medium, blog posts), not official Anthropic documentation. Official docs describe best practices but do not publish benchmark activation rates by description pattern.

### Unverified 2: New Metadata Fields Beyond Official Docs
Some third-party resources mention `argument-hint` field, but this does not appear in official Anthropic documentation (docs.claude.com, platform.claude.com). No confirmation that this field is supported in 2026.

### Unverified 3: Token Budget for Progressive Disclosure Reference Files
Official docs state that reference files are loaded "on-demand" and have "effectively unlimited" size, but do not specify exact costs. Presumably, file size scales linearly with token cost once read, but token-per-line metrics are not documented by Anthropic.

### Unverified 4: filePattern Matching Speed/Performance
Official docs describe gitignore-style semantics but do not quantify performance implications of deeply nested patterns or large pattern lists. Whether `**/*.pdf` is more expensive than `*.pdf` is not documented.

---

## Sources

1. [Skill authoring best practices - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — Official 2026 Anthropic documentation (primary source of truth). Accessed 2026-04-19.

2. [Agent Skills Overview - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) — Official architecture and progressive disclosure explanation. Accessed 2026-04-19.

3. [GitHub Issue #19141 - Clarify distinction between user-invocable and disable-model-invocation](https://github.com/anthropics/claude-code/issues/19141) — Confirmed and resolved; explains the unique dual-control paradigm in Claude Code. Accessed 2026-04-19.

4. [GitHub Issue #26795 - allowed-tools validator reports unsupported](https://github.com/anthropics/claude-code/issues/26795) — Confirms allowed-tools is experimental and has inconsistent support. Accessed 2026-04-19.

5. [Claude Code Tool Search Explained (2026)](https://www.aifreeapi.com/en/posts/claude-code-tool-search) — Community documentation of filePattern glob semantics aligned with official gitignore model. Accessed 2026-04-19.

6. [GitHub anthropic/skills Repository](https://github.com/anthropics/skills) — Official public skills repository with 17 example skills demonstrating current best practices. Accessed 2026-04-19.
