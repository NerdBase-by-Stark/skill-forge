---
name: mass-deploy-ux
description: UX patterns for desktop tools that commission or configure device fleets in parallel — status grids, error triage, resumable worklists, LED locate, throughput ETA. Use when designing a UI that tracks 50+ parallel device operations.
filePattern:
  - "**/batch*.py"
  - "**/worklist*.py"
  - "**/deploy_engine.py"
  - "**/deploy_page.py"
  - "**/batch_*.py"
bashPattern: []
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# Mass-Deploy UX — Parallel Device Commissioning

Patterns for building UIs that orchestrate 50-1000 parallel operations against physical devices (PDUs, switches, APs, IoT fleets, MDM-managed endpoints) without overwhelming the technician running the deployment.

Pairs with `pyside6-desktop` (Qt widget patterns) and `network-device-discovery` (underlying parallel-deploy engine). This skill covers the *interaction design* layer.

---

## Core design principle

A technician running a 120-device commissioning deployment is anxious, possibly on a deadline, and can't hold 120 device states in their head. The UI's job is to:

1. **Collapse state into status lanes** — never show a flat list of 120 equal things
2. **Surface only actionable information** — raw stack traces ≠ useful
3. **Survive shift changes and crashes** — state must persist to disk
4. **Keep running when things fail** — never halt on a single-device error
5. **Always tell the user what's next** — ETA, throughput, count summary always visible

What follows are 10 concrete patterns from tools that got this right, each with a PySide6 implementation hint and the anti-pattern to avoid.

---

## Pattern 1: Status-Lane Sorted Grid with Per-Item Progress

**Seen in:** Buildkite parallel job groups, Jenkins Blue Ocean, GitHub Actions matrix, Kubernetes Lens, Cisco DNA Center

Each device is one row. Columns: device name/ID, current status (Queued/Running/Complete/Failed), per-device progress bar, ETA, last error (if any). Rows are **sorted by status** so failures float to the top, not buried mid-list.

```python
# PySide6 implementation hint
class DeviceGridView(QTableWidget):
    STATUS_ORDER = {"failed": 0, "running": 1, "queued": 2, "complete": 3}

    def _refresh(self):
        items = sorted(self._devices, key=lambda d: (
            self.STATUS_ORDER[d.status],
            d.hostname,
        ))
        for row, device in enumerate(items):
            self._set_row(row, device)

    def _set_row(self, row, device):
        color = {
            "failed": QColor("#fce4e4"),
            "running": QColor("#fff4d6"),
            "queued": QColor("#f1f3f4"),
            "complete": QColor("#e6f4ea"),
        }[device.status]
        for col in range(self.columnCount()):
            item = self.item(row, col)
            if item:
                item.setBackground(color)
```

**Anti-pattern:** Inserting new rows as devices finish (order jumps around). Always sort the full list on each refresh.

**Anti-pattern:** Re-rendering the whole table on every progress tick. Batch UI updates with a `QTimer` at 500ms — faster than the eye sees anyway.

## Pattern 2: Throughput-Based ETA (Rolling Window)

**Seen in:** Ansible Tower (elapsed per play), Buildkite (estimated runtime), Jenkins Blue Ocean (stage duration)

Showing "ETA: 14:32" beats "ETA: 6m 12s" after 20 minutes — absolute times don't drift. Calculate from a **5-minute rolling throughput window**, not from inception (otherwise a slow start dominates the estimate forever).

```python
class ThroughputEstimator:
    def __init__(self, window_seconds: int = 300):
        self._samples: deque[tuple[float, int]] = deque()
        self._window = window_seconds

    def record(self, completed: int) -> None:
        now = time.monotonic()
        self._samples.append((now, completed))
        # Prune samples older than window
        while self._samples and now - self._samples[0][0] > self._window:
            self._samples.popleft()

    def devices_per_minute(self) -> float | None:
        if len(self._samples) < 2:
            return None
        (t0, c0), (t1, c1) = self._samples[0], self._samples[-1]
        elapsed = t1 - t0
        if elapsed < 30:                        # too little data
            return None
        return (c1 - c0) / elapsed * 60.0

    def eta(self, remaining: int) -> datetime | None:
        rate = self.devices_per_minute()
        if not rate or rate <= 0:
            return None
        seconds_left = remaining / (rate / 60.0)
        return datetime.now() + timedelta(seconds=seconds_left)
```

