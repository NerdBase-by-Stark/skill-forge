---
name: windows-release-pipeline
description: GitHub Actions CI/CD for Python/PyInstaller Windows desktop apps — matrix builds, Azure Trusted Signing via OIDC, Release Drafter, dependency caching, artifact attestation. Use when setting up or modifying CI/CD for a Python Windows .exe release pipeline.
filePattern:
  - ".github/workflows/*.yml"
  - ".github/workflows/*.yaml"
  - ".github/release-drafter.yml"
  - "*.spec"
bashPattern:
  - "gh workflow"
  - "gh run"
  - "signtool"
  - "AzureSignTool"
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

# Windows Release Pipeline — Python/PyInstaller Desktop Apps

Production patterns for automating `.exe` builds, signing, and GitHub releases for Python desktop apps on Windows. Scope: PyInstaller + PySide6 + GitHub Actions. Verified against 2026 runner images and action maintenance status.

Pairs with `pyside6-desktop` (PyInstaller rules, code signing fundamentals) — this skill covers the *automation* layer.

---

## 1. Reference Workflow (copy-paste starter)

Triggered by tag push (`v0.6.0`, `v1.0.0`, etc.). Builds, signs via Azure Trusted Signing, verifies, and publishes the release.

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write       # create releases
  id-token: write       # OIDC for Azure Trusted Signing
  attestations: write   # SBOM / artifact attestations (optional)

jobs:
  build:
    runs-on: windows-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12']

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0           # full history for changelog

      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
          cache-dependency-path: 'requirements.txt'

      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install "PyInstaller==6.11.0"   # pinned — see Rule 3

      - name: Verify .spec is committed
        shell: cmd
        run: if not exist "gude-deploy.spec" exit /b 1

      - name: Build
        run: pyinstaller gude-deploy.spec --distpath ./dist

      - name: Sign via Azure Trusted Signing
        uses: azure/trusted-signing-action@v0
        with:
          azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}
          azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          endpoint: ${{ secrets.AZURE_CODESIGNING_ENDPOINT }}
          trusted-signing-account-name: ${{ secrets.AZURE_CODESIGNING_ACCOUNT }}
          certificate-profile-name: ${{ secrets.AZURE_CODESIGNING_CERT_PROFILE }}
          files-folder: ./dist

      - name: Verify signed
        shell: cmd
        run: signtool verify /pa /all .\dist\GudeDeploy\GudeDeploy.exe

      - name: Package
        shell: pwsh
        run: Compress-Archive -Path dist/GudeDeploy -DestinationPath "dist/gude-deploy-${{ github.ref_name }}-py${{ matrix.python-version }}.zip"

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

      - uses: ncipollo/release-action@v1
        with:
          artifacts: 'builds-*/*.zip'
          generateReleaseNotes: true
          draft: false
```

---

## 2. Rules

### Rule 1: Commit the `.spec` file; never regenerate in CI

PyInstaller `.spec` files encode `pathex`, hiddenimports, and hooks. Regenerating in CI captures the runner's environment, not yours — wrong paths, missing hidden imports. The `.spec` is source code; treat it as such.

```yaml
# WRONG — regenerates spec in CI, ignores your local tuning
- run: pyi-makespec gude-deploy.py

# RIGHT — use committed .spec
- run: pyinstaller gude-deploy.spec
```

Add a guard step: fail the build if the spec file is missing.

### Rule 2: Enable `setup-python` dependency caching — saves ~3 min on a PySide6 build

PySide6 alone is ~60 MB. On a cold `pip install`, it's the dominant cost. `actions/setup-python@v5` caches pip downloads keyed on your `requirements.txt` hash:

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'
    cache-dependency-path: 'requirements.txt'
```

Cache hit → skip the ~3 min PySide6 download. Cache invalidates automatically on `requirements.txt` change.

**Don't** cache `build/` or `dist/` — PyInstaller's own build is I/O-bound, not CPU-bound, and caching multi-MB artifacts wastes GitHub's 10 GB cache quota for marginal gain.

### Rule 3: Pin PyInstaller version; bump deliberately

PyInstaller 6.x has had multiple Windows-specific regressions (setuptools hook missing in 6.0–6.6, "Looking for dynamic library" hang in 6.5, various PySide6 hook misses). Pin the version so CI doesn't silently upgrade overnight:

```
# requirements.txt
PyInstaller==6.11.0
```

When bumping: build locally first, test the frozen .exe, commit both the version bump and (if needed) any new hiddenimports in the .spec. **Never** pin `PyInstaller>=6.0` or leave it unpinned.

