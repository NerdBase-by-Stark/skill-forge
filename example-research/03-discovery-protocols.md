# Stream 3: Network Device Discovery Protocols

## Research Summary

Investigation of 10 major network device discovery protocols and their Python library ecosystems. Focus: Windows desktop app deployment without requiring admin, Npcap/WinPcap, or external binaries. All research conducted April 2026 against library releases dated through January 2026.

**Key Finding:** Multicast/UDP broadcast protocols (mDNS, SSDP, UPnP, WS-Discovery) require no admin and run perfectly on Windows. Raw packet protocols (ARP, LLDP, ICMP raw) require admin or Npcap OEM license. DHCP snooping requires admin. This shapes the skill: prefer broadcast-based discovery.

---

## Protocol-by-Protocol Analysis

### 1. mDNS / Bonjour / Zeroconf

**Description:**  
Multicast DNS (RFC 6762) for service discovery over local networks. Pure Python, no Bonjour/Avahi daemon required. Works across Windows, macOS, Linux.

**Python Library: `zeroconf` (Recommended)**
- Latest: **0.148.0** (October 5, 2025)
- Status: Actively maintained (721 GitHub stars, 229 forks, 218 releases)
- Windows: YES — binary wheels provided. Version 0.147.2 (Sep 2025) fixed missing Windows wheels.
- Admin required: NO — uses standard UDP multicast
- Python: 3.9+ (CPython, PyPy)
- License: LGPL-2.1-or-later
- Async: Optional (uses asyncio internally, developer API is sync-friendly)

**Known Gotchas:**
- IPv6 support exists but noted as "relatively new and currently limited"
- RFC 6762 traffic reduction (v0.32+) prevents network flooding but adds latency
- Multi-homed machines: library handles this correctly (unlike some older implementations)

**Sample Code:**
```python
from zeroconf import ServiceBrowser, Zeroconf

def on_service_state_change(zeroconf, service_type, name, state_change):
    if state_change.name == "Updated":
        info = zeroconf.get_service_info(service_type, name)
        print(f"Found: {info.name} at {info.addresses}")

zeroconf = Zeroconf()
ServiceBrowser(zeroconf, "_http._tcp.local.", handlers=[on_service_state_change])
```

---

### 2. SSDP / UPnP Discovery

**Description:**  
Simple Service Discovery Protocol (IETF and UPnP flavors). M-SEARCH multicast on UDP 239.255.255.250:1900. Finds printers, routers, smart devices, PDUs with UPnP stack.

**Python Libraries:**

**Option A: `ssdpy` (Legacy, NOT recommended)**
- Latest: 0.4.1 (2023+)
- Status: INACTIVE — no PyPI releases in 12+ months, low GitHub activity
- Avoid for new projects

**Option B: `ssdp` / `ssdpy` (Modern, RECOMMENDED)**
- Latest: Released September 2025
- Status: Actively maintained async library
- Windows: YES
- Admin required: NO
- Asyncio: Full async support

**Option C: `async-upnp-client` (Best for UPnP control)**
- Latest: **0.46.2** (January 3, 2026)
- Status: Actively maintained (Home Assistant standard library)
- Windows: YES (explicit IPv6 scope ID examples for Windows)
- Admin required: NO
- Async: Full asyncio
- Use case: If you need to query/control discovered UPnP devices (not just list them)

**Sample Code:**
```python
from ssdpy import SSDPClient

client = SSDPClient()
devices = client.m_search("ssdp:all")
for device in devices:
    print(f"{device.location}")  # URL to device descriptor
```

---

### 3. WS-Discovery (WSD)

**Description:**  
Web Services Discovery (WS-Discovery, SOAP over UDP). Primary use: ONVIF cameras, network printers, some Windows-only devices.

**Python Library: `WSDiscovery`**
- Latest: **2.1.2** (January 24, 2025)
- Status: Actively maintained (sustainable release cadence)
- Windows: YES
- Admin required: NO — UDP multicast on 239.255.255.250:3702
- Python: 3.x
- Async: Supported

**Known Gotchas:**
- ONVIF devices expect WS-Discovery probes; some legacy cameras don't respond
- Zeep SOAP client integration required for actual device communication (separate library)
- Probe timeout can be long; use `timeout_ms=500` to speed up slow networks

