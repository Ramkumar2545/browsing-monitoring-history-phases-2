# 🌐 Wazuh Browser History Monitoring — Phase 2

> **SQLite-native browser history collector with configurable scan intervals**  
> Author: **Ram Kumar G** (IT Fortress) · [Phase 1 Repo](https://github.com/Ramkumar2545/wazuh-browser-history-monitoring)

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blue)]()
[![Version](https://img.shields.io/badge/version-3.0-green)]()
[![License](https://img.shields.io/badge/license-MIT-orange)]()

---

## 🆕 What's New in Phase 2

| Feature | Phase 1 | Phase 2 |
|---|---|---|
| Interval | Fixed 60 seconds | **Configurable at install time** |
| Interval options | — | 1m / 5m / 10m / 20m / 30m / 60m / 2h / 6h / 12h / 24h |
| Config persistence | — | `.browser_monitor_config.json` |
| Windows Task Scheduler | At logon only | **At logon + repeat trigger every N minutes** |
| macOS LaunchAgent | RunAtLoad + KeepAlive | **RunAtLoad + KeepAlive + `StartInterval`** |
| Linux systemd | Fixed RestartSec | **RestartSec = selected interval** |
| Safari WAL support | ✅ | ✅ |
| Extension monitoring | ✅ | ✅ |

---

## ⚡ One-Line Install

### 🪟 Windows (PowerShell — Run as Administrator)

```powershell
powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr -UseBasicParsing 'https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.ps1' | iex"
```

### 🐧 Linux

```bash
curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
```

### 🍎 macOS (do NOT use sudo)

```bash
curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
```

---

## 🕐 Interval Selection (Interactive Prompt)

During installation, you will be prompted to choose a scan interval:

```
[?] Select scan interval (how often to read browser SQLite history):

     1)  1  minute   (most frequent — high I/O)
     2)  5  minutes
     3)  10 minutes
     4)  20 minutes
     5)  30 minutes  (recommended)
     6)  60 minutes / 1 hour
     7)  2  hours
     8)  6  hours
     9)  12 hours
    10)  24 hours    (once per day)

    Enter choice [1-10] (default: 5 = 30 minutes):
```

The selected interval is persisted to:
- **Windows**: `C:\BrowserMonitor\.browser_monitor_config.json`
- **Linux/macOS**: `~/.browser-monitor/.browser_monitor_config.json`

To change the interval, simply re-run the installer or edit the JSON file directly.

---

## 📁 File Structure

```
browsing-monitoring-history-phases-2/
├── collector/
│   └── browser-history-monitor.py   # Core SQLite collector (v3.0)
├── install.ps1                       # Windows installer
├── install.sh                        # Linux / macOS installer
└── README.md
```

---

## 🔧 How It Works

1. **Installer runs interactively** → prompts for scan interval
2. **Config file written** → `{ "scan_interval_seconds": 1800, "scan_interval_label": "30m" }`
3. **Collector downloaded** → reads config on startup to set its loop sleep time
4. **Persistence registered**:
   - **Windows**: Task Scheduler with AtLogon + repeat trigger
   - **Linux (root)**: systemd system service with `RestartSec=<interval>`
   - **Linux (user)**: systemd user service
   - **macOS**: LaunchAgent with `StartInterval=<seconds>`
5. **Wazuh ossec.conf** updated with `<localfile>` pointing to the log

---

## 🖥️ Supported Browsers

| Browser | Windows | Linux | macOS |
|---|---|---|---|
| Chrome | ✅ | ✅ (native + snap + flatpak) | ✅ |
| Edge | ✅ | ✅ | ✅ |
| Brave | ✅ | ✅ | ✅ |
| Firefox | ✅ | ✅ | ✅ |
| Opera / OperaGX | ✅ | ✅ | ✅ |
| Vivaldi | ✅ | ✅ | ✅ |
| Waterfox | ✅ | ✅ | — |
| Chromium | ✅ | ✅ | ✅ |
| Tor Browser | ✅ | ✅ | — |
| Safari | — | — | ✅ (WAL-aware) |

---

## 📊 Log Format

All events are written in syslog format to `browser_history.log`:

```
Apr 16 18:30:01 HOSTNAME browser-monitor: service_started interval=1800s (30m)
Apr 16 18:30:02 HOSTNAME browser-monitor: 2026-04-16 18:29:50 Chrome john Default https://example.com Example Domain
Apr 16 18:30:02 HOSTNAME browser-monitor: [Extension] john Chrome Default "uBlock Origin" (cjpalhdlnbpafiamejdnhcphjbkeiagm) v1.58.0
```

Wazuh agent picks this up via `<localfile>` → forwards to manager → decoded by rules.

---

## 📂 Install Paths

| Platform | Collector | Log | Config |
|---|---|---|---|
| Windows | `C:\BrowserMonitor\browser-history-monitor.py` | `C:\BrowserMonitor\browser_history.log` | `C:\BrowserMonitor\.browser_monitor_config.json` |
| Linux (root) | `/root/.browser-monitor/browser-history-monitor.py` | `/root/.browser-monitor/browser_history.log` | same dir |
| Linux (user) | `~/.browser-monitor/browser-history-monitor.py` | `~/.browser-monitor/browser_history.log` | same dir |
| macOS | `~/.browser-monitor/browser-history-monitor.py` | `~/.browser-monitor/browser_history.log` | same dir |

---

## 🔁 Change Interval After Install

### Option A: Edit config file
```json
{
  "scan_interval_seconds": 300,
  "scan_interval_label": "5m"
}
```
Then restart the collector/service.

### Option B: Re-run the installer
```bash
# Linux/macOS
curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
```
```powershell
# Windows
powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr -UseBasicParsing 'https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.ps1' | iex"
```

---

## 📋 Requirements

- **Python 3.8+** (system-wide on Windows; any on Linux/macOS)
- **Wazuh Agent** installed on the endpoint
- **Windows**: Python with "Install for All Users" + "Add to PATH" checked
- **macOS Safari**: Full Disk Access granted to Python in System Settings

---

## 🛡️ Wazuh Manager Setup

Deploy the same decoders and rules from Phase 1:  
https://github.com/Ramkumar2545/wazuh-browser-history-monitoring

---

*Built with ❤️ by Ram Kumar G — IT Fortress*
