---
name: network-device-discovery
description: Python network device discovery, scanning, and HTTP API management. Covers raw UDP sockets, vendor broadcast protocols (GBL reference), subnet scanning, HTTPS fallback, interface enumeration, and parallel probing. Built from production deployment to 120+ devices.
filePattern:
  - "**/discovery*.py"
  - "**/network*.py"
  - "**/api_client*.py"
  - "**/scan*.py"
bashPattern:
  - "ping"
  - "ipconfig"
  - "ifconfig"
  - "netsh"
  - "arp"
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

# Network Device Discovery Skill

Production-tested patterns for discovering, scanning, and managing network devices over HTTP/HTTPS.
Extracted from GUDE Deploy — a commissioning tool for 120+ rack-mounted PDU devices.

---

## Section 1: Interface Enumeration

### Rule 1: netifaces2 leaks memory on Windows — parse ipconfig instead

The netifaces2 C extension calls `GetAdaptersAddresses` on Windows and leaks unboundedly
(8-22 GB) on machines with AMD GPUs + multiple virtual adapters. It never returns.

**Fix:** Use `subprocess.run(["ipconfig", "/all"])` parsing on Windows. Keep netifaces2 for Linux/macOS.

```python
import platform

def get_network_interfaces() -> list[NetworkInterface]:
    if platform.system() == "Windows":
        return _parse_ipconfig()       # subprocess, no C extension
    else:
        try:
            return _get_interfaces_netifaces()
        except ImportError:
            return _fallback_socket()   # socket.gethostbyname
```

### Rule 2: Adapters can have multiple IPv4 addresses

Windows adapters with temp aliases (cross-subnet scanning) or dual DHCP+static emit
multiple "IPv4 Address" lines under the same adapter header. Emit one `NetworkInterface`
per IP+mask pair.

```python
def _parse_ipconfig() -> list[NetworkInterface]:
    # ...
    for line in output.splitlines():
        if "IPv4 Address" in stripped or "IP Address" in stripped:
            # Emit previous IP+mask before starting a new one
            _emit(current_name, current_ip, current_mask)
            current_ip = ""
            current_mask = ""
            parts = stripped.split(":", 1)
            if len(parts) == 2:
                current_ip = parts[1].strip().split("(")[0].strip()
        elif "Subnet Mask" in stripped:
            parts = stripped.split(":", 1)
            if len(parts) == 2:
                current_mask = parts[1].strip()
```

### Rule 3: Use encoding="utf-8-sig" for BOM handling

Windows command output and Excel-generated CSVs may have a UTF-8 BOM. Always
open with `encoding="utf-8-sig"` to strip it transparently. This applies to
`ipconfig /all` output, CSV worklists, and any file that might originate from Windows.

### Rule 4: Filter loopback, APIPA, and virtual adapters

Always exclude before presenting to users or scanning:
- Loopback: `127.x.x.x`
- APIPA: `169.254.x.x` (link-local, no real network)
- Virtual: Hyper-V, Tailscale, WSL, VPN adapters (context-dependent)

```python
DISCOVERY_APIPA_NETWORK = "169.254.0.0/16"

def is_apipa_interface(interface: NetworkInterface) -> bool:
    ip = ipaddress.IPv4Address(interface.ip_address)
    return ip in ipaddress.IPv4Network(DISCOVERY_APIPA_NETWORK)
```

### Rule 5: Sort interfaces by preference

Ethernet-like interfaces (eth*, en*) are preferred over Wi-Fi, VPN, or virtual adapters
for device discovery. Sort before presenting in UI or auto-selecting.

```python
def sort_key(iface: NetworkInterface) -> int:
    name = iface.name.lower()
    if name.startswith(("eth", "en")):
        return 0
    if "ethernet" in name:
        return 1
    return 2

non_loopback.sort(key=sort_key)
```

---

## Section 2: Subnet Scanning

### Rule 6: Support /23 and /22 subnets — don't hardcode /24

Production networks use larger subnets. Set `HTTP_SCAN_MAX_HOSTS = 1022` to support up
to /22. Always compute from CIDR, never assume 254 hosts.

```python
HTTP_SCAN_MAX_HOSTS = 1022  # /22 = 1022, /23 = 510, /24 = 254

network = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False)
num_hosts = network.num_addresses - 2  # exclude network + broadcast
if num_hosts > HTTP_SCAN_MAX_HOSTS:
    log.warning(f"Subnet {network} too large ({num_hosts} hosts), skipping")
    return []
ips = [str(ip) for ip in network.hosts()]
```

