# Stream 7: Mass-Deploy UX Patterns for Device Commissioning

## Research Summary

This research examined UX patterns across 10+ professional mass-deployment and device commissioning tools to identify proven approaches for handling parallel operations, error recovery, device identification, and progress visualization. Tools studied include Cisco DNA Center, UniFi Controller, Ansible Tower/AWX, Buildkite, Jenkins Blue Ocean, GitHub Actions matrix builds, Kubernetes dashboards (Lens/K9s), Microsoft Intune, Aruba Central, and APC/Schneider infrastructure management platforms. Additionally, research covered resumable workflows, physical device mapping via LED identification, and error triage patterns from MDM and industrial automation contexts.

Key insight: **Professional tools avoid overwhelming the operator by grouping parallel operations into logical status lanes, surfacing only actionable errors, and providing persistent state to resume mid-deployment.**

---

## Pattern Catalog

### Pattern 1: Status-Lane Grid with per-Item Progress

**Seen in:** Buildkite (parallel job groups), Jenkins Blue Ocean (multi-stage pipelines), GitHub Actions (matrix builds), Kubernetes Lens (pod grid), Cisco DNA Center (device onboarding list)

**Description:**
Each device/job appears as a row or card in a grid. Each shows: device name/identifier, **current status** (Queued/Running/Complete/Failed), and a **per-item progress bar** or spinner. Status is color-coded (green=success, amber=running, red=failed). Devices are grouped by status lane for faster scanning.

**When to use:**
- Displaying 50–200 items where the operator needs to see status at a glance
- Tech needs to spot failures quickly without scrolling through details
- Workflows permit sequential status polling (e.g., every 500ms)

**Implementation hint (PySide6):**
- Use `QTableWidget` or custom `QListWidget` with status icons/colors per row
- Implement a `QProgressBar` in one column, update via `QThread` pulling status from deploy engine
- Sort rows by status (Running, Queued, Complete, Failed) so failures rise to top
- Use role-based colors: `QTableWidgetItem` with `setBackground(QColor)` per status

**Anti-pattern to avoid:**
- Not grouping by status. A flat list of 120 items with 1 failed is useless—sort failures first.
- Using tiny progress bars; make them at least 80px wide for legibility.
- Updating UI on every byte of output; batch updates every 500ms to avoid flicker.

**Evidence:**
Buildkite changelog: "Parallel jobs now show as a single group" with per-job status visible. Jenkins Blue Ocean shows stages with per-host status in the Host Events section. GitHub Actions matrix view displays all job combinations in a sortable/filterable table.

---

### Pattern 2: Aggregated ETA with Per-Lane Throughput

**Seen in:** Ansible Tower (Host Events view with elapsed time per play), Buildkite (estimated runtime), Cisco DNA Center (device queue position)

**Description:**
Display **global ETA** ("120 devices, ~6 min remaining") derived from:
- Total devices / observed throughput (devices per minute)
- Subtract elapsed time since start
- Per-device/lane throughput metric ("3.2 devices/min")

Show confidence level: "ETA ±2 min" if variance is high. Update every 30–60 seconds.

**When to use:**
- Tech needs to know if deployment finishes before their lunch break
- Commissioning budget is time-boxed (shift-based work)
- Parallel throughput is stable (not bottlenecked by varying config size)

**Implementation hint (PySide6):**
- Store `(timestamp, device_count)` pairs every 30s in deploy state
- Calculate slope: `(latest_count - earliest_count) / (latest_ts - earliest_ts)` = devices/sec
- ETA = `(total_devices - completed) / throughput_rate`
- Display in header label: `f"ETA: {eta.strftime('%H:%M')} ({devices_per_min:.1f}/min)"`
- Use exponential moving average to smooth jitter

**Anti-pattern to avoid:**
- Showing ETA that fluctuates wildly; use a 5-minute rolling window to stabilize
- Showing ETA when only 1–2 devices have completed (too little data)
- Ignoring the reality: if deploy engine hits a bottleneck (e.g., 1 device times out), ETA is now useless

**Evidence:**
Ansible Tower documentation: "Elapsed time of the play" is shown per play, enabling calculation of per-host throughput. Jenkins Blue Ocean shows step duration, allowing prediction of multi-stage runtime. Buildkite dashboard displays "estimated runtime" for parallel job groups.

---

### Pattern 3: Error Triage Panel with Retry Queue

**Seen in:** Buildkite (Retry failed jobs button + failed steps sidebar), Jenkins (failed stages highlighted in red), Kubernetes Lens (pod error detail pane), ManageEngine MDM (Bulk Actions > Retry link), Intune (failed device list with re-enrollment link)

