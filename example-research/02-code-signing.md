# Stream 2: Windows Code Signing Deep-Dive

## Research Summary

This document consolidates 2024-2026 verified research on code signing practices for desktop applications. Key finding: the landscape has shifted dramatically. EV certificates no longer provide instant SmartScreen immunity (as of August 2024), CA/Browser Forum rules now mandate hardware-only private keys (June 2023), and certificate validity dropped from 39 months to 460 days (February 2026). Azure Artifact Signing (formerly Trusted Signing) offers a modern cloud alternative at $10/month with no hardware tokens. For a proprietary commercial tool like GUDE Deploy, the optimal path depends on whether you prioritize SmartScreen reputation speed vs. cost and operational simplicity.

**Research methodology**: Web search for 2024-2026 publications, Microsoft Learn docs, CA/Browser Forum requirements, vendor docs (DigiCert, Sectigo, SSL.com, Certum), GitHub projects (osslsigncode), and technical blog posts. All major claims cross-verified against multiple authoritative sources.

---

## Verified Gems

### Gem 1: Azure Artifact Signing Pricing & Identity Validation (2025)
**Source**: [Microsoft Learn - Azure Artifact Signing Quickstart](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart) (updated 2026-04-10)

Azure Artifact Signing (rebrand of Trusted Signing) offers two pricing tiers:
- **Basic**: $9.99/month, 5,000 signatures/month included
- **Premium**: $99.99/month, 100,000 signatures/month included
- **Public Trust eligibility**: USA, Canada, EU, UK (organizations); USA, Canada (individual developers)
- **Certificate validity**: 3 days only. Signatures remain valid indefinitely if timestamped during the 3-day window.

Identity validation can be completed via portal (1-20 business days). No hardware tokens required—keys live on Microsoft's FIPS 140-2 Level 3 HSM.

**Impact for GUDE Deploy**: At ~2-3 signatures per release, Basic tier costs ~$120/year and eliminates hardware token procurement/maintenance entirely.

---