### Rule 7: Use ThreadPoolExecutor with 50 workers for parallel probing

50 workers is the sweet spot for HTTP probing a /24 subnet. Below 30 is slow,
above 80 risks socket exhaustion on Windows.

```python
HTTP_SCAN_WORKERS = 50

with ThreadPoolExecutor(max_workers=HTTP_SCAN_WORKERS) as executor:
    future_to_ip = {
        executor.submit(_probe_ip, ip, timeout): ip for ip in ips
    }
    for future in as_completed(future_to_ip):
        device = future.result()
        if device is not None:
            devices.append(device)
```

### Rule 8: Use 0.5s timeout for probing, 5s for health checks

Discovery probes dead IPs — most won't respond. Keep probe timeout aggressive (0.5s).
Health checks talk to known-alive devices over potentially routed networks — use 5s.

```python
HTTP_SCAN_TIMEOUT = 0.5    # per-IP probe during discovery
DEFAULT_HTTP_TIMEOUT = 10.0  # general API calls
# Health check overrides to 5.0s temporarily
```

### Rule 9: Interface isolation — scan only the selected NIC's subnet

When user selects a specific interface, only scan that interface's subnet + user-supplied
extra ranges. Factory default ranges (192.168.0.0/24, 192.168.1.0/24) are only included
when scanning "all interfaces". The factory default IP probe (192.168.0.2) always runs.

```python
specific_interface = interface is not None
all_ranges: list[str] = []

if not specific_interface:
    all_ranges.extend(DISCOVERY_SCAN_RANGES)  # factory defaults

# Always add the selected interface's subnet
for iface in interfaces:
    if is_apipa_interface(iface):
        continue
    iface_cidr = str(ipaddress.IPv4Network(
        f"{iface.ip_address}/{iface.netmask}", strict=False
    ))
    if iface_cidr not in all_ranges:
        all_ranges.append(iface_cidr)
```

### Rule 10: Skip factory default ranges when specific interface selected

If a tech selects "Ethernet (172.26.46.1)", they don't want to scan 192.168.0.0/24.
Only add factory defaults when scanning all interfaces.

---

## Section 3: Device Discovery Strategies

### Rule 11: Multi-strategy discovery — run GBL + HTTP + manual in parallel

Never rely on a single method. GBL broadcast finds factory-default devices, HTTP scan
finds configured devices, manual connect handles known IPs. Run all in parallel with
`ThreadPoolExecutor` and deduplicate by IP.

```python
def discover_all(interface=None, on_log=None, cancel_check=None, extra_ranges=None):
    all_devices: dict[str, GudeDevice] = {}  # keyed by IP for dedup
    max_workers = min(8, 2 + len(all_ranges) + len(interfaces))

    with ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="discovery") as executor:
        futures = {}

        # Strategy 1: GBL broadcast per interface
        for iface in interfaces:
            futures[executor.submit(discover_gbl, interface=iface, ...)] = f"GBL on {iface.display_name}"

        # Strategy 2: Factory default IP probe
        futures[executor.submit(_probe_ip, "192.168.0.2", timeout)] = "Factory default"

        # Strategy 3: Subnet range scans
        for cidr in all_ranges:
            futures[executor.submit(probe_fixed_range, cidr, ...)] = f"Range {cidr}"

        for future in as_completed(futures):
            result = future.result()
            # Deduplicate by IP
            if isinstance(result, list):
                for device in result:
                    if device.ip_address not in all_devices:
                        all_devices[device.ip_address] = device
            elif result is not None:
                if result.ip_address not in all_devices:
                    all_devices[result.ip_address] = result

    return list(all_devices.values())
```

### Rule 12: Raw UDP sockets for broadcast — no Scapy/Npcap dependency

Scapy and Npcap are heavy, fragile dependencies. Raw UDP sockets work on all platforms
for broadcast discovery protocols. Send to the subnet's broadcast address on the
protocol port.

```python
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(timeout)
    sock.sendto(GBL_HEADER, (broadcast_addr, GBL_PORT))

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = max(0.1, deadline - time.monotonic())
        sock.settimeout(remaining)
        data, addr = sock.recvfrom(4096)
```

