# example-research/

Seven verified-source research documents produced by parallel `search-specialist` agents during Phase 5 of a `skill-forge` run. Each was the basis for skill edits and new rules in `../example-skills/`.

## The documents

| # | Topic | Gems | Rules proposed | File |
|---|---|---|---|---|
| 1 | PyInstaller 6.x edge cases | 9 | 8 | [01-pyinstaller-edges.md](01-pyinstaller-edges.md) |
| 2 | Windows code signing (2024-2026 shifts) | 10 | 6 | [02-code-signing.md](02-code-signing.md) |
| 3 | Network device discovery protocols | 7 | 6 | [03-discovery-protocols.md](03-discovery-protocols.md) |
| 4 | PyInstaller AV false-positive mitigation | 8 | 5 | [04-av-evasion.md](04-av-evasion.md) |
| 5 | Qt 6 / PySide6 threading patterns | 10 | 6 | [05-threading.md](05-threading.md) |
| 6 | GitHub Actions CI/CD for Python desktop | 10 | 6 | [06-cicd.md](06-cicd.md) |
| 7 | Mass-deploy UX patterns from pro tools | 10 patterns | 10 | [07-ux-patterns.md](07-ux-patterns.md) |

**Total:** ~2,950 lines, ~55 verified gems, ~47 proposed rules across 7 domains.

## Why keep these?

1. **Source-of-truth citations.** When the example skills reference "Azure Trusted Signing is $120/yr", the claim lives in `02-code-signing.md` with a Microsoft Learn URL and access date. Future sessions can re-verify without re-researching.
2. **Research-brief template validation.** `skill-forge/references/research-agent-brief.md` claims an agent can produce `5-10 verified gems` — these docs are the proof.
3. **Calibration for your own runs.** What does a "good" Phase 5 doc look like? These. What does a failed one look like? You'd see zero gems or UNVERIFIED-everywhere. This lets you judge your agent output.

## What's in each doc

Every research doc follows the template in `skill-forge/references/research-agent-brief.md`:

- **Research Summary** — scope, what was verified vs skipped
- **Verified Gems** — concrete findings with source URLs + access dates
- **Proposed Skill Rules** — ready-to-paste, matching the skill-library formatting
- **Anti-Patterns / Folklore to Ignore** — what NOT to do, with citations
- **Open Questions / Unverified** — things worth revisiting
- **Sources** — numbered URL list

## Known freshness

All docs were produced April 2026. For time-sensitive domains (Windows code signing, AV vendor behavior, GitHub Actions runner images), re-verify before citing in 2027+. The research-brief template includes re-verification steps in Section 7 "If you need to re-verify" for the highest-churn sections.
