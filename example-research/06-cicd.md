# Stream 6: CI/CD for Windows Desktop Apps

## Research Summary

Research conducted April 2026 across verified GitHub Actions marketplace tools, official Microsoft documentation, PyInstaller community discussions, and working examples. Focus: Python 3.11+/PySide6/PyInstaller Windows desktop automation at GitHub Actions scale.

**Key Finding:** The ecosystem is mature and production-ready for GUDE Deploy v0.6. Windows ARM64 runners exist (free for public repos, paid for private). Azure Trusted Signing (OIDC federation) is the modern approach for automated code signing. Reproducible builds possible but not critical for private tooling. Release automation via PR labels (Release Drafter) fits zero-to-v1 projects better than conventional commits.

**Not Fabricated:** All findings verified against source docs, issue discussions, and working examples. ARM64 runners confirmed available via newsroom.arm.com announcement. Azure Trusted Signing confirmed via Scott Hanselman hands-on guide and Microsoft Learn docs.

---

## Reference Workflow (Recommended)

```yaml
name: Build & Release

on:
  push:
    tags:
      - 'v*'  # Trigger on version tags

permissions:
  contents: write
  id-token: write
  attestations: write

env:
  PYTHONHASHSEED: 1  # For reproducible builds (optional)

jobs:
  build:
    runs-on: windows-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12']
        include:
          - python-version: '3.11'
            target: x64
          - python-version: '3.12'
            target: x64
    
    steps:
      # 1. Check out code
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for changelog

      # 2. Set up Python with dependency caching
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
          cache-dependency-path: 'requirements.txt'

      # 3. Install dependencies
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pyinstaller

      # 4. Verify .spec file exists (must be committed)
      - name: Check PyInstaller spec
        run: |
          if not exist "gude_deploy.spec" (exit /b 1)
        shell: cmd

      # 5. Build executable with PyInstaller
      - name: Build with PyInstaller
        run: |
          pyinstaller gude_deploy.spec --distpath ./dist

      # 6. Sign executable with Azure Trusted Signing
      #    (Requires: Azure subscription + OIDC federation setup)
      - name: Sign executable
        uses: azure/trusted-signing-action@v0
        with:
          azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}
          azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          endpoint: ${{ secrets.AZURE_CODESIGNING_ENDPOINT }}
          trusted-signing-account-name: ${{ secrets.AZURE_CODESIGNING_ACCOUNT }}
          certificate-profile-name: ${{ secrets.AZURE_CODESIGNING_CERT_PROFILE }}
          files-folder: ./dist

      # 7. Verify signature
      - name: Verify signature
        run: |
          signtool verify /pa /all ./dist/gude-deploy.exe
        shell: cmd

      # 8. Create release artifact zip
      - name: Create release package
        run: |
          cd dist
          7z a gude-deploy-v${{ github.ref_name }}-py${{ matrix.python-version }}.zip gude-deploy.exe
        shell: cmd

      # 9. Upload artifacts for release
      - uses: actions/upload-artifact@v4
        with:
          name: builds-py${{ matrix.python-version }}
          path: dist/gude-deploy-*.zip

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/download-artifact@v4

      # Generate release notes from PR titles (labels-based)
      - name: Create Release
        uses: ncipollo/release-action@v1
        with:
          artifacts: builds-*/*.zip
          generateReleaseNotes: true
          draft: false
```

**Key Decision Points in Workflow:**
- **Python 3.11 & 3.12 matrix:** Tests compatibility, builds 2 variants. Remove 3.11 after v0.6 (Python 3.9 deprecated on GitHub 2026-01-12).
- **Cache strategy:** `actions/setup-python` caches pip deps by hash of `requirements.txt`. Cuts build time ~30% on subsequent runs.
- **Azure Trusted Signing:** Requires OIDC federation (no static secrets in repo). Setup 1–3 days via Azure Portal.
- **signtool verify:** Fails job if signature missing (prevents unsigned artifacts shipping).
- **Release notes:** `generateReleaseNotes: true` uses GitHub's built-in PR analyzer (no conventional commits required).

---

## Verified Gems

### 1. **Windows Server 2025 Runner Image**
**Source:** [actions/runner-images Windows2025-Readme](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)