### Rule 13: Bind UDP socket to specific interface IP for isolation

Without binding, broadcast goes out all interfaces. Bind to the selected interface's
IP so the broadcast stays on the correct network segment.

```python
if interface and interface.ip_address:
    try:
        sock.bind((interface.ip_address, 0))
    except OSError as e:
        log.warning(f"Could not bind to {interface.ip_address}: {e}")
```

### Rule 14: HTTPS fallback — HTTP first, TCP check, then HTTPS

Some devices are HTTPS-only (port 80 closed, 443 open). Don't commit to full TLS+HTTP
overhead on dead hosts. Quick TCP connect test on port 443 first.

```python
def _probe_ip(ip: str, timeout: float = 0.5) -> Device | None:
    # Try HTTP first
    try:
        resp = requests.get(f"http://{ip}/status", timeout=timeout)
        return parse_response(resp)
    except requests.Timeout:
        return None  # no host — skip HTTPS too
    except requests.ConnectionError:
        pass  # port 80 refused — try 443

    # Quick TCP check before expensive HTTPS
    try:
        with socket.create_connection((ip, 443), timeout=0.5):
            pass
    except (OSError, socket.timeout):
        return None  # port 443 also closed

    # Now try HTTPS (worth the overhead)
    try:
        resp = requests.get(f"https://{ip}/status", timeout=5.0, verify=False)
        return parse_response(resp)
    except (requests.ConnectionError, requests.Timeout):
        return None
```

### Rule 15: Deduplicate results by IP across all strategies

