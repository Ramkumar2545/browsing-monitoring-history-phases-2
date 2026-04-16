#!/bin/bash
# =============================================================================
# Wazuh Browser Monitor Phase 2 - One-Line Bootstrap Installer for Linux / macOS
# Author  : Ram Kumar G (IT Fortress)
# Version : 3.0 (Configurable Interval + systemd/LaunchAgent)
# Repo    : https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2
#
# USAGE (macOS — do NOT prefix with sudo):
#   curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
#
# USAGE (Linux root / non-root):
#   curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
#   sudo curl -sSL https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.sh | bash
#
# Supported intervals: 1m, 5m, 10m, 20m, 30m, 60m, 2h, 6h, 12h, 24h
# Interval is written to .browser_monitor_config.json and read by the collector.
# =============================================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

REPO_BASE="https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main"
COLLECTOR_URL="$REPO_BASE/collector/browser-history-monitor.py"

OS="$(uname -s)"
SCRIPT_UID="$(id -u)"

# =============================================================================
# macOS: resolve the REAL console (GUI) user.
# =============================================================================
if [ "$OS" = "Darwin" ]; then
    MAC_REAL_USER=""
    MAC_REAL_USER=$(scutil <<< "show State:/Users/ConsoleUser" 2>/dev/null \
        | awk '/Name :/ && !/loginwindow/ { print $3; exit }')
    if [ -z "$MAC_REAL_USER" ] || [ "$MAC_REAL_USER" = "root" ]; then
        MAC_REAL_USER=$(who 2>/dev/null | awk '!/root/ {print $1; exit}')
    fi
    if [ -z "$MAC_REAL_USER" ] && [ "$SCRIPT_UID" -ne 0 ]; then
        MAC_REAL_USER="$USER"
    fi
    if [ -z "$MAC_REAL_USER" ] || [ "$MAC_REAL_USER" = "root" ]; then
        echo -e "${RED}[!] macOS: Cannot determine the real GUI user.${NC}"
        echo -e "${YELLOW}    Run WITHOUT sudo as your normal user.${NC}"
        exit 1
    fi
    MAC_REAL_HOME=$(dscl . -read "/Users/$MAC_REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [ -z "$MAC_REAL_HOME" ] && MAC_REAL_HOME="/Users/$MAC_REAL_USER"
    MAC_REAL_UID=$(id -u "$MAC_REAL_USER" 2>/dev/null)
    REAL_HOME="$MAC_REAL_HOME"
    INSTALL_DIR="$REAL_HOME/.browser-monitor"
    echo -e "${GREEN}[*] macOS real user : $MAC_REAL_USER (uid=$MAC_REAL_UID)${NC}"
else
    REAL_HOME="$HOME"
    if [ "$SCRIPT_UID" -eq 0 ]; then
        INSTALL_DIR="/root/.browser-monitor"
    else
        INSTALL_DIR="$HOME/.browser-monitor"
    fi
fi

DEST_SCRIPT="$INSTALL_DIR/browser-history-monitor.py"
LOG_FILE="$INSTALL_DIR/browser_history.log"
CONFIG_FILE="$INSTALL_DIR/.browser_monitor_config.json"

if [ "$OS" = "Darwin" ]; then
    WAZUH_CONF="/Library/Ossec/etc/ossec.conf"
    [ ! -f "$WAZUH_CONF" ] && WAZUH_CONF="/var/ossec/etc/ossec.conf"
else
    WAZUH_CONF="/var/ossec/etc/ossec.conf"
fi

echo -e ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Wazuh Browser Monitor Phase 2 - Installer v3.0        ║${NC}"
echo -e "${BLUE}║  IT Fortress | github.com/Ramkumar2545               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "${GREEN}[*] OS: $OS${NC}"

# ── DETECT ENVIRONMENT ───────────────────────────────────────────────────────
IS_ROOT=0
[ "$SCRIPT_UID" -eq 0 ] && IS_ROOT=1

IS_CONTAINER=0
if [ -f /.dockerenv ]; then
    IS_CONTAINER=1
elif grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; then
    IS_CONTAINER=1
elif [ "$OS" = "Linux" ] && ! systemctl --user status >/dev/null 2>&1; then
    IS_CONTAINER=1
fi
[ "$IS_CONTAINER" -eq 1 ] && echo -e "${YELLOW}[*] Container/no-D-Bus env detected — nohup fallback${NC}"

# ── INTERVAL SELECTION ───────────────────────────────────────────────────────
# When piped from curl, stdin is the script — read from /dev/tty for interaction
exec </dev/tty 2>/dev/null || true

echo -e ""
echo -e "${CYAN}[?] Select scan interval (how often to read browser SQLite history):${NC}"
echo ""
echo "     1)  1  minute   (most frequent — high I/O)"
echo "     2)  5  minutes"
echo "     3)  10 minutes"
echo "     4)  20 minutes"
echo "     5)  30 minutes  (recommended)"
echo "     6)  60 minutes / 1 hour"
echo "     7)  2  hours"
echo "     8)  6  hours"
echo "     9)  12 hours"
echo "    10)  24 hours    (once per day)"
echo ""

INTERVAL_SECONDS=1800
INTERVAL_LABEL="30m"

while true; do
    printf "    Enter choice [1-10] (default: 5 = 30 minutes): "
    read -r CHOICE </dev/tty 2>/dev/null || CHOICE="5"
    [ -z "$CHOICE" ] && CHOICE="5"
    case "$CHOICE" in
        1) INTERVAL_SECONDS=60;    INTERVAL_LABEL="1m";  break ;;
        2) INTERVAL_SECONDS=300;   INTERVAL_LABEL="5m";  break ;;
        3) INTERVAL_SECONDS=600;   INTERVAL_LABEL="10m"; break ;;
        4) INTERVAL_SECONDS=1200;  INTERVAL_LABEL="20m"; break ;;
        5) INTERVAL_SECONDS=1800;  INTERVAL_LABEL="30m"; break ;;
        6) INTERVAL_SECONDS=3600;  INTERVAL_LABEL="60m"; break ;;
        7) INTERVAL_SECONDS=7200;  INTERVAL_LABEL="2h";  break ;;
        8) INTERVAL_SECONDS=21600; INTERVAL_LABEL="6h";  break ;;
        9) INTERVAL_SECONDS=43200; INTERVAL_LABEL="12h"; break ;;
       10) INTERVAL_SECONDS=86400; INTERVAL_LABEL="24h"; break ;;
        *) echo -e "${RED}    [!] Invalid choice. Enter 1-10.${NC}" ;;
    esac
