#!/bin/bash
# =============================================================================
# Wazuh Browser Monitor Phase 2 - Linux / macOS One-Line Installer
# Author  : Ram Kumar G (IT Fortress)
# Version : 3.0 (Phase 2 - Configurable Interval)
# Supports:
#   Linux  : Ubuntu 20.04+, Debian 11+, AlmaLinux 8+, RHEL 8+, CentOS 8+
#   macOS  : 12 Monterey, 13 Ventura, 14 Sonoma, 15 Sequoia
#
# Usage (curl one-liner):
#   curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
# =============================================================================

set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

REPO_RAW="https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main"
INSTALL_DIR="$HOME/.browser-monitor"
DEST_SCRIPT="$INSTALL_DIR/browser-history-monitor.py"
CONFIG_FILE="$INSTALL_DIR/.browser_monitor_config.json"
LOG_FILE="$INSTALL_DIR/browser_history.log"
OS_TYPE="$(uname -s)"

# macOS vs Linux paths
if [ "$OS_TYPE" = "Darwin" ]; then
    WAZUH_CONF="/Library/Ossec/etc/ossec.conf"
else
    WAZUH_CONF="/var/ossec/etc/ossec.conf"
fi

echo -e ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Wazuh Browser Monitor Phase 2 - $([ "$OS_TYPE" = 'Darwin' ] && echo 'macOS' || echo 'Linux') Installer         ║${NC}"
echo -e "${BLUE}║  IT Fortress | Configurable Interval | SQLite-Native        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e ""

# ── STEP 1: PYTHON CHECK ──────────────────────────────────────────────────────
echo -e "${YELLOW}[1] Checking Python 3...${NC}"
PYTHON_BIN=""
for py in python3 python3.12 python3.11 python3.10 python3.9 python3.8; do
    if command -v "$py" &>/dev/null; then PYTHON_BIN=$(command -v "$py"); break; fi
done
if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}[-] Python 3 not found.${NC}"
    if   command -v apt-get &>/dev/null; then echo "    Run: sudo apt install -y python3"
    elif command -v dnf     &>/dev/null; then echo "    Run: sudo dnf install -y python3"
    elif command -v yum     &>/dev/null; then echo "    Run: sudo yum install -y python3"; fi
    exit 1
fi
echo -e "${GREEN}    [+] $($PYTHON_BIN --version 2>&1) at $PYTHON_BIN${NC}"

# ── STEP 2: INTERVAL SELECTION ────────────────────────────────────────────────
echo -e ""
echo -e "${YELLOW}[2] Select scan interval (how often to read browser SQLite history):${NC}"
echo -e "     1)  ${CYAN}1  minute${NC}   (high I/O)"
echo -e "     2)  5  minutes"
echo -e "     3)  10 minutes"
echo -e "     4)  20 minutes"
echo -e "     5)  ${CYAN}30 minutes${NC}  (recommended)"
echo -e "     6)  60 minutes / 1 hour"
echo -e "     7)  2  hours"
echo -e "     8)  6  hours"
echo -e "     9)  12 hours"
echo -e "    10)  24 hours    (once per day)"
echo -e ""

if [ -t 0 ]; then
    read -rp "    Enter choice [1-10] (default: 5 = 30 minutes): " CHOICE
else
    CHOICE="5"
    echo -e "    ${YELLOW}(Non-interactive: defaulting to 5 = 30 minutes)${NC}"
fi
[ -z "$CHOICE" ] && CHOICE="5"

case "$CHOICE" in
    1)  SECS=60;    LABEL="1m" ;;
    2)  SECS=300;   LABEL="5m" ;;
    3)  SECS=600;   LABEL="10m";;
    4)  SECS=1200;  LABEL="20m";;
    5)  SECS=1800;  LABEL="30m";;
    6)  SECS=3600;  LABEL="60m";;
    7)  SECS=7200;  LABEL="2h" ;;
    8)  SECS=21600; LABEL="6h" ;;
    9)  SECS=43200; LABEL="12h";;
    10) SECS=86400; LABEL="24h";;
    *)  SECS=1800;  LABEL="30m";;
esac

echo -e "${GREEN}    [+] Selected: $LABEL ($SECS seconds)${NC}"

# ── STEP 3: INSTALL DIR & DOWNLOAD ────────────────────────────────────────────
echo -e ""
echo -e "${YELLOW}[3] Installing to $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR"

if command -v curl &>/dev/null; then
    curl -sSL "$REPO_RAW/collector/browser-history-monitor.py" -o "$DEST_SCRIPT"
elif command -v wget &>/dev/null; then
    wget -qO "$DEST_SCRIPT" "$REPO_RAW/collector/browser-history-monitor.py"
else
    echo -e "${RED}[-] Neither curl nor wget found.${NC}"; exit 1
fi

chmod 755 "$DEST_SCRIPT"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo -e "${GREEN}    [+] Collector: $DEST_SCRIPT${NC}"
echo -e "${GREEN}    [+] Log file : $LOG_FILE${NC}"

# ── STEP 4: WRITE CONFIG ──────────────────────────────────────────────────────
echo -e ""
echo -e "${YELLOW}[4] Writing interval config...${NC}"
cat > "$CONFIG_FILE" <<EOF
{"scan_interval_seconds": $SECS, "scan_interval_label": "$LABEL"}
EOF
echo -e "${GREEN}    [+] Config: $CONFIG_FILE  [$LABEL = ${SECS}s]${NC}"

# ── STEP 5: REGISTER SERVICE / LAUNCHAGENT ────────────────────────────────────
echo -e ""
echo -e "${YELLOW}[5] Registering persistence...${NC}"