A device found by both GBL and HTTP scan should appear once. Key by IP address,
not MAC (some discovery methods don't return MAC).

```python
all_devices: dict[str, Device] = {}  # keyed by IP
for device in results:
    if device.ip_address not in all_devices:
        all_devices[device.ip_address] = device
```

### Rule 16: Separate quick probe from full info fetch

Discovery probes thousands of IPs — keep it minimal (one lightweight request).
After discovery, enrich each found device with a detailed API call. This separates
the "is anything there?" check from "what exactly is it?".

```python
def enrich_device(device: Device, client: ApiClient | None = None) -> Device:
    own_client = False
    if client is None:
        client = ApiClient(host=device.ip_address, use_ssl=device.use_ssl)
        own_client = True
    try:
        _populate_device_info(device, client)
    finally:
        if own_client:
            client.close()
    return device
```

---

## Section 4: HTTP API Client Patterns

### Rule 17: One requests.Session per client — NOT shared across threads

`requests.Session` is not thread-safe. Each `ApiClient` instance creates its own session.
In parallel operations, each worker thread creates and closes its own client.

```python
class ApiClient:
    def __init__(self, host, port=80, use_ssl=False, ...):
        self._session = requests.Session()
        if use_ssl:
            self._session.verify = False
        if username:
            self._session.auth = (username, password)
```

### Rule 18: Close sessions in finally blocks

Leaked sessions exhaust connection pools. Use context managers or explicit finally.

```python
# Option 1: Context manager
with ApiClient(host=ip) as client:
    client.health_check()

# Option 2: Explicit finally (for enrichment patterns)
own_client = False
if client is None:
    client = ApiClient(host=device.ip_address, use_ssl=device.use_ssl)
    own_client = True
try:
    _populate_device_info(device, client)
finally:
    if own_client:
        client.close()
```

### Rule 19: Disable SSL verification for self-signed certs

Network devices use self-signed certificates. Set `verify=False` on the session,
not per-request, to avoid missing it on one call.

```python
self._session.verify = False
```

### Rule 20: Suppress urllib3 InsecureRequestWarning globally

Without suppression, every HTTPS request to a self-signed device prints a warning.
Do this once at module level, not per-request.

```python
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
```

### Rule 21: Health check with 5s timeout, not 2s

Routed networks and VPN tunnels add latency. 2s is too aggressive for health checks.
Temporarily override the client timeout for health checks.

```python
def health_check(self, timeout: float = 5.0) -> bool:
    saved_timeout = self.timeout
    self.timeout = timeout
    try:
        self._get_json("statusjsn.js", {"components": STATUS_HEALTH_CHECK})
        return True
    except (ConnectionError, AuthenticationError, ConfigLoadError):
        return False
    finally:
        self.timeout = saved_timeout
```

### Rule 22: Handle 401 gracefully — devices may ship with no auth

Many network devices ship with auth disabled. When you get a 401, raise a specific
`AuthenticationError` so the UI can prompt for credentials, not show a generic failure.

```python
if resp.status_code == 401:
    raise AuthenticationError(url=url)
```

### Rule 23: GET-based command API — params via requests library

Many device APIs use GET with query params for commands (e.g. `ov.html?cmd=4&ip=x`).
Let the `requests` library encode params — don't manually build query strings.

```python
def send_command(self, cmd: int, params: dict | None = None) -> str:
    all_params = {"cmd": cmd}
    if params:
        all_params.update(params)
    resp = self._get("ov.html", all_params)  # requests encodes safely
```

---

## Section 5: Connection Monitoring

### Rule 24: Poll at 10s intervals, not 5s

5s polling creates unnecessary load on devices with limited HTTP stacks. 10s is
sufficient for connection monitoring during commissioning workflows.

```python
CONNECTION_CHECK_INTERVAL = 10000  # milliseconds
```

### Rule 25: Failure threshold before marking connection lost

Transient network hiccups cause single health check failures. Require 3 consecutive
failures before declaring the connection lost.

```python
CONNECTION_FAILURE_THRESHOLD = 3

# In the monitor:
if health_check_failed:
    self._consecutive_failures += 1
    if self._consecutive_failures >= CONNECTION_FAILURE_THRESHOLD:
        self._emit_connection_lost()
else:
    self._consecutive_failures = 0
    if was_disconnected:
        self._emit_connection_restored()
```

### Rule 26: Auto-recover on next successful check

Don't require user intervention to reconnect. If a health check succeeds after
failures, automatically restore the connection state.

### Rule 27: Stop monitoring during deploy operations

Health check polls interfere with deploy operations (especially IP changes).
Pause the monitor before deploy, resume after.

---

## Section 6: Parallel Operations

### Rule 28: Each worker creates its own ApiClient and closes it in finally

Never share `ApiClient` or `requests.Session` across threads. Create, use, close
within each worker function.

```python
def _deploy_one_device(device, config):
    client = ApiClient(host=device.ip_address, use_ssl=device.use_ssl)
    try:
        client.configure_ipv4(**config)
        return True
    except Exception as e:
        log.error(f"Deploy failed for {device.ip_address}: {e}")
        return False
    finally:
        client.close()
```

### Rule 29: Stagger parallel operations (3s between firmware uploads)

Simultaneous firmware uploads to 120 devices on the same switch causes packet loss.
Stagger with a small delay between submissions.

```python
BATCH_FIRMWARE_STAGGER = 3.0  # seconds between upload starts

for i, device in enumerate(devices):
    if i > 0:
        time.sleep(BATCH_FIRMWARE_STAGGER)
    future = executor.submit(upload_firmware, device, firmware_data)
    futures[future] = device
```

### Rule 30: Progress callbacks from as_completed(), never from pool threads

UI callbacks (Qt signals, tkinter `after()`) must run on the main thread.
Collect results via `as_completed()` on the main thread, then emit progress.

```python
for future in as_completed(futures):
    device = futures[future]
    try:
        result = future.result()
        on_progress(device, "success")  # main thread — safe for UI
    except Exception as e:
        on_progress(device, f"failed: {e}")
```

### Rule 31: Stabilization sleep after firmware reboot

After firmware upload + reboot command, the device takes 30-90 seconds to come back.
Wait before attempting config deployment or health checks.

```python
FIRMWARE_REBOOT_INITIAL_SLEEP = 30  # seconds before first reconnect attempt
FIRMWARE_REBOOT_WAIT = 120.0        # total timeout for device to come back
```

---

## Section 7: IP Management

### Rule 32: IPv4 config ALWAYS deployed last

Changing a device's IP disconnects it immediately. Deploy all other config (hostname,
SNMP, syslog, etc.) first, then change IP as the final step.

```python
DEPLOY_ORDER = [
    "http",
    "snmp",
    "email",
    "syslog",
    "ipacl",
    "inputs",
    "ports",
    "ipv4",  # ALWAYS LAST — IP change disconnects
]
```

### Rule 33: Track old_ip and new_ip through deploy

When deploying IP changes, you need both addresses: old_ip for sending the command,
new_ip for post-deploy verification. Store both in the deploy context.