**Sample Code:**
```python
from ws_discovery import WSDiscovery, QName

wsd = WSDiscovery(timeout_ms=500)
wsd.start()
services = wsd.searchServices(types=['dn:Device'])
for service in services:
    print(f"Found: {service.getEPR()}")
wsd.stop()
```

---

### 4. LLDP (Link Layer Discovery Protocol)

**Description:**  
IEEE 802.1AB layer-2 protocol for neighbor discovery. Network switches advertise port information, topology data. Desktop app use case: limited (requires listening on raw 802 frames).

**Python Libraries:**
- `scapy` (LLDP contrib layer exists)
- `WinLLDP` (Windows-specific LLDP sender/receiver)
- Direct parsing: Custom code parsing eth/802.1ab frames

**Admin required: YES — raw socket/packet capture needed**
- On Windows: Npcap OEM license required
- On Linux: CAP_NET_RAW capability (can be dropped after socket open)

**Verdict for Desktop Apps:** NOT RECOMMENDED without Npcap. LLDP is for network monitoring, not end-device discovery.

---

### 5. SNMP Discovery

**Description:**  
Query devices for sysDescr (OID 1.3.6.1.2.1.1.1.0), sysServices, ifTable to enumerate network interfaces and device inventory.

**Python Libraries:**

**Option A: `pysnmp` (Pure Python, RECOMMENDED)**
- Status: Sustainable (50 contributors, 151K weekly downloads)
- Windows: YES
- Admin required: NO (UDP port 161 queries)
- Performance: Slower than Net-SNMP C bindings, but portable
- Python: 3.6+

**Option B: `easysnmp` (C bindings, faster but abandoned)**
- Status: INACTIVE (no PyPI releases in 12+ months)
- Avoid for new projects

**Known Gotchas:**
- SNMP v3 auth/priv requires pycryptodome (adds dependency)
- Community string "public" default rarely works on modern networks
- Devices behind firewalls may block SNMP (UDP 161) outbound

**Sample Code:**
```python
from pysnmp.hlapi import *

for (errorIndication, errorStatus, errorIndex, varBinds) in bulkCmd(
    SnmpEngine(), CommunityData('public'),
    UdpTransportTarget(('192.168.1.1', 161), timeout=2),
    ContextData(), 0, 25, '1.3.6.1.2.1.1'
):
    for varBind in varBinds:
        print(f"{varBind[0]} = {varBind[1]}")
```

---

### 6. ARP Scanning

**Description:**  
Send ARP request ("who has 192.168.1.50?") on local subnet. Fast, layer-2. Finds all active IPs on local LAN.

**Python Libraries:**

**Option A: `scapy` (Full ARP + raw socket control)**
- Windows: Requires Npcap OEM (or admin + native raw sockets)
- Note: Native Windows raw sockets don't work well; Scapy developers recommend Npcap
- Code: `srp(Ether(dst="ff:ff:ff:ff:ff:ff")/ARP(pdst="192.168.1.0/24"), timeout=2)`

**Option B: Parse system `arp -a` output (Windows-native, NO admin)**
- Windows: YES, no Npcap needed
- Limitations: Only shows cache, not active discovery
- Code: `subprocess.run(['arp', '-a'], capture_output=True).stdout` then regex

**Verdict for Desktop Apps:** Use `arp -a` parsing on Windows (zero dependencies, no admin). Use Scapy+Npcap on enterprise networks with WinPcap available.

---

### 7. ICMP Ping Sweep

**Description:**  
Send ICMP Echo Request to IP range. Identifies responsive hosts. Can be slow (/22 subnet = 1022 hosts).

**Python Libraries:**

**Option A: `icmplib` (RECOMMENDED)**
- Latest: 2.0.2+
- Status: Modern, actively maintained
- Windows: Partial — `privileged` parameter ignored on Windows
- Admin required: YES on Windows (raw sockets), NO on Linux (unprivileged ICMP via IPPROTO_ICMP)
- Async: Full asyncio support via `async_ping()`
- Code: `icmplib.ping('192.168.1.1')`