Don't show ETA before you have ≥3 completions AND ≥30s of history — early estimates are catastrophically wrong.

**Anti-pattern:** Single-shot ETA calculated once at start. Real deployments have phases (fast devices first, slow ones at the end). Rolling window tracks reality.

## Pattern 3: Error Triage Panel (Non-Blocking, Classified)

**Seen in:** Buildkite failed step sidebar, Kubernetes Lens pod error pane, Intune bulk enrollment troubleshoot page

When a device fails, don't halt the deployment. Don't pop a modal. Instead: add to a right-side `QDockWidget` showing a scrollable list of failed devices, each with:

- Device identifier
- **Classified error** (one of: Network / Auth / Config / Timeout / Hardware) — NOT a raw traceback
- Last 5-10 log lines
- Per-device `[Retry]` button
- Header-level `[Retry All Failed]` button

Classify errors at the deploy-engine level, not the UI:

```python
def classify_error(exc: Exception) -> str:
    if isinstance(exc, (ConnectionError, socket.timeout)):
        return "Network"
    if isinstance(exc, AuthenticationError):
        return "Auth"
    if isinstance(exc, (TimeoutError, requests.Timeout)):
        return "Timeout"
    if isinstance(exc, ConfigValidationError):
        return "Config"
    return "Unknown"
```

**Anti-pattern:** Halting the deploy on first failure. Parallel commissioning assumes some devices will fail; the operator must be able to triage without stopping the other 119.

**Anti-pattern:** Showing raw Python tracebacks to the tech. They're electricians, not Python devs. Classification → action ("retry" / "skip" / "investigate") beats stack trace every time.

## Pattern 4: Persistent Worklist State (Atomic, Resumable)

**Seen in:** Ansible Tower job history, GitHub Actions workflow runs, Intune device provisioning log, MDM platforms

Commissioning 120 devices takes multiple hours, possibly across shift changes. If the app crashes at device 87, you need to resume at 88, not restart. Persist state after every single transition:

```python
def mark_device(self, device_id: str, status: str, **metadata):
    self._devices[device_id].status = status
    self._devices[device_id].metadata.update(metadata)
    self._devices[device_id].updated_at = datetime.now().isoformat()
    self._persist_atomic()

def _persist_atomic(self):
    """Write to temp file, then rename — never leaves half-written JSON."""
    path = self._persist_path
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(self._worklist.model_dump_json(indent=2), encoding="utf-8")
    tmp.replace(path)                           # atomic on POSIX and Windows ≥ Vista
```

On app start:

```python
def load_or_new(path: Path) -> WorkList:
    if path.exists():
        wl = WorkList.model_validate_json(path.read_text(encoding="utf-8"))
        # Reset any "running" devices back to "queued" — they were in-flight when we crashed
        for dev in wl.devices:
            if dev.status == "running":
                dev.status = "queued"
                dev.attempt_count += 1
        return wl
    return WorkList.new()
```

Critical details:

- **Atomic write** (temp + rename) prevents corruption on crash mid-write
- **JSON, not CSV** — CSV parsing across app versions is fragile
- Persist on every transition, not batched — the 10ms cost is cheaper than losing 2 hours of work
- Reset "running" to "queued" on load — assume anything mid-flight at crash time is uncertain

**Anti-pattern:** Writing on a timer (every 30s). If you crash 29s in, you lose 29s of state. Write on every state change.

**Anti-pattern:** Pickling the worklist. Pickle doesn't survive Python version upgrades or code refactors. Always use a documented, stable text format.

## Pattern 5: Physical-to-Logical Device Identification (LED Locate)

**Seen in:** Ubiquiti UniFi Controller, Cisco switches (locate CLI command), APC NetBotz sensor pods