### Rule 34: Post-deploy verification on the NEW IP

After an IP change, health-check the NEW address, not the discovery address.
The device is no longer reachable at the old IP.

```python
# After IP change command sent to old_ip:
new_client = ApiClient(host=new_ip, use_ssl=device.use_ssl)
try:
    if new_client.health_check(timeout=10.0):
        log.info(f"Device verified at new IP {new_ip}")
finally:
    new_client.close()
```

### Rule 35: Factory default IP conflict

If all devices ship with the same factory IP (e.g. 192.168.0.2), you cannot
mass-discover them simultaneously. Commission one at a time: discover, change IP,
verify at new IP, then discover the next device on the factory IP.

---

## Section 8: CSV/Worklist Patterns

### Rule 36: Validate CSV strictly — RFC 1123 hostnames, valid IPs, no dupes

Catch errors at load time, not deploy time. Validate every row.

```python
_HOSTNAME_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$")

# In the CSV loader:
if not _HOSTNAME_RE.match(hostname):
    raise WorkListError(f"Row {row_num}: invalid hostname '{hostname}'")
if not is_valid_ip(ip):
    raise WorkListError(f"Row {row_num}: invalid IP '{ip}'")

addr = ipaddress.IPv4Address(ip)
if addr.is_loopback:
    raise WorkListError(f"Row {row_num}: loopback IP not allowed")
if addr.is_multicast:
    raise WorkListError(f"Row {row_num}: multicast IP not allowed")

if hostname.lower() in seen_hostnames:
    raise WorkListError(f"Row {row_num}: duplicate hostname '{hostname}'")
if ip in seen_ips:
    raise WorkListError(f"Row {row_num}: duplicate IP '{ip}'")
```

### Rule 37: UTF-8 BOM handling for Excel CSVs

Excel saves CSV with a UTF-8 BOM (`\xef\xbb\xbf`). Using `encoding="utf-8-sig"`
strips it transparently. Without it, the first column header gets a invisible prefix
and `"hostname" not in normalized` fails silently.

```python
with open(filepath, encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
```

### Rule 38: Strip whitespace from all CSV values

PMs paste from spreadsheets. Trailing spaces in hostnames and IPs cause deploy failures
that are invisible in logs. Strip everything.

```python
hostname = (row.get(hostname_col) or "").strip()
ip = (row.get(ip_col) or "").strip()
```

### Rule 39: Netmask/gateway as optional columns

When present, they force static IP config (DHCP off). When absent, only hostname
and IP are set. This lets the same CSV format work for both DHCP and static deployments.

```python
class WorkListItem(BaseModel):
    hostname: str
    ip: str
    netmask: str = ""    # Optional — force static if provided
    gateway: str = ""    # Optional — force static if provided
```

### Rule 40: Persist worklist state to disk

Commissioning 120 devices takes hours across shift changes. If the app crashes at
device 87, you need to resume from 88, not restart. Persist after every status change.

```python
def persist(self) -> None:
    persist_path = Path(WORKLIST_PERSIST_FILE).expanduser()
    persist_path.parent.mkdir(parents=True, exist_ok=True)
    persist_path.write_text(
        self._worklist.model_dump_json(indent=2),
        encoding="utf-8",
    )

def mark_deployed(self, index: int, mac: str, session_id: str) -> None:
    item = self._worklist.items[index]
    item.status = "deployed"
    item.deployed_at = datetime.now().isoformat()
    item.mac_address = mac
    item.session_id = session_id
    self.persist()  # immediate write — crash-safe
```

---

## Section 9: Vendor UDP Broadcast Protocols (reference: GBL)

These rules generalize from GUDE's GBL protocol (reverse-engineered from GBL_Conf.exe v2.7.13 binary in April 2026). Apply the same patterns to any vendor discovery broadcast: ALP, Lantronix DeviceInstaller, WS-Discovery, etc.

### Rule 41: Send ALL protocol versions the vendor's tool sends — old firmware only answers old versions

Vendors iterate protocol versions without retiring old ones. Their own discovery tool sends both v3 and v4 packets on every scan because older or misconfigured devices only answer v3. If you send only the newest version, you'll miss those devices.