### Rule 4: Prefer Azure Trusted Signing + OIDC over PFX-in-secrets

Two reasons to avoid base64-encoded PFX files stored as GitHub Secrets:

1. **Attack surface.** Leaked logs or compromised workflow dumps the cert material.
2. **CA/Browser Forum rules (June 2023+).** Private keys must live on FIPS 140-2 Level 2+ hardware. Storing an exportable key as a file is non-compliant.

Azure Trusted Signing via OIDC federation avoids both. No secrets in repo — federated identity, cloud HSM handles the keys. Runs on stock `windows-latest`, no self-hosted runner needed.

If you're stuck with hardware tokens (YubiKey / eToken) instead, you **must** use a self-hosted runner with the token attached. GitHub-hosted runners can't see USB devices. See `pyside6-desktop` Rule 40 for the cost/complexity comparison.

### Rule 5: Always verify signature in CI — never trust the signing step's exit code alone

The signing action can exit 0 while producing an invalid signature (expired cert, bad timestamp server at sign time, wrong cert profile). Always follow signing with an explicit `signtool verify`:

```yaml
- name: Verify signed
  shell: cmd
  run: signtool verify /pa /all .\dist\GudeDeploy\GudeDeploy.exe
```

`/pa` = "Default Authentication Verification Policy" — the right flag for end-user distribution. Failing exit code aborts the job before release publication, preventing unsigned artifacts from reaching customers.

### Rule 6: Use Release Drafter with PR labels, not Conventional Commits

If your project doesn't retrofit Conventional Commits (`feat:`, `fix:`, `chore:` prefixes), most changelog actions will produce empty or broken release notes.

Release Drafter works from **PR labels** instead:

```yaml
# .github/release-drafter.yml
categories:
  - title: '🚀 Features'
    labels: ['feature', 'enhancement']
  - title: '🐛 Bug Fixes'
    labels: ['fix', 'bugfix']
  - title: '📖 Documentation'
    labels: ['docs']
template: |
  ## Changes
  $CHANGES
```

Works with any commit history. Pair with branch protection that requires a label on every PR merge. Simpler alternative: use GitHub's built-in `generateReleaseNotes: true` in `ncipollo/release-action` — it parses PR titles automatically.

### Rule 7: `ncipollo/release-action` > `softprops/action-gh-release` in 2026