### Gem 2: SmartScreen Reputation Mechanics Changed August 2024
**Source**: [Microsoft Q&A - SmartScreen Reputation with OV Certificates](https://learn.microsoft.com/en-us/answers/questions/417016/reputation-with-ov-certificates-and-are-ev-certifi)

Critical policy shift:
- **August 2024**: All EV Code Signing OIDs removed from Microsoft Trusted Root Program. EV certificates no longer grant instant reputation.
- **March 2024**: EV certificates stopped instantly bypassing SmartScreen warnings.
- **Current (2025)**: Both EV and OV certificates must build reputation organically via downloads. "Approximately 90% of all application downloads have established reputation by hash or digital certificate" (Microsoft, 2011 baseline—no current percentage published).

**What actually builds SmartScreen reputation**:
- Download volume from diverse IPs (Microsoft doesn't publish thresholds)
- Time accumulation (weeks to months typical)
- Absence of malware flags
- Certificate-based tracking (signed apps inherit issuer reputation)

EV certs provide slightly faster accumulation due to vetting history, but no bypass. OV certs now equivalent for SmartScreen purposes.

**Impact for GUDE Deploy**: Don't expect instant SmartScreen clearance from any cert type. Plan for 2-4 week ramp-up with internal testing + staged rollout to customer site (120 devices = high download volume for small tool).

---

### Gem 3: CA/Browser Forum June 2023 Rule: Private Keys on Hardware Only
**Source**: [Entrust Blog - CA/B Forum Code Signing Requirements](https://www.entrust.com/blog/2022/09/ca-browser-forum-updates-requirements-for-code-signing-certificate-private-keys)

Effective **June 1, 2023**, all code signing certificates (EV and OV) must have private keys generated and stored on hardware meeting FIPS 140-2 Level 2 or Common Criteria EAL 4+. No exportable keys allowed.

**Compliant hardware options**:
- YubiKey 5 FIPS (firmware v5.4.3+ with RSA4096 or v5.7+ with ECCP384)
- SafeNet eToken 5110 CC
- Thales Luna HSM
- DigiCert-supplied hardware tokens
- Azure Artifact Signing HSM (Microsoft-managed)

**Implementation impact**: 
- Traditional "cert-in-PEM-file" workflows are now non-compliant
- All new cert issuance requires hardware escrow
- GitHub Actions: requires self-hosted runner with physical token attached (cloud runners can't access HSM)

**Impact for GUDE Deploy**: If using traditional OV/EV certs, build CI/CD around self-hosted Windows runner with YubiKey attached, OR switch to Azure Artifact Signing (cloud HSM, no self-hosted runner needed).

---

### Gem 4: YubiKey 5 FIPS as Code Signing Hardware (2024 validated)
**Source**: [TheSSLStore - Sectigo YubiKey 5 FIPS Installation](https://www.thesslstore.com/knowledgebase/code-signing-hardware/sectigo-yubikey-5-fips-hsm-certificate-installation/)

YubiKey 5 FIPS is officially supported by Sectigo, DigiCert, and SSL.com for code signing. Setup:
- Certificate generated on YubiKey via CSR (never exported from device)
- SafeNet Authentication Client required for Windows signing
- Works with signtool.exe, AzureSignTool, osslsigncode
- Cost: ~$90-120 per key

**2026 caveat**: As of February 2026, DigiCert stopped issuing multi-year certs (max 1 year now). Sectigo/Comodo still offer multi-year with "Install on Existing HSM" option.

**Impact for GUDE Deploy**: YubiKey + Sectigo EV cert = $279-400/year for hardware + cert, plus SafeNet Authentication Client setup complexity. Azure Artifact Signing at $10/month avoids this entirely.

---

### Gem 5: osslsigncode for Cross-Platform Signing (Linux/macOS → Windows PE)
**Source**: [GitHub - mtrojnar/osslsigncode](https://github.com/mtrojnar/osslsigncode), [DigiCert Tutorial](https://knowledge.digicert.com/tutorials/sign-a-windows-app-on-linux-using-osslsigncode)

osslsigncode is a fully functional cross-platform alternative to signtool.exe. Supports PE (EXE/DLL/SYS), MSI, CAB, APPX, and PowerShell scripts.

**Requirements**:
- Certificate in SPC or PEM format
- Private key in DER, PEM, or PVK format
- OpenSSL library
- PKCS#11 support for hardware tokens (via libengine-pkcs11-openssl)

**2024 practical workflow**:
```bash
osslsigncode sign -pkcs11engine libpkcs11 -pkcs11module /path/to/libeToken.so \
  -spc cert.spc -key "keyid" -t http://timestamp.server.com/rfc3161 \
  -h sha256 -in app.exe -out app.signed.exe
```

**Impact for GUDE Deploy**: If moving build system off Windows, osslsigncode on Linux enables SHA-256 signing without migrating to cloud solutions. Requires PKCS#11 driver for YubiKey or eToken.

---

### Gem 6: RFC 3161 Timestamps Keep Signatures Valid Forever
**Source**: [Microsoft Learn - Time Stamping Authenticode Signatures](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)

**Critical for 2026 compliance**: Code signing certificates now max 460 days (down from 39 months). Timestamps are not optional—they're the only mechanism that keeps signatures valid after cert expiration.

**How it works**:
- Timestamp counter-signature (RFC 3161) embeds TSA's cert at signature time
- Verifier checks signature validity against timestamp cert expiration, not code-signing cert
- Even if code-signing cert expires, signature remains valid if timestamp cert is still valid
- Timestamp certs have longer validity (typically 5-10 years)

**Practical requirement**:
```powershell
signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 app.exe
```
The `/tr` and `/td` flags are mandatory—without them, signature validity matches cert validity.

**Impact for GUDE Deploy**: Every build must include `/tr` + `/td` flags. Test timestamp server uptime as part of CI/CD health checks. If timestamp server is unreachable at sign time, signing fails (no fallback).

---

### Gem 7: Code Signing Certificate Costs 2026 (Verified Pricing)
**Source**: [SSL.com Code Signing](https://www.ssl.com/faqs/which-code-signing-certificate-do-i-need-ev-ov/), [Sectigo EV Pricing](https://www.sectigo.com/ssl-certificates-tls/code-signing), [DigiCert Code Signing](https://www.digicert.com/signing/code-signing-certificates)

| Provider | OV | EV | Notes |
|----------|----|----|-------|
| **SSL.com** | $65-150/yr | $249-350/yr | Lowest cost, good for Indies |
| **Sectigo** | $150-200/yr | $279/yr | Strong CA, good ESO support |
| **DigiCert** | $300-400/yr | $560/yr | Premium, excellent support |
| **Certum** | €108-150/yr | ~€250/yr | EU-based, WebTrust certified |

**2026 regulatory change**: All certs max 459 days validity. Multi-year purchases now include free reissues (Certum, Sectigo).

**Cost breakdown for GUDE Deploy (1 year)**:
- OV cert + YubiKey: ~$200-300 (cert) + $100 (key) = $300-400
- EV cert + YubiKey: ~$300-500 (cert) + $100 (key) = $400-600
- Azure Artifact Signing: $120/year (no hardware)

---

### Gem 8: Self-Hosted GitHub Actions Runner Required for EV with Hardware Token
**Source**: [Melatonin Blog - EV Cert on GitHub Actions](https://melatonin.dev/blog/how-to-code-sign-windows-installers-with-an-ev-cert-on-github-actions/), [ForeLens Blog - AzureSignTool with Managed Identity](https://forelens.com/blog/github-actions-code-signing-with-azure-key-vault-hsm-rbac-oidc-and-managed-identity/)

GitHub Actions cloud runners **cannot** access USB hardware tokens (YubiKey, eToken). Workaround: self-hosted Windows runner with token attached.

**AzureSignTool example** (self-hosted runner):
```powershell
# GitHub Actions workflow on self-hosted runner
- name: Sign with AzureSignTool
  run: |
    AzureSignTool sign \
      -kvuri https://myvault.vault.azure.net \
      -kvcert MyCodeSigningCert \
      -kvi ${{ secrets.AZURE_CLIENT_ID }} \
      -kvt ${{ secrets.AZURE_TENANT_ID }} \
      -kvs ${{ secrets.AZURE_CLIENT_SECRET }} \
      -tr http://timestamp.digicert.com \
      -td sha256 app.exe
```

**Azure Artifact Signing alternative**: Works with cloud runners via Federated Identity + Azure SDK.

**Implementation cost**:
- Self-hosted runner: Windows VM + network (EC2/Azure/on-prem)
- Token passthrough: USB over IP or physical colocation
- Operational overhead: runner maintenance, security patching, token backup/rotation

**Impact for GUDE Deploy**: Switching from cloud CI/CD to self-hosted is a major operational shift. Azure Artifact Signing avoids this entirely.

---

### Gem 9: SignPath.io Free Code Signing (OSS Only, Proprietary Tool Ineligible)
**Source**: [SignPath Foundation](https://signpath.org/), [SignPath OSS Solutions](https://signpath.io/solutions/open-source-community)

SignPath Foundation provides **free** code signing for qualifying open-source projects. Hardware keys stored on SignPath-managed HSMs, no cert costs.

**OSS eligibility criteria**:
- Project must be publicly available under OSS license (GPL, MIT, Apache, etc.)
- Source code hosted on public repo (GitHub, GitLab, etc.)
- SignPath verifies binary matches source repo
- SignPath vouches for publisher identity

**Proprietary tools**: GUDE Deploy does not qualify. SignPath's commercial tier pricing not published (contact for quote).

**Impact for GUDE Deploy**: Ineligible. Keep on traditional cert path or Azure Artifact Signing.

---

### Gem 10: SHA-256 Only Now Standard; SHA-1 Dual Signing Obsolete
**Source**: [K Software - SHA1/SHA-256/Dual Signing Truth](https://support.ksoftware.net/support/solutions/articles/215805-the-truth-about-sha1-sha-256-dual-signing-and-code-signing-certificates/), [Microsoft SHA-2 Support](https://support.microsoft.com/en-us/topic/2019-sha-2-code-signing-support-requirement-for-windows-and-wsus-64d1c82d-31ee-c273-3930-69a4cde8e64f)

**Current status**:
- Windows 7 SP1: Required KB3033929 (SHA-2 support, released 2015) to validate SHA-256 sigs
- Windows 7 EOL: January 10, 2023 (no longer patched)
- GlobalSign: Ceased issuing SHA-1 certs in early 2021
- **Recommendation**: SHA-256 only. Dual signing obsolete unless supporting Windows XP SP3 or Vista (extremely rare enterprise).

**Timestamp servers**: SHA-1 timestamping deprecated (May 30, 2020). Must use SHA-256 (`/td sha256` in signtool).

**Impact for GUDE Deploy**: Use SHA-256 exclusively. No dual signing needed. Timespan simplification: fewer build matrix variations.

---

## Proposed Skill Rules

### Rule 1: Always Timestamp Code Signatures
**When**: Every production build signing
**Why**: Certificate validity now 460 days max (Feb 2026). Without timestamps, signatures expire with certs.
**Action**:
```powershell
signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 GUDE_Deploy.exe
```
**Verification**: Inspect signature: `signtool verify /pa /pb GUDE_Deploy.exe` confirms timestamp presence.

---

### Rule 2: Plan for SmartScreen Reputation Ramp-Up (2-4 weeks)
**When**: First release to end-user site
**Why**: SmartScreen warnings unavoidable initially; no cert type provides instant bypass (as of Aug 2024).
**Action**:
- Release with OV cert first (lower cost, same SmartScreen outcome as EV)
- Plan internal test phase + staged rollout to 120 devices over 2-4 weeks
- Collect execution telemetry; monitor SmartScreen flag rate
- No submission fee to Microsoft (reputation accumulates organically)
**Backup**: Certify tool with Windows logo if critical path; costs ~$5-10K (not typically justified for internal tools)

---

### Rule 3: Use Azure Artifact Signing for Simplicity; YubiKey + OV for Cost Control
**When**: Choosing signing method for 0.6+ releases
**Decision matrix**:
| Factor | Azure Artifact | OV + YubiKey |
|--------|---|---|
| **Setup time** | 1-2 hours | 4-6 hours + Hardware wait |
| **Annual cost** | $120 | $300-400 |
| **CI/CD complexity** | Cloud runner (simple) | Self-hosted runner (complex) |
| **Hardware maintenance** | None | YubiKey rotation, backup |
| **SmartScreen outcome** | Identical | Identical |
| **Best for** | Solo dev, rapid release | Teams needing EV compliance |

**Recommendation for GUDE Deploy**: Use Azure Artifact Signing ($120/year, 5000 sig/month Basic). Avoids hardware procurement, simplifies CI/CD, matches OV reputation timeline.

---

### Rule 4: Certificate Profile Naming & Rotation (2026 Compliance)
**When**: Every cert renewal (max 460 days validity)
**Action**:
- Name profile: `gude-deploy-2026-h1` (year-half semantic versioning)
- Generate new cert 30 days before expiration
- For Azure Artifact Signing: Simply create new certificate profile (no key reissue cost)
- For YubiKey: Order replacement token in parallel; test fallback token before cutover
**Testing**: Sign a test EXE with new cert 7 days before deployment to catch HSM/password issues

---

### Rule 5: osslsigncode for Linux/macOS Build Systems
**When**: Build matrix includes non-Windows CI/CD environments
**Action**: Install osslsigncode; use PKCS#11 bridge for hardware tokens (if using YubiKey)
```bash
apt-get install osslsigncode libengine-pkcs11-openssl
export PKCS11_MODULE=/usr/lib/x86_64-linux-gnu/libeToken.so
osslsigncode sign -pkcs11engine libpkcs11 -pkcs11module $PKCS11_MODULE \
  -spc cert.spc -key "keyid" -t http://timestamp.sectigo.com/rfc3161 \
  -h sha256 -in GUDE_Deploy.exe -out GUDE_Deploy.signed.exe
```
**Note**: osslsigncode is less featureful than signtool (no counter-signing, limited hash formats). Use for CI/CD sign-and-verify workflows only.

---

### Rule 6: Timestamp Server Health Check in CI/CD
**When**: Build + sign phase
**Action**: Wrap signing in retry loop; alert on timestamp server failure
```powershell
$maxRetries = 3
for ($i = 1; $i -le $maxRetries; $i++) {
    if (Test-Connection -ComputerName "timestamp.digicert.com" -Quiet) {
        signtool sign /fd sha256 /tr http://timestamp.digicert.com /td sha256 app.exe
        break
    }
    if ($i -eq $maxRetries) { throw "Timestamp server unreachable after $maxRetries attempts" }
    Start-Sleep -Seconds 10
}
```
**Rationale**: Timestamp server downtime = build failure (no workaround). Catch early.

---

## Decision Matrix: OV vs EV vs Azure Artifact Signing vs SignPath

| Criteria | OV (YubiKey) | EV (YubiKey) | Azure Artifact | SignPath |
|----------|---|---|---|---|
| **Annual cost** | $200-300 | $400-600 | $120 | N/A (OSS only) |
| **SmartScreen bypass?** | No (2024+ rule) | No (2024+ rule) | No | Yes (for OSS) |
| **Setup effort** | 4-6 hrs | 4-6 hrs | 1-2 hrs | Apply → vetting |
| **Hardware token required?** | Yes | Yes | No (cloud HSM) | No |
| **CI/CD runner type** | Self-hosted | Self-hosted | Cloud + Azure auth | Cloud + SignPath API |
| **Cert validity (2026)** | 460 days | 460 days | 3 days (timestamp crucial) | N/A |
| **For GUDE Deploy?** | ✓ Viable | ✗ Same SmartScreen as OV | ✓ Recommended | ✗ Not OSS |

**Recommendation**: **Azure Artifact Signing** for GUDE Deploy. Lowest cost, simplest CI/CD, identical SmartScreen outcome to OV, no hardware maintenance.

---

## Anti-Patterns Found

1. **Myth: EV certs grant instant SmartScreen clearance**
   - FALSE as of August 2024. Both EV and OV must build reputation organically.
   - Reference: [Microsoft Q&A SmartScreen OV/EV](https://learn.microsoft.com/en-us/answers/questions/417016/reputation-with-ov-certificates-and-are-ev-certifi)

2. **Myth: SHA-1 dual signing still needed for Windows 7**
   - FALSE. Windows 7 patched for SHA-256 (2015+). GlobalSign stopped issuing SHA-1 certs in 2021.
   - Dual signing only if supporting Windows XP SP3 or Vista (obsolete).

3. **Myth: You can store EV cert in a file**
   - FALSE since June 1, 2023. CA/Browser Forum mandates FIPS 140-2 Level 2+ hardware.
   - All new certs must use YubiKey, eToken, HSM, or cloud HSM (Azure).

4. **Myth: osslsigncode is a drop-in signtool replacement**
   - PARTIAL. osslsigncode works cross-platform but lacks signtool features (kernel-mode signing, EKU pinning, counter-signature chains).
   - Use for CI/CD automation only; prefer signtool on Windows for production signing.

5. **Myth: Timestamps are optional**
   - FALSE as of 2026. Cert validity = 460 days max. Timestamps keep signatures valid indefinitely.
   - Without `/tr` + `/td` in signtool, signature expires when cert does.

---

## Open Questions / Unverified

1. **SmartScreen numeric thresholds**: Microsoft docs state ~90% of downloads have reputation but don't publish threshold for "sufficient downloads." Anecdotal: 50-100 unique IPs over 2-4 weeks observed in practice (unverified).

2. **Azure Artifact Signing reputation equivalence**: No published comparison of Azure cert vs. OV cert for SmartScreen reputation velocity. Initial testing needed to confirm identical ramp-up.

3. **K Software vendor viability 2026**: Found as reseller in historical docs but not active in 2024-2026 search results. Status unclear (possible shutdown/consolidation).

4. **YubiKey firmware v5.7+ stability**: ECCP384 support newer; RSA4096 preferred for maximum compatibility. No production incident reports found, but newer codepath carries higher unknown-risk.

5. **SafeNet eToken 5110 CC current availability**: Certified for 2023+ code signing but rarely mentioned in 2024+ guides. Possible vendor phase-out; unclear if still purchasable.

6. **RFC 3161 timestamp cert expiration edge case**: If timestamp cert expires BEFORE code-signing cert, signature becomes invalid retroactively. Timestamp maintenance burden not addressed in vendor docs.

---

## Sources

- [Azure Artifact Signing (formerly Trusted Signing) - Microsoft Learn Quickstart](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)
- [Authenticode in 2025 – Azure Trusted Signing](https://textslashplain.com/2025/03/12/authenticode-in-2025-azure-trusted-signing/)
- [Microsoft Q&A - SmartScreen Reputation with OV Certificates](https://learn.microsoft.com/en-us/answers/questions/417016/reputation-with-ov-certificates-and-are-ev-certifi)
- [Entrust Blog - CA/B Forum Code Signing Private Keys](https://www.entrust.com/blog/2022/09/ca-browser-forum-updates-requirements-for-code-signing-certificate-private-keys)
- [Thales Blog - CA/B Forum Code Signing Requirements](https://cpl.thalesgroup.com/blog/encryption/ca-b-forum-code-signing-requirements-private-keys)
- [Sectigo Knowledge Base - YubiKey 5 FIPS HSM Installation](https://www.thesslstore.com/knowledgebase/code-signing-hardware/sectigo-yubikey-5-fips-hsm-certificate-installation/)
- [GitHub - mtrojnar/osslsigncode](https://github.com/mtrojnar/osslsigncode)
- [DigiCert - osslsigncode Tutorial](https://knowledge.digicert.com/tutorials/sign-a-windows-app-on-linux-using-osslsigncode)
- [Microsoft Learn - Time Stamping Authenticode Signatures](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)
- [Microsoft Learn - SmartScreen Application Reputation Building (Archive)](https://learn.microsoft.com/en-us/archive/blogs/ie/smartscreen-application-reputation-building-reputation)
- [K Software - SHA1/SHA-256/Dual Signing Truth](https://support.ksoftware.net/support/solutions/articles/215805-the-truth-about-sha1-sha-256-dual-signing-and-code-signing-certificates/)
- [Certum - Code Signing Certificates 2026 Updates](https://shop.certum.eu/code-signing.html)
- [SSL.com - Code Signing Certificate FAQ](https://www.ssl.com/faqs/which-code-signing-certificate-do-i-need-ev-ov/)
- [Melatonin - EV Cert Code Signing on GitHub Actions](https://melatonin.dev/blog/how-to-code-sign-windows-installers-with-an-ev-cert-on-github-actions/)
- [ForeLens Blog - AzureSignTool with Managed Identity](https://forelens.com/blog/github-actions-code-signing-with-azure-key-vault-hsm-rbac-oidc-and-managed-identity/)
- [SignPath Foundation - Open Source Code Signing](https://signpath.org/)