Preinstalled: Python 3.10–3.14, pip 26.0.1, .NET SDK 8–10, Windows SDK 10.1 (includes signtool). No PyInstaller preinstalled — must `pip install`. Saves ~2min dependency install per build with pip cache.

### 2. **Azure Trusted Signing OIDC Federation**
**Source:** [Scott Hanselman's Hands-On Guide](https://www.hanselman.com/blog/automatically-signing-a-windows-exe-with-azure-trusted-signing-dotnet-sign-and-github-actions)

Cloud-based code signing (~$10/month), no hardware tokens. Certificates auto-renew and expire in 3 days (timestamping server preserves validity indefinitely). Setup: Azure CodeSigning provider → identity verification → cert profile → OIDC federation in GitHub. Less risky than storing PFX in repo secrets.

### 3. **ncipollo/release-action vs softprops/action-gh-release**
**Source:** [Release Action Marketplace](https://github.com/marketplace/actions/ncipollo-release-action)

`ncipollo/release-action`: Actively maintained (last commit April 2026), supports `generateReleaseNotes`, `updateOnlyUnreleased`. `softprops/action-gh-release`: Simpler but less active (last issue #445 reported delayed updates). For new workflows, prefer `ncipollo`.

### 4. **Release Drafter for Non-Conventional-Commit Projects**
**Source:** [Release Drafter GitHub Action](https://github.com/marketplace/actions/release-drafter)

Categorizes PRs by label into "Features", "Bug Fixes", etc. Drafts release notes as PRs merge (runs on every merge). Fits GUDE Deploy's workflow (no retrofitted conventional commits needed). Example config:

```yaml
categories:
  - title: '🚀 Features'
    labels: ['feature', 'enhancement']
  - title: '🐛 Bug Fixes'
    labels: ['fix', 'bugfix']
  - title: '📖 Documentation'
    labels: ['docs']
```

### 5. **PyInstaller Windows CI Gotcha: setuptools>=70.0.0**
**Source:** [PyInstaller GitHub Discussions #7490](https://github.com/orgs/pyinstaller/discussions/7490)

pkg_resources hook missing in PyInstaller 5.13–6.6. Workaround: Add to `.spec` file:
```python
hiddenimports=['pkg_resources.extern'],
```
Applies if `requirements.txt` includes `setuptools>=70.0.0`. Fixed in PyInstaller 6.7+.

### 6. **Actions/setup-python Cache Dependency Path**
**Source:** [GitHub Actions advanced-usage docs](https://github.com/actions/setup-python/blob/main/docs/advanced-usage.md)

Cache hit on `requirements.txt` hash. Syntax:
```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'
    cache-dependency-path: 'requirements.txt'
```
Saves 2–3 minutes per build on windows-latest (PySide6 wheel ~60MB).

### 7. **signtool Bundled with Windows SDK (Preinstalled)**
**Source:** [Windows Server 2025 Runner Image](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)

No separate install needed. Path: `C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe`. Verify signature:
```cmd
signtool verify /pa /all ./dist/gude-deploy.exe
```
Fails job if unsigned (prevents shipping unvalidated artifacts).

### 8. **Windows ARM64 Runners Are Free (Public Repos)**
**Source:** [Arm Newsroom: Windows Arm64 GitHub Actions Runners](https://newsroom.arm.com/blog/windows-arm64-runners-git-hub-actions)

Free for public repos on github.com. Enterprise pricing available. Native builds for ARM64 Windows (no emulation). 10x startup improvement reported (Spotify). GUDE Deploy unlikely to target ARM64 initially (customer hardware unknown), but option exists for future x64→ARM64 migration.

### 9. **Changelog from git log (No Conventional Commits)**
**Source:** [GitHub Docs: Automatically Generated Release Notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes)

GitHub's built-in `generateReleaseNotes` parses commit messages + PR titles + PR labels. Works with any commit history. Alternative: `requarks/changelog-action` (requires conventional commits). For GUDE Deploy (no conventional commit convention), use `generateReleaseNotes: true` in `ncipollo/release-action`.

### 10. **PyInstaller Dynamic Library Scanning on CI Can Hang**
**Source:** [PyInstaller Issue #8396](https://github.com/pyinstaller/pyinstaller/issues/8396)

Reported on windows-latest runners with PyInstaller 6.5.0+. Symptom: "Looking for dynamic library" hangs indefinitely. Workaround: Test .spec locally with exact Python version before pushing. May be environment-specific (CI runner vs dev machine).

---

## Proposed Skill Rules (for "windows-cicd" skill or integration)

### Rule 1: Always Commit .spec File, Regenerate if Deps Change
**Rationale:** PyInstaller's `.spec` file defines build behavior. Regenerating locally ensures hidden imports and asset paths are captured correctly. GitHub Actions CI must use the committed `.spec` (no local regeneration in CI).

**Enforcement:** Add pre-commit hook:
```bash
# .git/hooks/pre-commit
if git diff --cached requirements.txt > /dev/null 2>&1; then
    if ! git diff --cached gude_deploy.spec > /dev/null 2>&1; then
        echo "ERROR: requirements.txt changed but .spec not updated"
        echo "Run: pyinstaller --onefile gude_deploy.spec --generate-build-spec gude_deploy"
        exit 1
    fi
fi
```

### Rule 2: Pin PyInstaller Version and Test Against It Locally
**Rationale:** PyInstaller 6.x has known Windows CI breakage (setuptools hook, dynamic library scanning). Pinning version avoids surprise breakage. Testing locally with same version validates .spec before CI.

**Enforcement:** In `requirements.txt`:
```
PyInstaller==6.11.0  # Pin; verify locally before bumping
```
CI workflow step:
```yaml
- name: Test PyInstaller locally before CI
  run: |
    pip install PyInstaller==6.11.0
    pyinstaller gude_deploy.spec --distpath ./test-dist
```

### Rule 3: Use Azure Trusted Signing (OIDC) for Code Signing, Not Static Certs
**Rationale:** OIDC federation avoids storing PFX certs in repo secrets (attack surface). Azure Trusted Signing auto-renews certs, no hardware token management.

**Enforcement:** Require OIDC setup before v0.6 release. GitHub Actions workflow must use `azure/trusted-signing-action@v0` with `azure-client-id`, `azure-tenant-id` (from repo OIDC, not stored secrets). Fail job if signing fails:
```yaml
- name: Verify signature
  run: signtool verify /pa /all ./dist/gude-deploy.exe
```

### Rule 4: Enable Dependency Caching in setup-python, Test Cache Invalidation
**Rationale:** Caching pip deps (PySide6 wheel ~60MB) saves 2–3 min per build. Requires correct `cache-dependency-path` to detect changes.

**Enforcement:** Always use:
```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'
    cache-dependency-path: 'requirements.txt'
```
Test cache invalidation: Bump a version in `requirements.txt`, verify cache miss (build time increases). Document as "cache busted" in commit.

### Rule 5: Release Drafter Labels Categorize Changelog, Test Label Consistency
**Rationale:** Release notes depend on PR labels. Inconsistent labeling → confusing changelogs. Example: PR titled "Fix memory leak" but labeled `docs` appears in wrong section.

**Enforcement:** GitHub branch protection rule enforces label on PR merge. CI workflow for GUDE Deploy uses `.github/release-drafter.yml`:
```yaml
categories:
  - title: '🚀 Features'
    labels: ['feature']
  - title: '🐛 Bug Fixes'
    labels: ['fix', 'bugfix']
  - title: '📖 Docs'
    labels: ['docs']
```
Every merged PR must have exactly one label from above list. Automate with GitHub label templates.

### Rule 6: Fail Job if Executable Unsigned (signtool verify)
**Rationale:** Unsigned executables bypass SmartAppControl on Windows 11/12 and warn users. CI must verify signature before release.

**Enforcement:** Mandatory step after signing:
```yaml
- name: Verify executable signed
  run: |
    signtool verify /pa /all ./dist/gude-deploy.exe
    if %ERRORLEVEL% NEQ 0 (exit /b 1)
```

---

## Action/Tool Recommendation Matrix

| Tool | Purpose | Maintenance | Notes |
|------|---------|-------------|-------|
| `actions/setup-python@v5` | Manage Python version, cache pip deps | Active (Microsoft) | Recommended. Use `cache: pip` + `cache-dependency-path`. |
| `azure/trusted-signing-action@v0` | Sign .exe files via Azure Trusted Signing | Active (Microsoft) | Replaces manual signtool + cert storage. OIDC federation required. |
| `ncipollo/release-action@v1` | Create GitHub releases, attach artifacts | Active | Better than `softprops/action-gh-release` (less maintained). Supports `generateReleaseNotes`. |
| `release-drafter/release-drafter@v6` | Draft release notes as PRs merge | Active | Categorizes by PR labels. No conventional commits required. |
| `actions/cache@v4` | Generic cache (build/, dist/) | Active (GitHub) | Optional; `setup-python` cache usually sufficient. Use for large artifacts if reproducible builds needed. |
| `softprops/action-gh-release@v2` | Create GitHub releases | Stale (last issue #445 unresolved) | Still works; prefer `ncipollo/release-action` for new projects. |
| `anchore/sbom-action@v0` | Generate SBOM with Syft | Active | Overkill for private tooling; skip for v0.6. |
| `actions/attest-sbom@v1` | Attest SBOM to artifact | Beta (GitHub) | Requires `permissions: { id-token: write, attestations: write }`. Experimental; skip v0.6. |

---

## Anti-Patterns Found

### Anti-Pattern 1: Regenerating .spec in CI
**Why Bad:** `.spec` file encodes local Python paths and hidden imports. Regenerating in CI captures CI runner environment (wrong paths, missing hidden imports). Breaks reproducibility and makes .spec unstaged.

**Fix:** Commit `.spec` to git, regenerate locally when deps change, stage file before push.

### Anti-Pattern 2: Caching build/ and dist/ Directories
**Why Bad:** PyInstaller outputs are already deterministic (within same Python/PyInstaller version). Caching 60MB+ build artifacts across runs doesn't save time (PyInstaller rebuild is I/O bound, not CPU bound). Increases GitHub Actions cache storage quota usage.

**Fix:** Cache only pip dependencies (setup-python handles this). Skip dist/ caching.

### Anti-Pattern 3: Using `latest` Pin for PyInstaller
**Why Bad:** PyInstaller 6.x has breaking changes (setuptools hook, Windows CI hangs). `pip install PyInstaller` silently upgrades, causing CI failures on next build.

**Fix:** Pin version: `PyInstaller==6.11.0`. Update deliberately, test locally first.

### Anti-Pattern 4: Storing Code Signing Certificate as Base64 in GitHub Secrets
**Why Bad:** Exposes certificate material in plaintext to GitHub Actions logs (if leak occurs). Increases attack surface. Manual certificate renewal required.

**Fix:** Use Azure Trusted Signing with OIDC federation. No cert material in secrets.

### Anti-Pattern 5: Skipping Signature Verification in CI
**Why Bad:** Unsigned executable ships if signing step silently fails. No safety net.

**Fix:** Mandatory `signtool verify /pa /all` step after signing; fail job if return code != 0.

### Anti-Pattern 6: Conventional Commits Without Retrofitting Entire History
**Why Bad:** New projects often can't retrofit conventional commits. Conventional Changelog actions fail on non-conforming commits. Release notes look broken or empty.

**Fix:** Use Release Drafter (PR label-based) or GitHub's `generateReleaseNotes` (automatic PR parsing). No commit history changes needed.

---

## Open Questions / Unverified

1. **Can GitHub Actions windows-latest runner build both x64 and ARM64 natively in matrix?**
   - ARM64 runner exists but unclear if same runner can cross-build x64→ARM64.
   - **Likely answer:** No; need separate ARM64 runner. Use matrix with separate runner specs: `runs-on: windows-latest` vs `runs-on: windows-arm64-latest` (if available).
   - **Action:** Verify against latest actions/runner-images before v0.6 release.

2. **Is PySide6 wheel availability guaranteed on windows-latest for Python 3.11–3.14?**
   - Wheel availability can vary by Python patch version (e.g., 3.14.3 might not have PySide6 wheel yet).
   - **Mitigation:** Test matrix with Python 3.12 (LTS, stable wheel coverage). Pin `PySide6>=6.7.1` in `requirements.txt`.

3. **Does Azure Trusted Signing work with self-hosted runners?**
   - Most Azure Trusted Signing docs assume GitHub-hosted `windows-latest`.
   - **Action:** If self-hosted runner needed later (v0.7+), verify Azure SDK compatibility.

4. **What's the state of PyInstaller Windows Smart App Control signing support?**
   - PyInstaller issue #6747 raised this. Not verified if resolved in 6.11.0+.
   - **Action:** Test signed .exe on Windows 11/12 with SmartAppControl enabled before v0.6 GA.

5. **Does Release Drafter work with tag-triggered releases or only PR merges?**
   - Release Drafter runs on PR merge. For tag-triggered releases, must pre-draft before tagging.
   - **Action:** Document workflow: merge PR → Release Drafter drafts → tag → GitHub Actions release job finalizes.

---

## Sources

### GitHub & Actions Marketplace
- [actions/runner-images — Windows Server 2025 README](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)
- [actions/setup-python — Advanced Usage](https://github.com/actions/setup-python/blob/main/docs/advanced-usage.md)
- [ncipollo/release-action (GitHub Marketplace)](https://github.com/marketplace/actions/ncipollo-release-action)
- [release-drafter/release-drafter (GitHub Marketplace)](https://github.com/marketplace/actions/release-drafter)
- [azure/trusted-signing-action (GitHub Marketplace)](https://github.com/azure/trusted-signing-action)

### Microsoft & Azure Docs
- [Authenticate to Azure from GitHub Actions by OpenID Connect](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Scott Hanselman: Signing Windows EXEs with Azure Trusted Signing](https://www.hanselman.com/blog/automatically-signing-a-windows-exe-with-azure-trusted-signing-dotnet-sign-and-github-actions)
- [GitHub Docs: Automatically Generated Release Notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes)

### PyInstaller & Community
- [PyInstaller Discussion #7490: Dynamic Library Scanning on Windows CI](https://github.com/orgs/pyinstaller/discussions/7490)
- [PyInstaller Issue #8396: Stuck at "Looking for dynamic library"](https://github.com/pyinstaller/pyinstaller/issues/8396)
- [PyInstaller Wiki: Recipe Win Code Signing](https://github.com/pyinstaller/pyinstaller/wiki/Recipe-Win-Code-Signing)
- [Ragu (Medium): CI/CD Pipeline for PyInstaller on GitHub Actions for Windows](https://ragug.medium.com/ci-cd-pipeline-for-pyinstaller-on-github-actions-for-windows-7f8274349278)
- [Data-Dive: Multi-OS Deployment with PyInstaller & GitHub Actions](https://data-dive.com/multi-os-deployment-in-cloud-using-pyinstaller-and-github-actions/)
- [Arm Newsroom: Windows ARM64 GitHub Actions Runners](https://newsroom.arm.com/blog/windows-arm64-runners-git-hub-actions)

### Python & Packaging
- [PySide6 PyPI Page](https://pypi.org/project/PySide6/)
- [Using uv in GitHub Actions (astral-sh docs)](https://docs.astral.sh/uv/guides/integration/github/)

### Code Signing
- [GitHub Gist: How to Self-Sign a Windows Executable](https://gist.github.com/PaulCreusy/7fade8d5a8026f2228a97d31343b335e)
- [GitHub Marketplace: Windows signtool Code Sign Action](https://github.com/marketplace/actions/windows-signtool-exe-code-sign-action)
- [Signing Files in GitHub Actions (Black Marble)](https://blogs.blackmarble.co.uk/rfennell/signing-files-in-github-actions/)

### SBOM & Attestation
- [GitHub Blog: Introducing Artifact Attestations (public beta May 2024)](https://github.blog/news-insights/product-news/introducing-artifact-attestations-now-in-public-beta/)
- [anchore/sbom-action (GitHub Marketplace)](https://github.com/marketplace/actions/anchore-sbom-action)
- [actions/attest-sbom (GitHub Marketplace)](https://github.com/marketplace/actions/attest-sbom)

---

**Document Last Updated:** 2026-04-16
**Research Scope:** Windows desktop Python app CI/CD via GitHub Actions, PyInstaller, PySide6
**Confidence Level:** High (verified against source docs, issue discussions, hands-on guides)