done

echo -e "${GREEN}    [+] Selected interval: $INTERVAL_LABEL ($INTERVAL_SECONDS seconds)${NC}"

# ── STEP 1: PYTHON CHECK ─────────────────────────────────────────────────────
echo -e "${YELLOW}[1] Checking Python 3...${NC}"
PYTHON_BIN=""
for py in python3 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8; do
    if command -v "$py" &>/dev/null; then PYTHON_BIN=$(command -v "$py"); break; fi
done
if [ -z "$PYTHON_BIN" ] && [ "$OS" = "Darwin" ]; then
    for py in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        [ -x "$py" ] && PYTHON_BIN="$py" && break
    done
fi
if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}[-] Python 3 not found.${NC}"
    [ "$OS" = "Linux" ]  && echo "    Install: apt install -y python3"
    [ "$OS" = "Darwin" ] && echo "    Install: brew install python3"
    exit 1
fi
echo -e "${GREEN}    [+] $($PYTHON_BIN --version 2>&1) at $PYTHON_BIN${NC}"

# ── STEP 2: CREATE DIRS ──────────────────────────────────────────────────────
echo -e "${YELLOW}[2] Creating $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
if [ "$OS" = "Darwin" ] && [ "$IS_ROOT" -eq 1 ]; then
    chown -R "$MAC_REAL_USER" "$INSTALL_DIR"
fi
echo -e "${GREEN}    [+] Directory ready${NC}"

# ── STEP 3: WRITE CONFIG FILE ────────────────────────────────────────────────
echo -e "${YELLOW}[3] Writing config file (interval=$INTERVAL_LABEL)...${NC}"
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
cat > "$CONFIG_FILE" <<CFGEOF
{
  "scan_interval_seconds": $INTERVAL_SECONDS,
  "scan_interval_label": "$INTERVAL_LABEL",
  "installed_at": "$INSTALL_DATE",
  "version": "3.0"
}
CFGEOF
chmod 644 "$CONFIG_FILE"
[ "$OS" = "Darwin" ] && [ "$IS_ROOT" -eq 1 ] && chown "$MAC_REAL_USER" "$CONFIG_FILE"
echo -e "${GREEN}    [+] Config written: $CONFIG_FILE${NC}"

# ── STEP 4: DOWNLOAD COLLECTOR ───────────────────────────────────────────────
echo -e "${YELLOW}[4] Downloading collector...${NC}"
if command -v curl &>/dev/null; then
    curl -sSL -o "$DEST_SCRIPT" "$COLLECTOR_URL"
elif command -v wget &>/dev/null; then
    wget -qO "$DEST_SCRIPT" "$COLLECTOR_URL"