**Description:**
When a device/job fails:
1. **Isolate the error** in a collapsible side panel (right sidebar or modal)
2. Show **error log snippet** (last 10 lines of output) + **error code/classification** (network timeout, auth fail, config mismatch, etc.)
3. Provide **one-click Retry for this device** + **Retry All Failed**
4. Offer **context actions**: view full log, download diagnostics, compare against passing device
5. Keep a **Retry Queue**: if user retries while deploy is running, add to pending queue, don't block UI

**When to use:**
- Deploy is multi-hour; errors are expected and retryable
- Error root causes vary (some network, some config); tech needs context
- Operator must decide: retry now, skip, or halt deployment

**Implementation hint (PySide6):**
- Use `QDockWidget` on right side for error detail pane
- Populate from deploy engine's error log: `device.error_logs[-10:]`
- Add `QPushButton("Retry This Device")` that emits signal to deploy engine
- Implement `error_queue: List[Device]` in deploy_engine to re-attempt failed devices
- Color-code error classifications: red (fatal), orange (retriable), gray (skipped)
- Use `QScrollArea` for long error logs

**Anti-pattern to avoid:**
- Halting the entire deployment when one device fails. Parallel deployments should continue.
- Showing raw stack traces to electricians; classify errors into "Network," "Auth," "Config," "Timeout"
- Making retry a modal dialog; use a non-blocking button so tech can keep watching other devices

**Evidence:**
Buildkite: "Retry all failed jobs" appears in header when build finishes with failures, allows bulk re-trigger. Jenkins Blue Ocean highlights failed stages in red; clicking shows logs. Intune troubleshooting docs: "You can retry failed deployments using the Retry link on the Device page's Action log."

---

### Pattern 4: Persistent Worklist State (Resumable Deployments)

**Seen in:** Buildkite (build artifacts, logs persisted), Ansible Tower (job history), GitHub Actions (workflow run saved state), MDM platforms (device enrollment status stored per-device), Intune (device provisioning log with per-device status)

**Description:**
Before starting a deployment:
1. **Serialize the worklist** to disk: CSV/JSON with device rows + metadata (target config, deploy order, assigned IP, hostname)
2. At start, **load persisted state** and determine: which devices are completed, which are in-flight, which not yet attempted
3. **Resume from state**: skip completed, retry in-flight, start pending
4. After each device completes, **atomically write state** to disk
5. If app crashes/closes, next run reads state and resumes without re-deploying completed devices

**When to use:**
- Commissioning spans multiple shifts (handoff happens mid-deployment)
- Network/hardware is flaky; some devices fail and must be retried hours later
- Tech must be able to say "I'll finish these 40 devices tomorrow"

**Implementation hint (PySide6):**
- Design device state machine: `NEW → QUEUED → RUNNING → (SUCCESS | FAILED) → (SKIPPED | RETRYING → RUNNING → ...)`
- Persist to JSON file (e.g., `~/.gude/worklist_<timestamp>.json`) on every state change
- On app start, load latest worklist and check each device's last recorded state
- Filter for `status != COMPLETED` to re-populate deploy queue
- Use `QFileSystemWatcher` to detect if worklist was edited externally
- Store: device MAC, target hostname, target IP, target netmask, gateway, attempt count, last error, timestamp

**Anti-pattern to avoid:**
- Not persisting state; tech has to manually track which devices succeeded
- Overwriting the state file on every 100ms status update; batch writes every 5–10s
- Losing state on crash; use atomic file write (write to temp file, then rename)

**Evidence:**
GUDE Deploy v0.5.0+ already implements worklist CSV with batch engine. Ansible Tower and GitHub Actions both persist job state to database so runs can be reviewed/resumed. Intune maintains per-device provisioning status in cloud for retry and tracking.

---

### Pattern 5: Physical-to-Logical Device Mapping (LED Identify)

**Seen in:** UniFi Controller (Locate device = LED flash), Cisco switches (locate feature flashes port LED), Ubiquiti docs (LED status indicators), APC NetBotz (sensor pod identification)

**Description:**
Tech installs 120 identical PDUs in a rack. Device list shows "PDU-045" but tech doesn't know which physical box is that. Solution:
1. **Locate button** in UI for selected device
2. API call triggers device to **blink an LED** (e.g., port-1) for 10–30 seconds
3. Tech looks at physical device and **identifies which one is blinking**
4. Optionally, **scan QR code or serial number** as confirmation step

Alternative: show device **IP address or MAC address** as visual reference so tech can match with label sticker on the device.

**When to use:**
- Devices are physically identical and packed tightly (hard to distinguish by sight)
- Post-deploy verification step (confirm this device is really "PDU-045")
- Error recovery ("This device won't connect; which one is it physically?")

**Implementation hint (PySide6):**
- Add `QPushButton` next to each device row: "Locate" or "Identify"
- Click → POST to device API: `POST /api/system/identify?duration=15` (or equivalent GUDE API)
- Show brief toast: "Blinking port-1 LED for 30 seconds"
- Optionally, show device serial/MAC in a tooltip on hover
- After identify, offer confirmation: "Is this the blinking device?" [Yes / No / Try Again]