120 PDUs in a rack look identical. When a device fails, the tech needs to find the physical one. Every device control API with an LED should expose a "locate" command; the UI should expose it per-device:

```python
class DeviceRow(QWidget):
    def _on_locate_clicked(self):
        client = ApiClient(host=self._device.ip)
        try:
            client.blink_led(port=1, duration_seconds=30)
            self.show_toast(f"Blinking port-1 LED on {self._device.hostname} for 30s")
        except Exception as e:
            self.show_error(f"Could not trigger LED: {e}")
        finally:
            client.close()

        # After a delay, ask the tech to confirm
        QTimer.singleShot(30_000, lambda: self._ask_located())

    def _ask_located(self):
        reply = QMessageBox.question(self, "Locate",
            f"Did you see {self._device.hostname} blink?",
            QMessageBox.Yes | QMessageBox.No | QMessageBox.Retry)
        if reply == QMessageBox.Yes:
            self._device.physical_confirmed = True
```

**Anti-pattern:** LED blink without confirmation loop. The tech may have missed it, or it's the wrong device — ask.

**Anti-pattern:** Too-fast or too-slow blink. 1 Hz for 30s is the sweet spot — human-perceivable, not annoying, long enough to get to the rack.

**Anti-pattern:** Locating without physical context. Print a static rack-position label on device stickers or show a diagram — "port 1 LED" means nothing if the tech doesn't know which port is 1.

## Pattern 6: Compact Grid Heatmap (Spot Patterns, Not Just Individuals)

**Seen in:** Kubernetes Lens pod grid, Buildkite matrix view, GitHub Actions matrix, APC NetBotz sensor heatmap

A scrollable table of 120 devices is useful for "find PDU-045". A **12 × 10 colored grid** is useful for "are all devices in Rack A failing?" Both have their place — offer the grid as an alternative view.

Each cell = one device, ~60×60px, color = status, hover shows IP/progress, click opens detail. Layout order: by rack/hostname, not by status (so geographic patterns emerge).

```python
class DeviceHeatmapWidget(QWidget):
    CELL_SIZE = 60
    COLS = 12

    def paintEvent(self, event):
        painter = QPainter(self)
        for i, device in enumerate(self._devices):
            col, row = i % self.COLS, i // self.COLS
            rect = QRect(col * self.CELL_SIZE, row * self.CELL_SIZE,
                         self.CELL_SIZE - 2, self.CELL_SIZE - 2)
            painter.fillRect(rect, self._color_for(device.status))
            painter.drawText(rect, Qt.AlignCenter, str(device.index + 1))

    def mousePressEvent(self, event):
        col = event.x() // self.CELL_SIZE
        row = event.y() // self.CELL_SIZE
        idx = row * self.COLS + col
        if 0 <= idx < len(self._devices):
            self.device_clicked.emit(self._devices[idx])
```

**Anti-pattern:** Cells too small to read device labels. 60×60 px minimum with 10pt font.

**Anti-pattern:** Color-only status. Include a shape/glyph (✓, X, ⧗) for colorblind users and screenshots.

**Anti-pattern:** Replacing the table view with the heatmap. Keep both — search/sort use cases need a table; pattern recognition uses cases need the grid.

## Pattern 7: Graceful Fallback Strategies Before Escalating to the User

**Seen in:** Ansible Tower retries, Buildkite exit-code-based retry, Intune MDM profile retry

Known failure modes have known recoveries. Encode them once; don't bounce every error to the tech:

| Failure | Auto-fallback |
|---|---|
| IP change command timed out | Poll new IP for 30s before declaring failure |
| HTTPS connection refused | Retry with HTTP |
| DNS lookup failed | Use IP directly, skip hostname |
| First auth fail | Retry with factory-default creds |
| Socket reset mid-transfer | Exponential backoff, retry up to 3× |

Only escalate to UI after all fallback strategies exhaust. Log every fallback attempt in the device's history so the tech can see "recovered via HTTP fallback" vs "hard failure."