else
    echo -e "${RED}[-] Neither curl nor wget found.${NC}"; exit 1
fi
FILE_SIZE=$(wc -c < "$DEST_SCRIPT" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo -e "${RED}[-] Download failed ($FILE_SIZE bytes).${NC}"; exit 1
fi
chmod 755 "$DEST_SCRIPT"
[ "$OS" = "Darwin" ] && [ "$IS_ROOT" -eq 1 ] && chown "$MAC_REAL_USER" "$DEST_SCRIPT"
echo -e "${GREEN}    [+] Downloaded: $DEST_SCRIPT ($FILE_SIZE bytes)${NC}"

# ── NOHUP FALLBACK ───────────────────────────────────────────────────────────
_start_nohup() {
    pkill -f "browser-history-monitor.py" 2>/dev/null || true
    sleep 1
    nohup "$PYTHON_BIN" "$DEST_SCRIPT" >> "$INSTALL_DIR/error.log" 2>&1 &
    BGPID=$!
    sleep 2
    if kill -0 "$BGPID" 2>/dev/null; then
        echo -e "${GREEN}    [+] Collector running via nohup (PID $BGPID)${NC}"
        echo "$BGPID" > "$INSTALL_DIR/browser-monitor.pid"
        cat > "$INSTALL_DIR/restart.sh" <<RESTART
#!/bin/bash
pkill -f browser-history-monitor.py 2>/dev/null || true
sleep 1
nohup $PYTHON_BIN $DEST_SCRIPT >> $INSTALL_DIR/error.log 2>&1 &
echo \$! > $INSTALL_DIR/browser-monitor.pid
echo "[+] Restarted (PID \$!)"
RESTART
        chmod +x "$INSTALL_DIR/restart.sh"
        echo -e "${YELLOW}    [!] Add to crontab for persistence:${NC}"
        echo "        @reboot $PYTHON_BIN $DEST_SCRIPT >> $INSTALL_DIR/error.log 2>&1 &"
    else
        echo -e "${RED}    [-] Collector failed to start. Check: $INSTALL_DIR/error.log${NC}"
    fi
}

# ── STEP 5: PERSISTENCE ──────────────────────────────────────────────────────
echo -e "${YELLOW}[5] Setting up background service...${NC}"

if [ "$OS" = "Linux" ]; then
    if [ "$IS_ROOT" -eq 1 ] || [ "$IS_CONTAINER" -eq 1 ]; then
        SERVICE_FILE="/etc/systemd/system/browser-monitor.service"
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wazuh Browser History Monitor Phase 2
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN $DEST_SCRIPT
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=$INTERVAL_SECONDS
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        if systemctl daemon-reload 2>/dev/null && \
           systemctl enable browser-monitor 2>/dev/null && \
           systemctl restart browser-monitor 2>/dev/null; then
            sleep 2
            systemctl is-active --quiet browser-monitor 2>/dev/null && \
                echo -e "${GREEN}    [+] Systemd SYSTEM service running (RestartSec=${INTERVAL_SECONDS}s)${NC}" || \
                { echo -e "${YELLOW}    [!] Systemd inactive — nohup fallback${NC}"; _start_nohup; }
        else
            echo -e "${YELLOW}    [!] Systemd unavailable — nohup fallback${NC}"
            _start_nohup
        fi
    else
        SERVICE_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SERVICE_DIR"
        cat > "$SERVICE_DIR/browser-monitor.service" <<EOF
[Unit]
Description=Wazuh Browser History Monitor Phase 2
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN $DEST_SCRIPT
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=$INTERVAL_SECONDS
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable  browser-monitor 2>/dev/null || true
        systemctl --user restart browser-monitor 2>/dev/null || true
        sleep 2
        systemctl --user is-active --quiet browser-monitor 2>/dev/null && \
            echo -e "${GREEN}    [+] Systemd USER service running (interval=$INTERVAL_LABEL)${NC}" || \
            { echo -e "${YELLOW}    [!] User service failed — nohup fallback${NC}"; _start_nohup; }
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

elif [ "$OS" = "Darwin" ]; then
    LABEL="com.ramkumar.browser-monitor-p2"
    PLIST_DIR="$REAL_HOME/Library/LaunchAgents"
    PLIST_FILE="$PLIST_DIR/$LABEL.plist"
    mkdir -p "$PLIST_DIR"

    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$PYTHON_BIN</string><string>$DEST_SCRIPT</string></array>
    <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StartInterval</key><integer>$INTERVAL_SECONDS</integer>
    <key>StandardOutPath</key><string>/dev/null</string>
    <key>StandardErrorPath</key><string>$INSTALL_DIR/error.log</string>
    <key>UserName</key><string>$MAC_REAL_USER</string>
</dict>
</plist>
EOF
    chown "$MAC_REAL_USER" "$PLIST_FILE"
    chmod 644 "$PLIST_FILE"

    echo -e ""
    echo -e "${YELLOW}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │  REQUIRED for Safari: System Settings → Privacy &      │${NC}"
    echo -e "${YELLOW}  │  Security → Full Disk Access → add $PYTHON_BIN         │${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────────────────┘${NC}"
    echo -e ""

    if [ "$IS_ROOT" -eq 1 ]; then
        su -l "$MAC_REAL_USER" -c "launchctl bootout gui/$MAC_REAL_UID/$LABEL 2>/dev/null; true" 2>/dev/null || true
    else
        launchctl bootout "gui/$MAC_REAL_UID/$LABEL" 2>/dev/null || true
    fi
    sleep 1

    LOAD_OK=0
    if [ "$IS_ROOT" -eq 1 ]; then
        su -l "$MAC_REAL_USER" -c "launchctl bootstrap gui/$MAC_REAL_UID '$PLIST_FILE'" 2>/dev/null && LOAD_OK=1
    else
        launchctl bootstrap "gui/$MAC_REAL_UID" "$PLIST_FILE" 2>/dev/null && LOAD_OK=1
    fi
    if [ "$LOAD_OK" -eq 0 ]; then
        if [ "$IS_ROOT" -eq 1 ]; then
            su -l "$MAC_REAL_USER" -c "launchctl load '$PLIST_FILE'" 2>/dev/null && LOAD_OK=1
        else
            launchctl load "$PLIST_FILE" 2>/dev/null && LOAD_OK=1
        fi
    fi

    sleep 2
    if [ "$LOAD_OK" -eq 1 ]; then
        echo -e "${GREEN}    [+] LaunchAgent loaded for user: $MAC_REAL_USER (StartInterval=$INTERVAL_SECONDS)${NC}"
    else
        echo -e "${RED}    [-] LaunchAgent failed. Run manually:${NC}"
        echo "        launchctl bootstrap gui/$MAC_REAL_UID $PLIST_FILE"
    fi
fi

# ── STEP 6: WAZUH OSSEC.CONF ─────────────────────────────────────────────────
echo -e "${YELLOW}[6] Updating Wazuh ossec.conf...${NC}"
MARKER="<!-- BROWSER_MONITOR_P2 -->"

if [ -f "$WAZUH_CONF" ]; then
    if ! grep -q "$MARKER" "$WAZUH_CONF"; then
        if [ "$OS" = "Darwin" ]; then
            sed -i '' "s|</ossec_config>|\n  $MARKER\n  <localfile>\n    <location>$LOG_FILE</location>\n    <log_format>syslog</log_format>\n  </localfile>\n</ossec_config>|" "$WAZUH_CONF"
        else
            sed -i "s|</ossec_config>|\n  $MARKER\n  <localfile>\n    <location>$LOG_FILE</location>\n    <log_format>syslog</log_format>\n  </localfile>\n</ossec_config>|" "$WAZUH_CONF"
        fi
        echo -e "${GREEN}    [+] localfile block added${NC}"
        if [ "$OS" = "Darwin" ]; then
            /Library/Ossec/bin/wazuh-control restart 2>/dev/null || true
        else
            systemctl restart wazuh-agent 2>/dev/null || /var/ossec/bin/wazuh-control restart 2>/dev/null || true
        fi
    else
        echo -e "${GREEN}    [=] Already configured — skipping${NC}"
    fi
else
    echo -e "${YELLOW}    [!] ossec.conf not found. Add manually:${NC}"
    echo "      <localfile>"
    echo "        <location>$LOG_FILE</location>"
    echo "        <log_format>syslog</log_format>"
    echo "      </localfile>"
fi

# ── DONE ─────────────────────────────────────────────────────────────────────
echo -e ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  [SUCCESS] Phase 2 Installation Complete! v3.0         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo "  Collector : $DEST_SCRIPT"
echo "  Config    : $CONFIG_FILE"
echo "  Log file  : $LOG_FILE"
echo "  Interval  : $INTERVAL_LABEL ($INTERVAL_SECONDS seconds)"
echo ""
echo "  Watch logs : tail -f $LOG_FILE"
if [ "$OS" = "Darwin" ]; then
    echo "  Status     : launchctl print gui/$MAC_REAL_UID/$LABEL"
    echo "  Stop       : launchctl bootout gui/$MAC_REAL_UID/$LABEL"
else
    echo "  Restart    : bash $INSTALL_DIR/restart.sh"
fi
echo ""
echo "  Repo: https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2"
echo ""