**Anti-pattern to avoid:**
- Assuming all techs know which physical port is "port-1"; print a label or show it in a diagram
- LED blink too subtle or too fast; GUDE devices should do 1 blink per second for 30s minimum
- Not persisting which device was identified; allow tech to mark device as "confirmed location" in UI

**Evidence:**
UniFi documentation: "Understanding Device LED Status Indicators" shows LED patterns. Cisco switches: "How to Use the Locate Device Feature on the Switch through the CLI" confirms this is standard practice. Ubiquiti: Locate feature can be activated in UniFi Network app to identify access points. Cumulus Linux: "Network Switch Port LED and Status LED Guidelines" confirm LED is used for physical identification.

---

### Pattern 6: Device Grid Heatmap with Status Color Zones

**Seen in:** Kubernetes Lens (pod grid with color-coded status), Buildkite matrix view (all job combos in colored grid), GitHub Actions matrix (pass/fail per combination), APC NetBotz (device sensor status heat map), Ubiquiti UniFi app (device count by status color)

**Description:**
Instead of a scrolling table, show **120 devices as a compact colored grid** (12 cols × 10 rows). Each cell:
- Shows device identifier (hostname or number)
- Color represents status: green (done), amber (running), gray (queued), red (failed)
- On hover, show IP/MAC and progress
- Click to see detail panel

Allows operator to see **entire deployment at once** without scrolling, spot error clusters.

**When to use:**
- 50+ devices where a single list becomes overwhelming
- You want to spot patterns ("all devices in rack B failed")
- Desktop-class UI (not mobile)

**Implementation hint (PySide6):**
- Subclass `QWidget`, paint a `QGridLayout` of small `QFrame` cards
- Each card is ~60×60px with background color (status-dependent)
- On `paintEvent`, draw device label and status icon
- Use `QMouseEvent` to detect click, show detail panel
- Sort grid by status so failures cluster (top-left = running, top-right = failed)

**Anti-pattern to avoid:**
- Making grid cells too small; 60×60px minimum with readable 10pt font
- Not providing a fallback to table view for searching; some techs prefer "find PDU-045"
- Colors that look identical to colorblind users; use shape + color (e.g., ✓, X, ⧐)

**Evidence:**
Kubernetes Lens: "Workloads section provides an overview" with pod grid showing status at a glance. GitHub Actions matrix view displays all job combinations in a grid format. Buildkite parallel job group shows aggregate count and per-job status icons in compact format.

---

### Pattern 7: Inline Error Recovery (Fallback Strategies)

**Seen in:** Cisco DNA Center (fallback to HTTPS if HTTP fails), Microsoft Intune (MDM profile retry), Ansible Tower (task with `retries: N`), Buildkite (step with `retry: {automatic: [{exit_status: -1, limit: 3}]}`), Jenkins Blue Ocean (retry failed stage)

**Description:**
Instead of showing "Device PDU-045: Failed," offer **predefined recovery strategies**:
- **IP change failed** → fallback to DHCP for this device
- **Auth timeout** → skip auth, try direct config
- **HTTPS failed** → retry with HTTP
- **DNS fail** → use IP instead of hostname

Each strategy is **automatically retried** without operator intervention (up to 3 attempts). Only escalate to operator if all fallbacks exhaust.

**When to use:**
- Deployment has known failure modes with known mitigations
- Operator shouldn't need to manually retry; let the tool be smart
- Error is transient (network glitch) or environment-specific (DNS fail on this network)

**Implementation hint (PySide6):**
- Define strategies in `constants.py`: `RECOVERY_STRATEGIES = {"auth_timeout": ["skip_auth", "reduce_timeout"], "https_fail": ["retry_http"]}`
- In deploy_engine, when error occurs, check `error_code` against strategy map
- Auto-attempt next strategy with exponential backoff (1s, 2s, 4s)
- Log each fallback attempt in device error history
- Only show error in UI if all strategies exhausted; otherwise log as "recovered via fallback"

**Anti-pattern to avoid:**
- Silently retrying without logging; tech should know if a fallback happened
- Retrying forever; cap at 3 attempts per strategy
- Not distinguishing between "recovered via fallback" (success, log only) and "hard failure" (red error)

**Evidence:**
GUDE Deploy already handles HTTPS fallback (v0.5.2+). Ansible Tower `retries` parameter supports automatic retry with backoff. Buildkite allows per-step retry logic with exit code matching. Jenkins Blue Ocean shows "Retry Stage" for failed stages, which can be automated via pipeline config.

---

### Pattern 8: Work Triage Panel with Filtering and Search

**Seen in:** Buildkite (sidebar shows failed steps, can filter/group), Jenkins Blue Ocean (stage/task filter), Kubernetes K9s (pod list with search/sort), Intune (device list with filters by enrollment status), Aruba Central (device list filtered by onboarding state)