```python
RECOVERY_STRATEGIES = {
    "https_connection_refused": ["retry_http"],
    "auth_timeout": ["retry_factory_creds", "retry_blank_creds"],
    "post_ip_change_unreachable": ["wait_30s_retry_new_ip", "retry_old_ip"],
}

def deploy_with_recovery(device, config):
    for attempt in range(3):
        try:
            return _deploy_once(device, config)
        except KnownError as e:
            strategies = RECOVERY_STRATEGIES.get(e.code, [])
            if not strategies:
                raise                            # no auto-recovery available
            device.history.append(f"fallback: {strategies[0]}")
            config = _apply_strategy(config, strategies[0])
    raise MaxRetriesExhausted(device.id)
```

**Anti-pattern:** Silently retrying without logging. If a fallback happened, the tech deserves to know (debugging tomorrow).

**Anti-pattern:** Infinite retries. Cap at 3 attempts per strategy; if all exhaust, escalate.

## Pattern 8: Searchable / Filterable Triage Sidebar

**Seen in:** Kubernetes K9s, Jenkins Blue Ocean task filter, Intune device list

120 devices = can't scroll-hunt. Give the tech a left sidebar with:

- Search box (device name / IP / MAC, fuzzy match, 300ms debounce)
- Status filter dropdown (All / Queued / Running / Failed / Complete)
- Group-by toggle (by rack, by subnet, by error class)
- Context menu per row: Retry, Skip, Locate, View Details

```python
class TriageSidebar(QDockWidget):
    def __init__(self):
        super().__init__("Devices")
        self._search = QLineEdit(placeholderText="Search device / IP / MAC...")
        self._filter = QComboBox()
        self._filter.addItems(["All", "Queued", "Running", "Failed", "Complete"])
        self._proxy = QSortFilterProxyModel()
        self._proxy.setSourceModel(DeviceListModel(...))

        self._search_timer = QTimer(singleShot=True)
        self._search_timer.timeout.connect(self._apply_search)
        self._search.textChanged.connect(lambda: self._search_timer.start(300))

    def _apply_search(self):
        self._proxy.setFilterWildcard(f"*{self._search.text()}*")
```

**Anti-pattern:** Case-sensitive search. Lowercase both sides.

**Anti-pattern:** Unfiltered count. Show "Filtered: 12/120" in the header so the tech knows they've filtered something out.

**Anti-pattern:** Rebuilding the underlying data on every keystroke. Use `QSortFilterProxyModel` — it filters an existing model efficiently.

## Pattern 9: Dry-Run Preview for Batch Actions

**Seen in:** Buildkite "Retry all failed jobs" confirmation, Kubernetes Lens bulk delete, Intune bulk actions

"Retry All Failed" is a trigger that affects many devices. Before committing, show a modal preview:

```
Retry 7 devices?
  • PDU-045  (10.0.1.45)  — Network error at 14:23
  • PDU-087  (10.0.1.87)  — Auth failed at 14:41
  • PDU-091  (10.0.1.91)  — Config mismatch at 14:55
  • ... (4 more)

[ ] Let me hand-pick instead      [ Cancel ]   [ Retry All 7 ]
```

The "hand-pick" option converts the list to checkboxes so the tech can retry a subset. Always required for any bulk action affecting >5 devices.

**Anti-pattern:** Raw "OK / Cancel" with no device list. The tech has no idea what they're about to do.

**Anti-pattern:** Listing 120 devices in a modal with no scroll. Cap the preview at 20 rows with "...and N more."

## Pattern 10: Sticky Status Header with Abort Button

**Seen in:** Buildkite build header, Jenkins Blue Ocean pipeline header, GitHub Actions workflow page, Ansible Tower job page, Intune enrollment page

A top bar that **never scrolls off**, always showing:

- Deployment name + timestamp
- Count summary with glyphs: `45/120 ✓ | 15 ⧗ | 5 ✗`
- Rolling ETA (Pattern 2): "14:32 (3.2/min)"
- `[Stop]` button — opens confirmation modal before calling `deploy_engine.abort()`

