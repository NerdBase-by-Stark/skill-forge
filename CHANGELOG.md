# Changelog

All notable changes to this project will be documented in this file. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-04-16

### Added
- Initial public release
- `/skill-forge` slash command with full 9-phase pipeline (discover → audit → find-candidates → first-pass → research → second-pass → structure → QA → memory)
- `skill-forge` skill with progressive-disclosure methodology (main SKILL.md + 10 reference files)
- `audit.sh` — static-analysis script for skill libraries (YAML validity, rule coverage, filePattern overlap, progressive-disclosure detection)
- `install.sh` — one-line installer that copies skill + command into `~/.claude/`
- Five worked example skills produced by the methodology (pyside6-desktop, network-device-discovery, windows-release-pipeline, mass-deploy-ux, python-packaging)
- Seven verified-source research documents produced by Phase 5 agents
- Documentation: README, INSTALL, CONTRIBUTING, architecture notes, AI-discoverability note

### Safety rails
- Never auto-install third-party skills (clone-to-review only)
- Parallelism cap of 3 concurrent agents (stay under Anthropic compliance thresholds)
- Phase 4 creates backup tarball before any edits
- Phase 5 (cost-bearing) requires explicit user consent
- Every added rule must cite a source URL or project-memory reference

### Known limitations
- `audit.sh` requires Python 3 + PyYAML (documented in INSTALL)
- Windows-native shell compatibility untested (WSL works)
- Phase 5 cost estimate is heuristic; actual token usage may vary