`softprops/action-gh-release` still works but has accumulated unaddressed issues (#445, #451 as of April 2026). `ncipollo/release-action@v1` is actively maintained, supports `generateReleaseNotes: true`, `updateOnlyUnreleased`, and file globs:

```yaml
- uses: ncipollo/release-action@v1
  with:
    artifacts: 'builds-*/*.zip'
    generateReleaseNotes: true
    draft: false
```

Don't be the team that notices their release action died when it's time to ship.

### Rule 8: Separate `build` and `release` jobs across OS runners

Run `build` on `windows-latest` (needed for Windows builds). Run `release` on `ubuntu-latest` — it's faster to spin up and just needs to glue zip files to a GitHub release. Using one Windows job for both wastes 30-60s per release on the slower runner boot.

```yaml
build:
  runs-on: windows-latest
  # ...
release:
  needs: build          # ← sequential dependency
  runs-on: ubuntu-latest
```

### Rule 9: Known PyInstaller 6.x Windows CI traps

Two specific breakages to pre-guard against:

- **setuptools≥70 + PyInstaller 5.13–6.6:** `pkg_resources` hook missing. Add to `.spec`:
  ```python
  hiddenimports=['pkg_resources.extern']
  ```
  Fixed in PyInstaller 6.7+. ([Discussion #7490](https://github.com/orgs/pyinstaller/discussions/7490))

- **"Looking for dynamic library" hangs on windows-latest:** Intermittent on PyInstaller 6.5+. Reproduce locally with the same Python patch version before pushing to catch it pre-CI. ([Issue #8396](https://github.com/pyinstaller/pyinstaller/issues/8396))

### Rule 10: Skip SBOM / artifact attestation for v1 unless you need supply-chain compliance

`anchore/sbom-action` + `actions/attest-sbom` produce software bills of materials and cryptographic attestations. They're valuable for:
- Regulated industries (healthcare, defense, finance)
- Supply-chain audit requirements (SLSA Level 3+)
- Multi-tenant open-source distribution

For a private tool shipped to one customer, skip it until someone asks. It adds workflow complexity and SBOM noise without customer-visible benefit.

Revisit if/when an enterprise customer asks for SLSA provenance.

---

## 3. Action / Tool Recommendation Matrix (verified April 2026)

| Purpose | Tool | Status | Use |
|---|---|---|---|
| Python setup + pip cache | `actions/setup-python@v5` | Active (Microsoft) | Always |
| Sign .exe (cloud HSM) | `azure/trusted-signing-action@v0` | Active (Microsoft) | Recommended default |
| Sign .exe (hardware token) | `AzureSignTool` (self-hosted) | Active | If stuck with YubiKey/eToken |
| Sign .exe (cross-platform) | `osslsigncode` | Active | Linux/macOS CI with PKCS#11 |
| Create release | `ncipollo/release-action@v1` | Active | Recommended |
| Create release (older alt) | `softprops/action-gh-release@v2` | Stale | Skip for new workflows |
| Draft release notes | `release-drafter/release-drafter@v6` | Active | Alt to `generateReleaseNotes` |
| Generate SBOM | `anchore/sbom-action@v0` | Active | Only for compliance needs |
| Attest artifact | `actions/attest-build-provenance@v1` | Beta (GitHub) | Only for compliance needs |
| Windows ARM64 runner | `runs-on: windows-11-arm` (public repos) | GA April 2025 | If shipping ARM64 .exe |

---

## 4. Common anti-patterns

1. **Regenerating `.spec` in CI** — captures runner env, breaks reproducibility
2. **Caching `dist/`** — wastes GitHub cache quota, doesn't speed up rebuilds
3. **Unpinned PyInstaller** — silent breakage on every new release
4. **PFX base64 in GitHub Secrets** — attack surface + CA/B Forum non-compliance
5. **Skipping signature verification** — unsigned builds ship when signing silently fails
6. **Trying to build Windows ARM64 on `windows-latest`** — cross-compile doesn't work; use `windows-11-arm` runner
7. **Running release job on `windows-latest`** — 30-60s slower than `ubuntu-latest` for what's just a GitHub API call

---

## 5. Secrets layout (recommended)

Keep these in repo → Settings → Secrets and variables → Actions:

| Secret | Purpose | How to obtain |
|---|---|---|
| `AZURE_TENANT_ID` | OIDC federation target | Azure portal → Entra ID |
| `AZURE_CLIENT_ID` | Federated app identity | Azure portal → App registrations |
| `AZURE_CLIENT_SECRET` | (or rely on OIDC, not static) | Only if not using OIDC |
| `AZURE_CODESIGNING_ENDPOINT` | Signing endpoint URL | Trusted Signing resource page |
| `AZURE_CODESIGNING_ACCOUNT` | Signing account name | Trusted Signing resource page |
| `AZURE_CODESIGNING_CERT_PROFILE` | Certificate profile | Trusted Signing → Profiles |

OIDC federation replaces `AZURE_CLIENT_SECRET` entirely — safer. Set up via [Microsoft Learn: OIDC for GitHub Actions](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect).

---

## 6. Open questions (verify before adopting)

- **Windows ARM64 cross-compile on `windows-latest`:** Not currently supported; need a separate `windows-11-arm` runner job. Verify if PySide6 ARM64 wheels exist for your Python version before enabling.
- **Smart App Control compatibility:** Windows 11 Smart App Control may reject even signed PyInstaller builds depending on reputation. Test post-signing on a fresh Win 11 image before customer rollout.
- **Release Drafter tag-triggered vs PR-triggered:** Release Drafter drafts on every PR merge by default. For tag-triggered releases, ensure the drafter job runs separately and the release job finalizes the draft.

---

## Sources

- [Microsoft Learn: Azure Trusted Signing Quickstart](https://learn.microsoft.com/en-us/azure/trusted-signing/quickstart)
- [Microsoft Learn: OIDC for Azure from GitHub Actions](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Scott Hanselman: Signing Windows EXEs with Azure Trusted Signing + GitHub Actions](https://www.hanselman.com/blog/automatically-signing-a-windows-exe-with-azure-trusted-signing-dotnet-sign-and-github-actions)
- [Windows Server 2025 runner image](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)
- [PyInstaller #7490 — setuptools≥70 hook missing](https://github.com/orgs/pyinstaller/discussions/7490)
- [PyInstaller #8396 — "Looking for dynamic library" hang](https://github.com/pyinstaller/pyinstaller/issues/8396)
- [Release Drafter docs](https://github.com/release-drafter/release-drafter)
- [ncipollo/release-action](https://github.com/ncipollo/release-action)