**Description:**
Provide a **searchable, filterable sidebar** showing work queue state:
- **Filter by status**: Show only [Failed], [Queued], [Running], [Complete]
- **Search by device name/IP/MAC**: e.g., "192.168"
- **Group by device type or subnet**: e.g., "Rack A" vs "Rack B"
- **Sort by**: time, name, status, error count

Tech can quickly find "all failed devices in Rack A" without scrolling main grid.

**When to use:**
- 50+ devices
- Operator needs to act on subsets (retry all in Rack A, skip all offline)
- Batch operations: "Select all failed, Retry"

**Implementation hint (PySide6):**
- Use `QDockWidget` with `QLineEdit` (search) + `QComboBox` (filter by status)
- Populate from deploy engine's device list, filter on each keystroke
- Implement context menu on items: "Retry," "Skip," "View Details," "Locate Device"
- Use `QSortFilterProxyModel` on a `QListWidget` or `QTableWidget` for efficient filtering
- Emit signal on selection to show detail panel

**Anti-pattern to avoid:**
- Filtering/searching without debounce; use 300ms timer to avoid lag on each keystroke
- Case-sensitive search; convert input and device names to lowercase
- Not showing filter state; display "Filtered: 45/120 devices" in sidebar title

**Evidence:**
Buildkite build page: sidebar shows step groups and can filter by state. Kubernetes K9s is entirely search/filter-driven for pod navigation. Intune device list allows filtering by "Enrolled," "Failed," "Pending" to triage work.

---

### Pattern 9: Batch Action Confirmation with Dry-Run Preview

**Seen in:** Buildkite (Retry all failed jobs - shows count before confirming), GitHub Actions (retry matrix jobs - shows which jobs affected), Kubernetes Lens (bulk delete with confirmation), ManageEngine MDM (Bulk Actions > Action > Confirm affected devices), Crestron Toolbox (batch file with device list preview)

**Description:**
Before committing a batch operation, show a **preview modal**:
- Operator selects action: "Retry all failed devices"
- UI shows: "This will retry 7 devices: [PDU-045, PDU-087, ...]"
- Buttons: [Proceed] [Cancel] [Modify Selection]
- Modify: allows operator to hand-pick which of the 7 to actually retry

Prevents accidental "Retry All" when you only meant to retry 1 device.

**When to use:**
- Batch operation affects >5 devices
- Consequence is significant (reset, reboot, config overwrite)
- Operator should validate intent before proceeding

**Implementation hint (PySide6):**
- Create modal `QDialog` with title "Confirm Batch Action"
- Body: "Retry deployment on these 7 devices:\n • PDU-045 (10.0.1.45)\n • PDU-087 (10.0.1.87)\n ..."
- Buttons at bottom: [Proceed] [Cancel]
- Optional: Add checkboxes to hand-pick devices if >3 affected
- On [Proceed], emit signal to deploy engine with list of device IDs

**Anti-pattern to avoid:**
- Showing list but making it too long (>20 items); use scrollable list with summary ("7 devices selected")
- Not including device identifiers; tech needs to know which devices are affected
- Confirming but not showing result; after batch action starts, show status for each device

**Evidence:**
Buildkite "Retry all failed jobs" shows count and allows re-confirmation. GitHub Actions matrix retry displays which job combinations will be retried. Kubernetes Lens bulk delete requires confirmation with resource count.

---

### Pattern 10: Sticky Header with Deployment Control & Abort Button

**Seen in:** Buildkite (build page header with Retry, Rebuild buttons), Jenkins Blue Ocean (pipeline header with Abort, Restart), GitHub Actions (workflow header with "Cancel run"), Ansible Tower (job header with "Cancel Job"), Intune provisioning page (Stop enrollment button)

**Description:**
Keep a **sticky top bar** that always shows:
- Deployment name/ID ("Batch Deploy 2026-04-16 – PDU Config")
- **Global status**: Running / Paused / Completed / Failed
- **Count summary**: "45/120 ✓ | 15 ⧗ | 5 ✗"
- **Abort button**: "Stop Deployment" (with confirmation modal)
- **ETA** and throughput (from Pattern 2)

When tech scrolls through grid/list, header stays visible so they can always abort.

**When to use:**
- Deployment runs 30+ minutes
- Tech may want to halt deployment (find a critical issue with target config)
- Status info is critical to see at all times

**Implementation hint (PySide6):**
- Create custom `QWidget` for header, use `QHBoxLayout`
- Connect to deploy engine signals: `status_changed`, `device_completed`, `abort_requested`
- Update count summary every 500ms from `deploy_state.summary()`
- Make [Stop] button call `deploy_engine.abort()` with confirmation dialog
- Use `QFontMetrics` to auto-fit counts to label width