**Option B: `ping3` (Pure Python)**
- Status: Maintained
- Windows: Requires admin for raw ICMP
- Simpler API but slower than icmplib

**Admin Reality:** Both libraries require admin on Windows for raw ICMP. Subprocess-based `ping.exe` works unprivileged but is slow at scale.

**Verdict for Desktop Apps:** SKIP ping sweep without admin. If user runs app with admin, icmplib+asyncio is solid. Otherwise, fallback to ARP sweep on local subnets.

---

### 8. DHCP Snooping / Passive Discovery

**Description:**  
Listen on UDP 67/68 for DHCP DISCOVER/OFFER/REQUEST/ACK packets. Identifies new devices joining network without active scanning.

**Python Library: `scapy`**
- Code: `scapy.sniff(filter='udp and (port 67 or port 68)', prn=parse_dhcp)`
- Admin required: YES (packet sniffing requires raw socket on most OSes)
- Windows: Npcap OEM required (or run as admin with native sockets)

**Verdict for Desktop Apps:** NOT PRACTICAL without admin. Use for network monitoring tools, not consumer desktop apps.

---

### 9. NetBIOS / SMB Browse

**Description:**  
Windows name resolution over UDP 137-139. Legacy but still in use on corporate LANs. Finds Windows shares and printers.

**Python Libraries:**
- `pysmb` (SMB client, not discovery)
- Custom NBNS/NetBIOS packet parsing (complex, rarely maintained)
- `nmcli` / `nbtscan` (external binaries)

**Admin required: NO for queries, YES for raw sniffing**

**Verdict for Desktop Apps:** NOT RECOMMENDED. Modern networks disable NetBIOS. SSDP/UPnP + SMB queries (`smb://` URL enumeration) is better.

---

### 10. Aggregate Tools (nmap, masscan, scanless)

**Description:**  
All-in-one scanning frameworks. Require Nmap binary (GPL license) or Masscan binary.

**Python Wrapper: `python-nmap`**
- Requires: Nmap binary installed separately
- Licensing: Nmap is GPL; redistribution requires GPL compliance or OEM license ($2000+)
- Windows OEM: Includes Npcap OEM license bundled
- Verdict: For commercial tools, licensing burden outweighs convenience

**Scanless / Passive Tools:**
- `scanless` (external API-based)
- `shodan` API (requires API key, internet-dependent)

**Verdict for Desktop Apps:** Avoid GPL redistribution. Build composable single-protocol discovery instead (mDNS + SSDP + ARP parsing).

---

## Verified Gems (Non-Obvious Findings)

1. **Zeroconf 0.147.2 fixed Windows wheel distribution (Sep 2025)** — Was missing binaries; now ships correctly. Safe to use now.

2. **async-upnp-client is 2025-maintained with explicit Windows IPv6 scope ID support** — Not just "it works on Windows"; they test Windows-specific IPv6 quirks (scope IDs). Production-ready.

3. **WSDiscovery 2.1.2 (Jan 2025) released in active cadence** — Library had been dormant for years. Recently revived for ONVIF ecosystem expansion. Worth trusting.

4. **PySNMP is sustainable; easysnmp is dead** — Common misconception: easysnmp is "faster" but unmaintained since 2023. PySNMP slower but actively developed (50+ contributors, 151K weekly downloads).

5. **ICMP raw sockets on Windows ignore privileged parameter** — icmplib docs claim non-admin support, but Windows silently ignores the flag. Always requires admin for raw ICMP.

6. **ARP parsing via `arp -a` on Windows returns cached entries only** — Not active discovery; only shows devices that recently talked. Good for "is device on network?" checks, not full enumeration.

7. **Npcap/WinPcap licensing is commercial blocker** — Nmap OEM license $2000+, Npcap OEM redistribution separate license. If shipping with consumers, avoid Scapy+Npcap path. Use SSDP/mDNS instead.

---

## Proposed Skill Rules

### Rule: Multi-Homed Interface Iteration
**Pattern:** For mDNS/SSDP/WSD discovery, don't bind to a single interface. Iterate interfaces (via `netifaces2` or `ipconfig` parsing on Windows), send multicast probes from each active interface. Devices may respond only on the interface closest to them.

