# example-skills/

Real skills produced by running `/skill-forge` on a production project — a Python/PySide6 desktop commissioning tool deployed to 120+ GUDE Power PDU devices.

**These aren't installed by `install.sh`.** They're reference material — worked examples of what Phase 6 output looks like in practice.

## The five skills

| Skill | Archetype | What's noteworthy |
|---|---|---|
| [`pyside6-desktop/`](pyside6-desktop/) | **Large skill → progressive disclosure** | 168-line main + 7 reference files covering 52 rules. Read this first to see how `skill-forge` refactors oversized monoliths. |
| [`network-device-discovery/`](network-device-discovery/) | **Deep domain knowledge** | 47 rules including a Section 9 "Vendor UDP Broadcast Protocols" produced via reverse-engineering of a vendor's closed-source binary. Kept monolithic because content is genuinely cohesive. |
| [`windows-release-pipeline/`](windows-release-pipeline/) | **CI/CD workflow skill** | Complete reference GitHub Actions YAML + 10 rules on Azure Trusted Signing, Release Drafter, artifact verification. |
| [`mass-deploy-ux/`](mass-deploy-ux/) | **UX pattern library** | 10 patterns with PySide6 implementation hints, distilled from Ansible Tower, Buildkite, Jenkins Blue Ocean, Kubernetes Lens, Microsoft Intune. |
| [`python-packaging/`](python-packaging/) | **Scope-bounded skill** | Demonstrates the anti-bloat pattern: explicit "this is PyPI only, NOT for desktop apps — see X" scope delimiter. |

## What to do with these

1. **Read them** — they're tight, opinionated, and cite their sources. Even if your project isn't Python or desktop, the structural patterns transfer.
2. **Copy structures, not content** — `pyside6-desktop`'s main-plus-references layout is reusable; the specific PySide6 rules are project-specific.
3. **Don't install them** — they're calibrated to a specific project. Running `skill-forge` on *your* project will produce skills calibrated to *yours*.

## The research that produced them

Every rule cites a source. Many of those sources come from [`../example-research/`](../example-research/) — the Phase 5 research outputs from the same session that produced these skills.