```python
class DeployHeader(QWidget):
    def __init__(self, deploy_engine: DeployEngine):
        super().__init__()
        layout = QHBoxLayout(self)
        self._name = QLabel(deploy_engine.name)
        self._summary = QLabel()
        self._eta = QLabel()
        self._stop = QPushButton("Stop Deployment")
        self._stop.clicked.connect(self._confirm_stop)
        layout.addWidget(self._name)
        layout.addStretch()
        layout.addWidget(self._summary)
        layout.addWidget(self._eta)
        layout.addWidget(self._stop)

        # Refresh every 500ms
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh)
        self._timer.start(500)

    def _refresh(self):
        s = self._engine.summary()
        self._summary.setText(f"{s.complete}/{s.total} ✓ | {s.running} ⧗ | {s.failed} ✗")
        eta = self._engine.eta()
        self._eta.setText(eta.strftime("%H:%M") if eta else "…")

    def _confirm_stop(self):
        reply = QMessageBox.question(self, "Stop deployment?",
            f"{self._engine.summary().running} devices are currently deploying. "
            "Stop now will leave them in an inconsistent state.",
            QMessageBox.Ok | QMessageBox.Cancel)
        if reply == QMessageBox.Ok:
            self._engine.abort()
```

**Anti-pattern:** `[Stop]` without confirmation. It's an irreversible action that can leave devices half-configured.

**Anti-pattern:** Hiding the count summary behind a tab. The whole point is constant visibility.

**Anti-pattern:** Running the refresh timer at 50ms (UI flicker) or 5s (too stale). 500ms is the human-visible sweet spot.

---

## Prioritization for a new tool

If starting from scratch, implement patterns in this order:

| Tier | Patterns | Reason |
|---|---|---|
| 1 (day-1) | 1, 4, 10 | Status grid, persistent state, header — the skeleton |
| 2 (week-1) | 3, 7 | Error triage, auto-fallback — essential resilience |
| 3 (month-1) | 2, 9 | Rolling ETA, batch confirmations — ergonomic polish |
| 4 (later) | 5, 6, 8 | Locate, heatmap, filter sidebar — scale to 100s of devices |

Patterns 1, 4, 10 together convert a "works" tool into a "shippable" tool. Everything else is refinement.

---

## Anti-pattern summary

From worst to least-bad (all seen in real vendor tools):

1. **Halting the whole deployment on first error** — kills multi-hour work for one bad device
2. **No persistent state** — crashes force full restart
3. **Raw tracebacks in the UI** — useless to non-dev techs
4. **Modal dialogs during deploy** — freezes the UI, tech can't monitor
5. **No ETA / throughput** — "is this ever going to finish?"
6. **LED identify without software integration** — forces separate vendor CLI
7. **Flat error list, no grouping** — tech scrolls through 120 items looking for 7 failures
8. **Manual worklist rebuild for resume** — makes re-running effectively "do it again"
9. **No preview for bulk actions** — accidental "Retry All" disasters
10. **Overly small grid cells or unsortable tables** — forces endless scrolling

---

## Sources

- Ansible Tower: [Job output & host events](https://docs.ansible.com/ansible-tower/3.2.2/html/userguide/jobs.html)
- Buildkite: [Dashboard walkthrough](https://buildkite.com/docs/pipelines/dashboard-walkthrough), [Retry failed jobs](https://buildkite.com/resources/releases/2023-12/retry-all-failed-jobs/)
- Jenkins Blue Ocean: [Pipeline run details](https://www.jenkins.io/doc/book/blueocean/pipeline-run-details/)
- GitHub Actions: [Matrix strategy docs](https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow)
- Kubernetes Lens: [Spacelift overview](https://spacelift.io/blog/lens-kubernetes)
- Kubernetes K9s: [k9scli.io](https://k9scli.io/)
- Microsoft Intune: [Bulk enrollment](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-bulk-enroll)
- Ubiquiti UniFi: [Device LED indicators](https://help.ui.com/hc/en-us/articles/204910134-Understanding-Device-LED-Status-Indicators)