```python
GBL_PORT = 50123                    # UDP, both request and response
GBL_MAGIC = b"GBL"                  # 3-byte magic
GBL_REQUEST_V3 = GBL_MAGIC + b"\x03"  # 4 bytes: GBL\x03
GBL_REQUEST_V4 = GBL_MAGIC + b"\x04"  # 4 bytes: GBL\x04

def discover_gbl(interface: NetworkInterface, timeout: float = 1.5):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind((interface.ip_address, 0))
        # Send BOTH versions — do not skip v3 "because v4 is newer"
        sock.sendto(GBL_REQUEST_V3, (broadcast_addr, GBL_PORT))
        sock.sendto(GBL_REQUEST_V4, (broadcast_addr, GBL_PORT))
        # ... then collect responses
```

Gotcha: log strings in the vendor's binary like `"broadcasting GBL1 v3"` are human-readable log output, NOT packet bytes. Do not send the literal `"GBL1"` string — send `GBL\x03` / `GBL\x04` as 4-byte packets.

### Rule 42: Single broadcast + blocking receive loop, not a retry loop

The intuition "send 3 times, 3 seconds apart" is wrong for UDP broadcast discovery. Vendor tools do **one** broadcast and then sit in a blocking receive loop for ~1000ms collecting responses. This is fast, doesn't flood the NIC, and works because every device answers immediately on receipt.

```python
def discover_gbl(interface, timeout_ms: int = 1500):
    results = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind((interface.ip_address, 0))
        sock.sendto(GBL_REQUEST_V3, (broadcast_addr, GBL_PORT))
        sock.sendto(GBL_REQUEST_V4, (broadcast_addr, GBL_PORT))

        deadline = time.monotonic() + (timeout_ms / 1000.0)
        while time.monotonic() < deadline:
            remaining = max(0.05, deadline - time.monotonic())
            sock.settimeout(remaining)
            try:
                data, addr = sock.recvfrom(4096)
                device = _parse_gbl_response(data, addr)
                if device:
                    results.append(device)
            except socket.timeout:
                break  # no more responses coming in
    return results
```

Keep the per-iteration timeout ≥ 50ms so the loop doesn't busy-wait on `settimeout(0)`.

### Rule 43: Broadcast on each interface's directed broadcast address, not 255.255.255.255

`255.255.255.255` is the limited broadcast — the OS routes it out whichever interface it chooses, and on multi-homed machines (Ethernet + Wi-Fi + VPN) that's often the wrong one. Enumerate interfaces and broadcast on each interface's **directed broadcast address** (e.g. `172.26.46.255` for a /24 on `172.26.46.x`).

```python
def get_broadcast_address(interface: NetworkInterface) -> str:
    network = ipaddress.IPv4Network(
        f"{interface.ip_address}/{interface.netmask}", strict=False
    )
    return str(network.broadcast_address)

# Run one broadcast per non-loopback, non-APIPA interface
for iface in get_non_loopback_interfaces():
    if is_apipa_interface(iface):
        continue
    bcast = get_broadcast_address(iface)
    futures.append(pool.submit(discover_gbl, iface, bcast))
```

Binding the socket to the interface's source IP (Rule 13) ensures the reply comes back on the same NIC.

### Rule 44: `addr[0]` from recvfrom is the REPLY source, not always the device's IP

`socket.recvfrom()` returns `(data, (sender_ip, sender_port))`. On networks with NAT, 1:1 routing, or misconfigured devices, `sender_ip` can differ from the device's advertised IP inside the response payload. GUDE's protocol embeds the device's self-reported IP in the response body (bytes 10-13, big-endian).

**Rule:** trust the payload, but fall back to `addr[0]` if the payload IP is `0.0.0.0` or invalid.

```python
def _parse_gbl_response(data: bytes, addr: tuple) -> GudeDevice | None:
    if len(data) < 21 or data[:3] != GBL_MAGIC:
        return None
    # Response layout: GBL + ver(1) + mac(6) + ip(4) + mask(4) + gw(4) + hostname\0 + fw\0
    payload_ip = ".".join(str(b) for b in data[10:14])
    try:
        ip_obj = ipaddress.IPv4Address(payload_ip)
        if ip_obj.is_unspecified or ip_obj.is_loopback:
            payload_ip = addr[0]  # fallback to sender
    except ValueError:
        payload_ip = addr[0]
    return GudeDevice(ip_address=payload_ip, ...)
```

Without this fallback, misconfigured devices (factory-default 0.0.0.0, never commissioned) show up as unreachable despite responding to the broadcast.