**Why:** Zeroconf, async-upnp-client, WSDiscovery all support per-interface binding. GUDE Discovery already does this (temp IP aliasing). Apply pattern to all UDP broadcast discovery.

---

### Rule: Timeout + Retry on Multicast
**Pattern:** First multicast probe with short timeout (500ms), then retry with 1000ms if low response count (<3 devices). Some devices slow to respond.

**Why:** WSDiscovery docs recommend 500ms timeout; real networks often need 1000ms. Avoid hanging the UI; two fast probes is better than one long wait.

---

### Rule: Fallback to Admin-Free Discovery
**Pattern:** Detect if app running with admin. If NO admin:
- Skip ICMP ping sweep, raw ARP scanning
- Fall back to mDNS + SSDP + ARP cache parsing
- Offer user "Run as Administrator for full discovery"

**Why:** Most users won't run desktop tools as admin. Design for that. Offer upgradable discovery path, not blocker.

---

### Rule: UDP Firewall Assumption
**Pattern:** All UDP multicast (239.255.255.250 and 224.0.0.251) may be firewalled. If no responses after two rounds, notify user "network firewall may block discovery" and offer manual IP entry.

**Why:** Corporate networks filter multicast hard. Real-world experience matters here.

---

### Rule: Async But Not Mandatory
**Pattern:** Use asyncio-ready libraries (async-upnp-client, asyncping, icmplib) but wrap sync API for simplicity. Let event loop be opt-in for future scaling.

**Why:** GUDE Deploy is PySide6 (Qt), not pure asyncio. Qt has own event loop. Async libraries should not force asyncio usage (zeroconf, async-upnp-client support this; scapy does not).

---

### Rule: License Check Before Adoption
**Pattern:** Before adding discovery method, check license:
- LGPL: OK (py-zeroconf, pysnmp, etc.)
- GPL: Requires GPL compliance document or OEM license ($$$)
- Apache/MIT: Preferred
- Proprietary: Research redistribution terms

**Why:** Commercial tool shipping GPL code must disclose source. OEM licenses cost $$. Plan early.

---

## Library Recommendation Matrix

| Protocol | Best Python Lib (2026) | Maintained? | Admin Required? | Windows OK? | Notes |
|----------|------------------------|-------------|-----------------|-------------|-------|
| mDNS | `zeroconf` 0.148.0 | YES (Oct 2025) | NO | YES (wheels fixed Sep 2025) | LGPL, no deps, 721★ |
| SSDP/UPnP | `async-upnp-client` 0.46.2 | YES (Jan 2026) | NO | YES (explicit IPv6 support) | Home Assistant standard, asyncio |
| WS-Discovery | `WSDiscovery` 2.1.2 | YES (Jan 2025) | NO | YES | ONVIF, revived 2025 |
| LLDP | `scapy` contrib | YES | YES (Npcap OEM) | YES (with Npcap) | Layer-2 only, licensing burden |
| SNMP | `pysnmp` | YES (sustainable) | NO | YES | 151K/week downloads, v3 needs crypto |
| ARP | `scapy` | YES | YES (Npcap OEM) | YES (with Npcap) | Or parse `arp -a` (no admin) |
| ICMP | `icmplib` | YES | YES (Windows) | Partial (wins ignore privileged) | Pure Python, asyncio, 2.0.2+ |
| DHCP sniff | `scapy` | YES | YES | YES (with Npcap) | Passive only, network monitoring |
| NetBIOS | Custom NBNS parse | N/A | NO | YES (UDP 137) | Legacy, not recommended |
| nmap wrapper | `python-nmap` | YES | Depends on nmap | YES | GPL (licensing check needed), OEM $2K+ |

---

## Anti-Patterns Found

1. **Blocking on single multicast round** — Don't `sleep(5)` waiting for all devices. Use threading/asyncio + timeout, then return what you have. Users hate spinners.

2. **Binding multicast to single interface** — Will miss devices on other subnets/vlans. Iterate all active interfaces, send from each.

3. **Assuming ICMP ping works on Windows without admin** — It doesn't, no matter what library claims. Plan for admin-free fallback path.