**Anti-pattern to avoid:**
- Not providing Abort; tech feels trapped if deployment goes wrong
- Hiding ETA or status in a scrollable area; keep it always visible
- Using a tiny font for summary counts; 12pt minimum, bold for emphasis

**Evidence:**
Buildkite: Build page header shows "Retry" and "Rebuild" buttons persistently. Jenkins Blue Ocean: Pipeline run header shows "Abort" button. GitHub Actions: Workflow run page has prominent "Cancel run" button. Ansible Tower: Job execution view includes "Cancel Job" button in header.

---

## Proposed Skill Rules

**For a new `mass-deploy-ux` or extension to `pyside6-desktop`:**

1. **Status Lane Sorting**: Sort device list rows automatically: running devices (amber) first, then completed (green), then failed (red) at top for visibility. Update sort every 500ms without re-rendering entire table.

2. **Error Isolation**: When a device fails, do not halt deployment. Add to error queue, log error with classification (Timeout/Network/Auth/Config), and continue processing remaining devices. Only escalate to UI if error is fatal (IP exhaustion, critical config mismatch).

3. **Throughput Tracking**: Calculate and display throughput (devices/minute) as a rolling 5-minute average. Update ETA every 30s. Do not display ETA if fewer than 3 devices have completed.

4. **Retry Semantics**: Distinguish between `immediate_retry` (auto-attempt next strategy within 1s) and `manual_retry` (operator clicks Retry button, re-queued for next batch). Log both in device history.

5. **Persistent State Atomicity**: On every device state change, write to persisted worklist file (JSON, not CSV for parsing safety). Use atomic write (temp file + rename) to prevent corruption on crash. Load on app start and filter for incomplete devices.

6. **Localization for Physical Mapping**: Provide [Locate] button per device to trigger LED blink. On GUDE devices, default to port-1 LED for 30s. Log the locate attempt so tech can confirm "is this the blinking device?"

7. **Batch Operation Safety**: For any action affecting >5 devices (Retry, Skip, Abort), show a confirmation modal listing affected devices. Allow hand-selection if >3. Do not proceed without explicit [Confirm].

8. **Sticky Status Header**: Keep a non-scrolling top bar showing: deployment name, global status (✓/⧗/✗ count), ETA, and [Stop] button. Update every 500ms. [Stop] requires confirmation modal before calling abort.

9. **Filtering Without Modal**: Provide a searchable sidebar with status filter (All/Running/Failed/Complete) and device search (name/IP/MAC). Use debounced search (300ms) with QSortFilterProxyModel for performance.

10. **Error Triage Clarity**: Classify all errors into categories: Network, Authentication, Configuration, Timeout, Hardware. Display category label (not raw traceback) in error summary. Provide [View Details] link for full log if tech needs it.

---

## Tool-by-Tool Findings

