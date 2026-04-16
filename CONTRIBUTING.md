# Contributing to skill-forge

Thanks for thinking about contributing. Here's how to propose changes, what I'm looking for, and what I'll push back on.

## What I'd like to see

- **Bug reports** — especially edge cases in `audit.sh` (YAML weirdness, unusual filePatterns, skills without rule numbering)
- **Port notes** — if you've got `skill-forge` working on another agent harness (Cursor, Windsurf, custom), write up the diff
- **New phase references** — e.g. a `phase-10-security.md` that runs a security-audit pass on every skill
- **Better candidate-detection heuristics** for Phase 3 — right now queries are stack-keyword-based; there's room to do better
- **Worked example skills** from project types the current examples don't cover (Rust, Go, iOS/Swift, Unreal, game dev, etc.)
- **Research-brief templates** for narrow domains — a good iOS-research brief looks different from a good Windows-CI research brief

## What I'll probably decline (for now)

- **Non-Claude-Code slash-command wrappers** — ports are welcome, but as sibling repos until the core interface stabilises. Link from the README.
- **Auto-install of third-party skills** — that's a deliberate safety rule, not an oversight. PRs adding auto-install won't land.
- **Fully autonomous end-to-end runs** — the checkpoint-per-phase model is load-bearing. Removing checkpoints without a solid argument won't land either.

## Conventions

### Skills

Follow the conventions documented in `skill-forge/SKILL.md` itself:

- Progressive disclosure for any skill > 2k tokens
- Description ≤ 300 characters
- Every rule cites a source URL or an explicit project-memory reference
- filePattern narrow enough it doesn't trigger on unrelated files

### Commits

Conventional Commits style preferred but not required:

```
feat(phase-5): consent prompt now shows cost estimate per stream
fix(audit): handle skills with no rule numbering
docs(readme): add FAQ entry on Phase 5 costs
```

Scope is one of: `phase-N`, `audit`, `install`, `readme`, `docs`, `command`, `skill`.

### PR checklist

- [ ] Ran `bash skill-forge/scripts/audit.sh skill-forge/` and got 0 errors
- [ ] Updated `CHANGELOG.md` under `## [Unreleased]`
- [ ] Touched at most one phase reference file per PR (easier review)
- [ ] If you added a new workflow pattern, updated or added example coverage in `example-skills/`

## Running the audit locally

```bash
cd skill-forge
bash skill-forge/scripts/audit.sh skill-forge/
```

Should print all green checks. If it doesn't after your changes, that's a real issue — please fix before PR.

## Local development loop

```bash
# 1. Fork + clone
git clone https://github.com/YOUR-NAME/skill-forge.git
cd skill-forge

# 2. Install into your own ~/.claude to test
./install.sh

# 3. Make changes in the repo
# 4. Re-run install.sh to sync
# 5. Test in Claude Code: /skill-forge --phase=audit
```

## Licensing

By contributing, you agree your work is MIT-licensed and compatible with the rest of the repo.

## Questions

Open an issue or discussion. Prefer issues for bugs/features, discussions for design questions.