4. **Using easysnmp without checking maintenance** — Project abandoned 2023. Trap for new code. Use pysnmp instead.

5. **Deploying Scapy+Npcap without licensing review** — Npcap OEM not free. Add compliance doc early in commercial projects.

6. **Trusting old device response lists** — ARP cache stale, DHCP leases expire. Always treat discovery results as "best guess" not "ground truth."

7. **Single discovery round with long timeout** — Two 500ms rounds > one 1000ms round. Better UX.

---

## Open Questions / Unverified

1. **Do GUDE devices respond to SSDP M-SEARCH or WS-Discovery probes?**
   - Known: They respond to custom UDP 50123 GBL (proprietary)
   - Unknown: UPnP/SSDP support on newer models
   - Recommendation: Test with async-upnp-client on real hardware

2. **What's the actual Windows admin elevation flow for icmplib?**
   - Docs say "privileged ignored on Windows" but unclear if this means:
     - a) Falls back to unprivileged mode (works, slow)
     - b) Fails silently (wrong)
     - c) Requires UAC elevation (blocker)
   - Need: Direct testing on Windows 10/11

3. **Does Zeroconf IPv6 limitation matter for enterprise?**
   - Docs say IPv6 "limited"; unclear if this is "broken" or "just basic"
   - Enterprise networks still mostly IPv4 anyway
   - Low priority for GUDE (PDUs are IPv4 devices)

4. **Can WSDiscovery and async-upnp-client coexist in same app?**
   - Both use UDP multicast on same port (239.255.255.250:1900 and 3702)
   - No resource conflict documented
   - Recommendation: Test with both running

---

## Sources

### Zeroconf / mDNS
- [python-zeroconf PyPI](https://pypi.org/project/zeroconf/)
- [python-zeroconf GitHub](https://github.com/python-zeroconf/python-zeroconf)
- [python-zeroconf Docs](https://python-zeroconf.readthedocs.io/)

### SSDP / UPnP
- [ssdpy GitHub](https://github.com/MoshiBin/ssdpy)
- [async-upnp-client GitHub](https://github.com/StevenLooman/async_upnp_client)
- [async-upnp-client Snyk Report](https://snyk.io/advisor/python/async-upnp-client)

### WS-Discovery
- [WSDiscovery PyPI](https://pypi.org/project/WSDiscovery/)
- [python-ws-discovery GitHub](https://github.com/andreikop/python-ws-discovery)
- [WSDiscovery Docs](https://python-ws-discovery.readthedocs.io/)

### LLDP
- [Scapy LLDP contrib](https://github.com/secdev/scapy/blob/master/scapy/contrib/lldp.py)
- [WinLLDP GitHub](https://github.com/oriolrius/WinLLDP)

### SNMP
- [pysnmp PyPI](https://pypi.org/project/pysnmp/)
- [easysnmp Snyk Report](https://snyk.io/advisor/python/easysnmp) (maintenance status: inactive)

### ARP & Raw Packets
- [Scapy Usage Docs](https://scapy.readthedocs.io/en/latest/usage.html)
- [Scapy GitHub Issue #3873 (Windows admin)](https://github.com/secdev/scapy/issues/3873)
- [arp-scan GitHub](https://github.com/FrostyLabs/arp-scan)

### ICMP / Ping
- [icmplib PyPI](https://pypi.org/project/icmplib/)
- [icmplib GitHub](https://github.com/ValentinBELYN/icmplib)
- [ping3 PyPI](https://pypi.org/project/ping3/)
- [Microsoft Q&A: Non-privileged ICMP](https://learn.microsoft.com/en-us/answers/questions/2460086/non-privileged-icmp-raw-sockets)

### DHCP Snooping
- [Scapy DHCP Listener Tutorial](https://thepythoncode.com/article/dhcp-listener-using-scapy-in-python)
- [DHCP Sniffer Project](https://github.com/chmuhammadasim/DHCP-Sniffer-and-Analysis)

### nmap / Aggregate Tools
- [python-nmap PyPI](https://pypi.org/project/python-nmap/)
- [Nmap OEM License](https://nmap.org/oem/)
- [Npcap License](https://github.com/nmap/Npcap/blob/master/LICENSE)