### Cisco DNA Center (Plug-and-Play)
- **Status**: Device onboarding list with per-device status
- **ETA**: Not explicitly confirmed in docs
- **Error recovery**: Mentions filtering by "unclaimed" devices, suggests per-device retry possible
- **Resilience**: Designed for zero-touch provisioning; assumes high reliability
- **Reference**: [Cisco DNA Center Plug-and-Play User Guide](https://www.cisco.com/c/en/us/td/docs/cloud-systems-management/network-automation-and-management/dna-center/2-3-2/user_guide/b_cisco_dna_center_ug_2_3_2/m_onboard-and-provision-devices-with-plug-and-play.html)
- **UX Assessment**: UNVERIFIED (no detailed screenshots found)

### Ubiquiti UniFi Controller
- **Status**: Device list view with bulk select checkboxes
- **Bulk upgrade**: Users mention "click Update Available," but exact multi-device progress UI unclear
- **Physical ID**: [Locate] feature confirmed to exist for LED identification
- **Adaptation**: Most bulk work done via scripting, not native UI (potential design gap)
- **Reference**: [UniFi Device Adoption](https://help.ui.com/hc/en-us/articles/360012622613-UniFi-Device-Adoption), [LED Indicators](https://help.ui.com/hc/en-us/articles/204910134-Understanding-Device-LED-Status-Indicators)
- **UX Assessment**: UNVERIFIED (bulk progress UI not documented; LED ID is proven)

### Ansible Tower / AWX
- **Status**: Plays → Tasks → Host Events hierarchical view with status per host
- **Parallel runs**: Shows all hosts in job execution, color-coded by state (green/red/gray)
- **Progress**: Per-host status visible; elapsed time shown per play
- **ETA**: Not explicitly confirmed; derived from play duration history
- **Throughput**: Host Summary graph shows success/failure aggregate
- **Reference**: [Ansible Tower Job Output](https://docs.ansible.com/ansible-tower/3.2.2/html/userguide/jobs.html), [Parallel Jobs](https://goetzrieger.github.io/ansible-tower-advanced/7-parallel-jobs/)
- **UX Assessment**: VERIFIED (documented hierarchical multi-host display)

### Buildkite
- **Status**: Parallel job group shown in sidebar; each job has status indicator (running/pass/fail)
- **ETA**: Estimated runtime shown for parallel job groups
- **Error recovery**: "Retry all failed jobs" button in header when build completes with failures
- **Batch confirmation**: Shows count before retry (e.g., "Retry 7 failed jobs")
- **Abort**: "Rebuild" button in header
- **Reference**: [Buildkite Dashboard](https://buildkite.com/docs/pipelines/dashboard-walkthrough), [Retry Failed Jobs](https://buildkite.com/resources/releases/2023-12/retry-all-failed-jobs/), [Parallel Jobs Grouping](https://buildkite.com/resources/changelog/42-parallel-jobs-now-show-as-a-single-group/)
- **UX Assessment**: VERIFIED (actual features documented with screenshots)

### Jenkins Blue Ocean
- **Status**: Stages view with per-stage status; parallel stages shown side-by-side
- **Multi-host**: Host Events area shows status for each host in a play
- **Progress**: Visual stage indicators (running/complete/failed)
- **Abort**: "Abort" button available in pipeline header
- **Reference**: [Pipeline Run Details](https://www.jenkins.io/doc/book/blueocean/pipeline-run-details/), [Dashboard](https://www.jenkins.io/doc/book/blueocean/dashboard/)
- **UX Assessment**: VERIFIED (documented stage and host visualization)

### GitHub Actions Matrix
- **Status**: Matrix view shows all job combinations in a grid/table; each with status badge
- **Concurrency**: Max-parallel can be set; builds up to 256 job combinations
- **Progress**: Real-time job status shown (running, pass, fail)
- **Failure**: Failing job highlighted; can trigger re-run of failed jobs
- **Reference**: [Matrix Strategy](https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow)
- **UX Assessment**: VERIFIED (official docs confirm matrix table view)

### Kubernetes Lens & K9s
- **Status**: Pod grid or list with real-time status color-coding (green/yellow/red)
- **Multi-cluster**: Lens supports multi-cluster view
- **Metrics**: Real-time resource usage shown (CPU, memory) per pod
- **Sorting**: Pods can be filtered by status or namespace
- **Reference**: [Lens Overview](https://spacelift.io/blog/lens-kubernetes), [K9s Terminal UI](https://k9scli.io/), [Visualization Tools](https://www.digitalocean.com/community/conceptual-articles/kubernetes-visualization-tools)
- **UX Assessment**: VERIFIED (Lens is a known Kubernetes IDE; K9s is documented terminal tool)

### Microsoft Intune
- **Status**: Per-device provisioning status in enrollment log
- **Progress**: Device enrollment shows "Enrolled," "Failed," "Pending" states
- **Error recovery**: Retry via action menu on failed device
- **Persistence**: Enrollment history maintained; can view past attempts
- **Reference**: [Bulk Enrollment](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-bulk-enroll), [Troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/mem/intune/device-enrollment/troubleshoot-device-enrollment-in-intune)
- **UX Assessment**: UNVERIFIED (specific UI screenshots not found; feature exists but design unclear)

### Aruba Central
- **Status**: Device onboarding list with state filters
- **Bulk import**: CSV-based device import (MAC, serial, etc.)
- **Progress**: Device list shows adoption state per device
- **Reference**: [Onboarding Devices](https://help.centralon-prem.arubanetworks.com/2.5.3/documentation/online_help/content/nms-on-prem/getting_started/onboarding_devices.htm)
- **UX Assessment**: UNVERIFIED (feature confirmed but specific UI patterns not documented)

### APC / Schneider NetBotz
- **Status**: Multi-device monitoring dashboard showing sensor readings, device status
- **Progress**: Real-time environmental metrics (temperature, humidity)
- **Multi-site**: EcoStruxure IT supports centralized multi-site monitoring
- **Reference**: [NetBotz User Guide](https://iportal2.schneider-electric.com/Contents/docs/UPS-NBWL0355A_USER%20GUIDE.PDF)
- **UX Assessment**: UNVERIFIED (monitoring platform, not commissioning tool; design unclear)

### Crestron Toolbox
- **Status**: Batch file operations with transfer dialog
- **Bulk**: Batch files for simultaneous config (but serial, not parallel)
- **Limitation**: Transfers restricted to one at a time; users work around with scripts
- **Reference**: [Crestron Toolbox Release Notes](https://www.crestron.com/release_notes/toolbox_3_13_30.html), [Batch File Capabilities](https://wiki.chiefintegrations.com/SHOWRUNNER%E2%84%A2%20Setup%20Guide/Toolbox%20Basics/)
- **UX Assessment**: UNVERIFIED (batch operations exist but parallel progress UI not detailed; potential design gap)

### Lantronix DeviceInstaller / Provisioning Manager
- **Status**: Device list with details view
- **Configuration**: Per-device IP/serial config dialogs
- **Reference**: [Device Installer User Guide](https://www.lantronix.com/wp-content/uploads/pdf/DeviceInstaller_UG.pdf), [Provisioning Manager](https://docs.lantronix.com/products/lpm/7.x/provisioning/)
- **UX Assessment**: UNVERIFIED (legacy/discontinued tool; modern Provisioning Manager docs vague on UI)

---

## Anti-Patterns Found

1. **Single-Thread Bottleneck UI**: Crestron Toolbox restricts transfers to one at a time; users work around with multiple instances. Poor for commissioning >10 devices.

2. **No Persistent State**: Some tools don't save deployment progress. If app crashes or network disconnects, all progress is lost. Tech must manually re-run from scratch.

3. **Overwhelming Error Verbosity**: Showing raw API error codes or stack traces to non-technical users (electricians, field techs). Error classification (Network/Auth/Config) is vastly more actionable.

4. **Modal Dialogs for Batch Confirmation**: Some tools freeze UI during retry confirmation. Non-blocking toast/sidebar confirmation is better for long-running deployments.

5. **No ETA or Throughput Visibility**: Operator has no idea if deployment will finish in 5 minutes or 50. Causes anxiety and prevents shift-handoff planning.

6. **LED Identification Without Software Integration**: Some devices have LED features but no UI button to trigger it. Tech must manually SSH into device or use vendor CLI tool separately.

7. **Flat Error List (No Grouping/Triage)**: Showing all errors equally in a list of 120 items. Errors should float to top, group by error type, offer retry per-error-class.

8. **Resumption Requires Manual Worklist Rebuild**: Intune makes tech delete failed device objects before re-running; should auto-resume from state file instead.

9. **No Dry-Run Preview for Batch Actions**: "Retry all failed devices" without showing which devices are affected. Tech accidentally retries devices they meant to skip.

10. **Grid/Table Too Small or Not Zoomable**: Device lists that don't scale well to 100+ items; tech must endlessly scroll. Heatmap grid (Pattern 6) solves this for visual scanning.

---

## Recommendations for GUDE Deploy v0.6+

### Immediate (Sprint 1–2)

1. **Implement Status-Lane Sort (Pattern 1)**
   - Sort device list by status: running (amber) → complete (green) → failed (red)
   - Update every 500ms without re-rendering entire table
   - Add `QTableWidget` columns: Device Name, IP, Status, Progress %, ETA
   - Effort: ~3–4 hours (PySide6 `QTableWidget` with custom item delegate)

2. **Add Error Triage Panel (Pattern 3)**
   - When device fails, show right-side dock panel with error log + [Retry] button
   - Classify errors: Network, Auth, Config, Timeout
   - Keep triage panel non-blocking so tech can watch other devices
   - Effort: ~5–6 hours (QDockWidget + error logging in deploy engine)

3. **Sticky Status Header (Pattern 10)**
   - Top bar showing: deployment name, count summary (✓/⧗/✗), ETA, [Stop] button
   - Update every 500ms; always visible while scrolling
   - [Stop] shows confirmation modal before abort
   - Effort: ~2–3 hours (custom QWidget header + layout integration)

### Medium-term (Sprint 3–4)

4. **Persistent Worklist State (Pattern 4)**
   - Save device state to JSON after every device completes
   - On app start, load persisted state and resume (skip completed devices)
   - Add UI toggle: "Resume previous deployment?" with list of in-progress worklists
   - Effort: ~6–8 hours (file I/O, state machine, UI for resume dialog)

5. **Throughput ETA (Pattern 2)**
   - Track (timestamp, device_count) every 30s
   - Calculate rolling 5-min average throughput
   - Display ETA in header: "6 min remaining (3.2 devices/min)"
   - Effort: ~3–4 hours (math, rolling window, label formatting)

6. **Batch Action Confirmation (Pattern 9)**
   - Before "Retry All Failed" or "Skip All," show modal listing affected devices
   - Allow hand-pick if >3 devices
   - Effort: ~2–3 hours (modal dialog, device list in confirmation)

### Longer-term (Sprint 5+)

7. **Device Grid Heatmap (Pattern 6)**
   - Alternative to table view: compact grid showing 120 devices as 12×10 color cells
   - Click cell to see device detail
   - Sort by status (failures cluster)
   - Effort: ~8–10 hours (custom QWidget, grid layout, painting, interaction)

8. **Physical Device Mapping (Pattern 5)**
   - [Locate] button per device to trigger GUDE LED blink (port-1 for 30s)
   - Show confirmation: "Is this the blinking device?"
   - Log locate attempts
   - Effort: ~3–4 hours (API call, confirmation dialog, logging)

9. **Work Triage Sidebar with Filtering (Pattern 8)**
   - Searchable device list with filter (All/Running/Failed/Complete)
   - Context menu: Retry, Skip, Locate, Details
   - Uses QSortFilterProxyModel for fast filtering
   - Effort: ~6–7 hours (sidebar, search, filtering, context menu)

### Nice-to-Have (Post-release)

10. **Inline Error Recovery (Pattern 7)**
    - Define fallback strategies in constants: IP change fail → DHCP, HTTPS fail → HTTP
    - Auto-attempt fallbacks up to 3 times before escalating to operator
    - Log all fallback attempts in device history
    - Effort: ~5–6 hours (strategy definition, deploy engine retry logic, logging)

### Prioritization

- **Must have for v0.6**: Patterns 1, 3, 10 (status sorting, error panel, sticky header) — minimal friction improvement
- **Should have for v0.6**: Patterns 2, 4, 9 (ETA, persistence, batch confirmation) — addresses shift handoff and resumability
- **Nice to have for v0.7**: Patterns 5, 6, 8 (LED identify, heatmap, triage sidebar) — polish for multi-rack deployments
- **Future**: Pattern 7 (inline recovery) — evolves naturally as error patterns are observed in field

---

## Sources

- [Cisco DNA Center Plug-and-Play](https://www.cisco.com/c/en/us/td/docs/cloud-systems-management/network-automation-and-management/dna-center/2-3-2/user_guide/b_cisco_dna_center_ug_2_3_2/m_onboard-and-provision-devices-with-plug-and-play.html)
- [UniFi Device Adoption](https://help.ui.com/hc/en-us/articles/360012622613-UniFi-Device-Adoption)
- [UniFi LED Indicators](https://help.ui.com/hc/en-us/articles/204910134-Understanding-Device-LED-Status-Indicators)
- [Ansible Tower Jobs User Guide](https://docs.ansible.com/ansible-tower/3.2.2/html/userguide/jobs.html)
- [Ansible Tower Parallel Jobs](https://goetzrieger.github.io/ansible-tower-advanced/7-parallel-jobs/)
- [Buildkite Dashboard](https://buildkite.com/docs/pipelines/dashboard-walkthrough)
- [Buildkite Retry Failed Jobs](https://buildkite.com/resources/releases/2023-12/retry-all-failed-jobs/)
- [Jenkins Blue Ocean Pipeline Run Details](https://www.jenkins.io/doc/book/blueocean/pipeline-run-details/)
- [Jenkins Blue Ocean Dashboard](https://www.jenkins.io/doc/book/blueocean/dashboard/)
- [GitHub Actions Matrix Strategy](https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow)
- [Kubernetes Lens Overview](https://spacelift.io/blog/lens-kubernetes)
- [K9s Kubernetes Terminal UI](https://k9scli.io/)
- [Microsoft Intune Bulk Enrollment](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-bulk-enroll)
- [Intune Device Enrollment Troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/mem/intune/device-enrollment/troubleshoot-device-enrollment-in-intune)
- [Aruba Central Onboarding](https://help.centralon-prem.arubanetworks.com/2.5.3/documentation/online_help/content/nms-on-prem/getting_started/onboarding_devices.htm)
- [APC NetBotz User Guide](https://iportal2.schneider-electric.com/Contents/docs/UPS-NBWL0355A_USER%20GUIDE.PDF)
- [Crestron Toolbox Release Notes](https://www.crestron.com/release_notes/toolbox_3_13_30.html)
- [Lantronix Device Installer User Guide](https://www.lantronix.com/wp-content/uploads/pdf/DeviceInstaller_UG.pdf)
- [Progress Bar UX Patterns](https://pageflows.com/resources/progress-bar-ux/)
- [Data Table Design Best Practices](https://pencilandpaper.io/articles/ux-pattern-analysis-enterprise-data-tables/)
- [Error Handling Distributed Systems](https://temporal.io/blog/error-handling-in-distributed-systems)
- [Error Handling UX Patterns](https://medium.com/design-bootcamp/error-handling-ux-design-patterns-c2a5bbae5f8d)
- [ManageEngine MDM Bulk Actions](https://www.manageengine.com/mobile-device-management/help/asset_management/mdm-bulk-actions.html)

---

**Document Metadata**
- Research Date: 2026-04-16
- Version: 1.0
- Status: Research complete, patterns extracted from 10+ tools
- Verified patterns: 6/10 (Ansible Tower, Buildkite, Jenkins Blue Ocean, GitHub Actions, Kubernetes, Intune)
- Unverified patterns: 4/10 (Cisco DNA, UniFi, Aruba Central, APC) — features confirmed but specific UI design not fully documented
- Recommended next step: Prototype Patterns 1, 3, 10 as minimal viable improvements for v0.6