### Rule 45: Ephemeral socket per scan > persistent listener

Vendor GUI tools often keep a `TIdUDPServer` / long-lived socket bound to the protocol port for the app lifetime. This is a GUI-state convenience, not a protocol requirement. Our pattern — open socket, broadcast, listen, close — is equivalent for a single discovery pass and avoids port conflicts when multiple instances of the tool run on the same host.

```python
# Each call opens its own socket on an ephemeral local port
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind((interface.ip_address, 0))  # port 0 = OS picks free port
    # ... broadcast + listen + close when `with` exits
```

Don't bind the LOCAL socket to the protocol port (50123) — that only matters if you want to listen for unsolicited device announcements. For active discovery, any ephemeral port works since the device replies to `(your_sender_ip, your_sender_port)`.

### Rule 46: Static-analyze the vendor's tool once, write constants down, never again

When reverse-engineering a closed protocol, static-analyzing the vendor binary for constants (port, magic bytes, timeouts) takes multiple agent rounds on a compiled Delphi/C++ binary with no symbols. Do it ONCE, write the constants into `constants.py` with source-of-truth comments, and document in a project memory file how to re-derive them if the vendor changes the protocol.

For the GBL protocol (GUDE), these were the load-bearing facts:
- Port 50123, confirmed via `mov cx, 0xCBC3` instruction pattern `66 b9 cb c3` at 6 code locations
- Timeout 1000ms, Delphi DFM-encoded `\x03\xe8\x03` = Int16 1000
- Packets: `GBL\x03` and `GBL\x04`, both sent every scan
- Response format decoded from TIdUDPServer.OnUDPRead handler

Re-verify when things break:
```bash
curl -sLO https://gude-systems.com/app/uploads/2021/04/gblconf_v2.7.13.zip
unzip gblconf_v2.7.13.zip
strings -el GBL_Conf.exe | grep -iE "(gbl1|broadcast|timeout)"
python3 -c "import re; d=open('GBL_Conf.exe','rb').read(); \
  print([hex(m.start()) for m in re.finditer(b'\\x66\\xb9\\xcb\\xc3', d)])"
```

### Rule 47: Pitfalls when reading vendor binaries

Don't confuse runtime protocol data with compiler metadata:

- Delphi **VCL button-type constants** (`BBRETRY`, `BBOK`, `BBCANCEL`) look like retry/timeout settings but are UI button identifiers. Don't tune broadcast retries from there.
- Registry key names like `BTPORT` often refer to serial/Bluetooth COM ports, not network ports.
- Byte patterns like `GBL\x03\x00\x00\x00\x00\x00\x0c\x00...` at specific binary offsets are usually **Delphi RTTI method tables**, not packet templates. Confirm any alleged "packet template" by finding where it's actually sent (`sendto`, `WSASend`, `Indy.Send`).

When in doubt, verify a constant appears at a `sendto`/`recvfrom` call site, not just as a string literal.

---

## Quick Reference: Timeouts

| Context | Timeout | Why |
|---|---|---|
| HTTP probe (discovery) | 0.5s | Most IPs are dead — fail fast |
| TCP port check (443) | 0.5s | Quick liveness test before HTTPS |
| HTTPS probe (discovery) | 5.0s | TLS handshake is slow |
| Health check | 5.0s | Routed networks have latency |
| General API calls | 10.0s | Config/status fetches |
| Firmware upload | 180.0s | Large binary POST |
| GBL broadcast wait | 3.0s | UDP responses are fast |
| Connection monitor interval | 10s | Avoid overloading device HTTP stack |
| Post-reboot initial sleep | 30s | Device boot time |
| Post-reboot total timeout | 120s | Slow devices, firmware flash |

## Quick Reference: Worker Counts

| Operation | Workers | Why |
|---|---|---|
| HTTP subnet scan | 50 | Sweet spot for /24, won't exhaust sockets |
| Ping sweep | 80 | Lightweight subprocess, higher parallelism OK |
| Batch firmware upload | 8 | Heavy POST, staggered 3s apart |
| Batch config deploy | 8 | Multiple GET commands per device |
| Discovery strategies | min(8, 2+ranges+ifaces) | One thread per strategy |

## Quick Reference: Python Discovery Libraries (2026)

For protocols we haven't implemented yet but might need. Verified against PyPI release cadence as of April 2026.