if [ "$OS_TYPE" = "Darwin" ]; then
    # ── macOS LaunchAgent ──────────────────────────────────────────────────────
    PLIST_DIR="$HOME/Library/LaunchAgents"
    LABEL_ID="com.ramkumar.browser-monitor"
    PLIST_FILE="$PLIST_DIR/$LABEL_ID.plist"
    mkdir -p "$PLIST_DIR"
    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_BIN</string>
        <string>$DEST_SCRIPT</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StartInterval</key>
    <integer>$SECS</integer>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/error.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"
    sleep 2
    if launchctl list | grep -q "$LABEL_ID"; then
        echo -e "${GREEN}    [+] LaunchAgent running: $LABEL_ID (interval: $LABEL)${NC}"
    else
        echo -e "${YELLOW}    [!] LaunchAgent may not have started. Grant Full Disk Access to: $PYTHON_BIN${NC}"
        echo -e "        System Settings → Privacy & Security → Full Disk Access"
        echo -e "        Then: launchctl unload $PLIST_FILE && launchctl load $PLIST_FILE"
    fi

else
    # ── Linux: systemd (root or user) ─────────────────────────────────────────
    if [ "$(id -u)" = "0" ]; then
        # root: system service
        SERVICE_FILE="/etc/systemd/system/browser-monitor.service"
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wazuh Browser History Monitor Phase 2
Documentation=https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN $DEST_SCRIPT
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=$SECS
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable browser-monitor
        systemctl restart browser-monitor
        sleep 2
        if systemctl is-active --quiet browser-monitor; then
            echo -e "${GREEN}    [+] systemd service running (RestartSec=${SECS}s)${NC}"
        else
            echo -e "${YELLOW}    [!] Check: journalctl -u browser-monitor -n 30${NC}"
        fi
    else
        # user: systemd user service
        SERVICE_DIR="$HOME/.config/systemd/user"
        SERVICE_FILE="$SERVICE_DIR/browser-monitor.service"
        mkdir -p "$SERVICE_DIR"
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wazuh Browser History Monitor Phase 2
Documentation=https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN $DEST_SCRIPT
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=$SECS
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable browser-monitor
        systemctl --user restart browser-monitor
        sleep 2
        if systemctl --user is-active --quiet browser-monitor; then
            echo -e "${GREEN}    [+] systemd user service running (RestartSec=${SECS}s)${NC}"
        else
            echo -e "${YELLOW}    [!] Check: journalctl --user -u browser-monitor -n 30${NC}"
        fi
        if command -v loginctl &>/dev/null; then
            loginctl enable-linger "$USER" 2>/dev/null || true
            echo -e "${GREEN}    [+] loginctl linger enabled for $USER${NC}"
        fi
    fi
fi

# ── STEP 6: WAZUH OSSEC.CONF ──────────────────────────────────────────────────
echo -e ""
echo -e "${YELLOW}[6] Updating Wazuh ossec.conf...${NC}"
MARKER="<!-- BROWSER_MONITOR_P2 -->"

if [ -f "$WAZUH_CONF" ]; then
    if ! grep -q "$MARKER" "$WAZUH_CONF" 2>/dev/null; then
        if [ "$OS_TYPE" = "Darwin" ]; then
            sed -i '' "s|</ossec_config>|\n  <!-- BROWSER_MONITOR_P2 -->\n  <localfile>\n    <location>$LOG_FILE</location>\n    <log_format>syslog</log_format>\n  </localfile>\n</ossec_config>|" "$WAZUH_CONF"
        else
            sudo sed -i "s|</ossec_config>|\n  <!-- BROWSER_MONITOR_P2 -->\n  <localfile>\n    <location>$LOG_FILE</location>\n    <log_format>syslog</log_format>\n  </localfile>\n</ossec_config>|" "$WAZUH_CONF"
        fi
        echo -e "${GREEN}    [+] localfile block added to ossec.conf${NC}"
        if [ "$OS_TYPE" = "Darwin" ]; then
            /Library/Ossec/bin/wazuh-control restart 2>/dev/null || true
        else
            sudo systemctl restart wazuh-agent 2>/dev/null || sudo /var/ossec/bin/wazuh-control restart 2>/dev/null || true
        fi
        echo -e "${GREEN}    [+] Wazuh agent restarted${NC}"
    else
        echo -e "${GREEN}    [=] localfile block already present — skipping${NC}"
    fi
else
    echo -e "${YELLOW}    [!] ossec.conf not found at $WAZUH_CONF${NC}"
    echo -e "    Add manually inside <ossec_config>:"
    echo -e "      <localfile>"
    echo -e "        <location>$LOG_FILE</location>"
    echo -e "        <log_format>syslog</log_format>"
    echo -e "      </localfile>"
fi

# ── DONE ──────────────────────────────────────────────────────────────────────
echo -e ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  [SUCCESS] Phase 2 Installation Complete!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo    "  Interval : $LABEL ($SECS seconds)"
echo    "  Log file : $LOG_FILE"
echo -e "  Watch    : ${CYAN}tail -f $LOG_FILE${NC}"
if [ "$OS_TYPE" = "Darwin" ]; then
    echo -e "  Service  : ${CYAN}launchctl list | grep browser-monitor${NC}"
    echo -e "  ${YELLOW}⚠ IMPORTANT: Grant Full Disk Access to $PYTHON_BIN${NC}"
    echo    "     System Settings → Privacy & Security → Full Disk Access"
elif [ "$(id -u)" = "0" ]; then
    echo -e "  Service  : ${CYAN}systemctl status browser-monitor${NC}"
    echo -e "  Journal  : ${CYAN}journalctl -u browser-monitor -f${NC}"
else
    echo -e "  Service  : ${CYAN}systemctl --user status browser-monitor${NC}"
    echo -e "  Journal  : ${CYAN}journalctl --user -u browser-monitor -f${NC}"
fi
echo ""