| Protocol | Library | Latest | Admin needed? | Windows OK? | License | Notes |
|---|---|---|---|---|---|---|
| mDNS / Bonjour | `zeroconf` 0.148+ | Oct 2025 | No | Yes (wheels fixed 0.147.2) | LGPL-2.1+ | Pure Python, actively maintained |
| SSDP / UPnP | `async-upnp-client` 0.46+ | Jan 2026 | No | Yes (explicit IPv6 scope ID support) | MIT | Home Assistant's choice; asyncio-native |
| WS-Discovery | `WSDiscovery` 2.1.2 | Jan 2025 | No | Yes | MIT | Revived in 2025 for ONVIF |
| SNMP v1/v2c/v3 | `pysnmp` | Sustainable | No (UDP 161 queries) | Yes | BSD | 151K weekly downloads; 50+ contributors |
| ICMP ping | `icmplib` 2.0+ | Active | **Yes on Windows** | Partial | MIT | `privileged=False` is silently ignored on Windows |
| ARP scan | `scapy` + Npcap | Active | **Yes (Npcap OEM)** | With Npcap | GPL (scapy) + Npcap OEM | Npcap OEM redistribution = paid license |
| ARP cache parse | `subprocess` + `arp -a` | N/A | No | Yes | - | Cache only, not active discovery |
| LLDP | `scapy` contrib | Active | **Yes (raw packets)** | With Npcap | GPL | Layer-2; rarely useful without admin |
| nmap wrapper | `python-nmap` | Active | Depends | With nmap | GPL / requires nmap binary | Redistribution needs OEM license (~$2K) |

**Avoid (deprecated or dead):**
- `easysnmp` — no PyPI releases in 12+ months; use `pysnmp`
- `ssdpy` (original `MoshiBin/ssdpy`) — inactive; prefer `async-upnp-client`

### Rule 41.5: License-check every discovery lib before adopting — Npcap/GPL can be commercial blockers

`scapy` is GPL. `python-nmap` requires the GPL nmap binary. Shipping either in a closed-source commercial tool means either:
- Release your own source as GPL (usually a non-starter), OR
- Buy an OEM license — Nmap OEM is ~$2000, Npcap OEM is a separate SKU.

`zeroconf`, `async-upnp-client`, `WSDiscovery`, `pysnmp`, `icmplib` are all LGPL/MIT/BSD — safe to bundle in a proprietary PyInstaller build. **Verify license BEFORE writing code against a library** — swapping out a discovery backend after the fact is painful.

### Rule 41.6: Admin-free first, elevation as optional upgrade

Most field techs won't (and shouldn't need to) run a commissioning tool as Administrator. Design the discovery stack so the default code path works without elevation:

1. **Default path (no admin):** UDP broadcast (GBL, mDNS, SSDP, WSD) + TCP probe sweep via `socket.create_connection` + HTTP(S) enrich
2. **Optional upgrade:** Offer a "Run as Administrator for extended discovery" button that enables raw ARP / ICMP ping sweep. Never require it.

Specifically, `icmplib`'s `privileged=False` parameter is **silently ignored on Windows** — the underlying `SOCK_RAW` API always needs admin. Don't rely on the library's docs claim; test the code path on a non-admin Windows account before shipping.

### Rule 41.7: Corporate firewalls often drop multicast — fall back to unicast probes gracefully

UDP multicast to `239.255.255.250` (SSDP), `224.0.0.251` (mDNS) and `239.255.255.250:3702` (WSD) is routinely filtered by corporate firewalls, managed switches without IGMP snooping, and many hypervisor virtual networks. If two full broadcast rounds return zero results:

1. Surface a "No devices found via broadcast — try manual IP range?" dialog
2. Fall back to TCP subnet scan on the same interfaces
3. Log the multicast failure so field diagnostics can spot it later

Don't silently treat "zero broadcast hits" as "no devices" — it's usually a firewall symptom.

---

## Quick Reference: Common OUI Prefixes

When filtering ARP tables for specific vendors:

```python
GUDE_OUI = "00:19:32"          # GUDE Systems GmbH
GUDE_OUI_DASH = "00-19-32"    # Windows ARP table uses dashes
```

Always normalize to lowercase colon-separated before comparison:
```python
mac = parts[1].strip().lower().replace("-", ":")
```
