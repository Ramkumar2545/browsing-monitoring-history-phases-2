<#
.SYNOPSIS
    Wazuh Browser Monitor Phase 2 - One-Line Bootstrap Installer for Windows
    Author  : Ram Kumar G (IT Fortress)
    Version : 3.0 (Configurable Interval + Task Scheduler)
    Repo    : https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2

.DESCRIPTION
    Interactive installer that prompts for scan interval during setup.
    Sets the interval in .browser_monitor_config.json and registers a
    Windows Task Scheduler task that runs the collector hidden at logon
    with automatic restart every <interval> minutes.

    Supported intervals: 1m, 5m, 10m, 20m, 30m, 60m, 2h, 6h, 12h, 24h

    USAGE (run as Administrator in PowerShell):
      powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr -UseBasicParsing 'https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.ps1' | iex"

    REQUIREMENTS:
      Python 3.8+ must be installed SYSTEM-WIDE before running this.
      Download from: https://python.org
      During install: check 'Install for All Users' AND 'Add to PATH'
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ─── CONFIG ──────────────────────────────────────────────────────────────────
$RepoBase     = "https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main"
$InstallDir   = "C:\BrowserMonitor"
$TaskName     = "BrowserHistoryMonitor"
$LogFile      = "$InstallDir\browser_history.log"
$ConfigFile   = "$InstallDir\.browser_monitor_config.json"
$WazuhConf    = "C:\Program Files (x86)\ossec-agent\ossec.conf"
$WazuhSvc     = "WazuhSvc"

$CollectorUrl = "$RepoBase/collector/browser-history-monitor.py"
$CollectorDst = "$InstallDir\browser-history-monitor.py"

# ─── INTERVAL MAP ────────────────────────────────────────────────────────────
$IntervalMap = @{
    "1"  = @{ Label="1m";  Seconds=60;    RepeatMins=1 }
    "2"  = @{ Label="5m";  Seconds=300;   RepeatMins=5 }
    "3"  = @{ Label="10m"; Seconds=600;   RepeatMins=10 }
    "4"  = @{ Label="20m"; Seconds=1200;  RepeatMins=20 }
    "5"  = @{ Label="30m"; Seconds=1800;  RepeatMins=30 }
    "6"  = @{ Label="60m"; Seconds=3600;  RepeatMins=60 }
    "7"  = @{ Label="2h";  Seconds=7200;  RepeatMins=120 }
    "8"  = @{ Label="6h";  Seconds=21600; RepeatMins=360 }
    "9"  = @{ Label="12h"; Seconds=43200; RepeatMins=720 }
    "10" = @{ Label="24h"; Seconds=86400; RepeatMins=1440 }
}

# ─── BANNER ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Wazuh Browser Monitor Phase 2 - Installer v3.0         ║" -ForegroundColor Cyan
Write-Host "║  IT Fortress  |  github.com/Ramkumar2545                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── ADMIN CHECK ─────────────────────────────────────────────────────────────
Write-Host "[*] Checking Administrator privileges..." -ForegroundColor Yellow
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] ERROR: Run PowerShell as Administrator and retry." -ForegroundColor Red
    Write-Host "    Right-click PowerShell -> 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}
Write-Host "    [+] Running as Administrator" -ForegroundColor Green

# ─── INTERVAL SELECTION ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "[?] Select scan interval (how often to read browser SQLite history):" -ForegroundColor Cyan
Write-Host ""
Write-Host "     1)  1  minute   (most frequent — high I/O)" -ForegroundColor White
Write-Host "     2)  5  minutes" -ForegroundColor White
Write-Host "     3)  10 minutes" -ForegroundColor White
Write-Host "     4)  20 minutes" -ForegroundColor White
Write-Host "     5)  30 minutes  (recommended for most environments)" -ForegroundColor Green
Write-Host "     6)  60 minutes / 1 hour" -ForegroundColor White
Write-Host "     7)  2  hours" -ForegroundColor White
Write-Host "     8)  6  hours" -ForegroundColor White
Write-Host "     9)  12 hours" -ForegroundColor White
Write-Host "    10)  24 hours    (once per day)" -ForegroundColor White
Write-Host ""

$SelectedInterval = $null
do {
    $Choice = Read-Host "    Enter choice [1-10] (default: 5 = 30 minutes)"
    if ([string]::IsNullOrWhiteSpace($Choice)) { $Choice = "5" }
    if ($IntervalMap.ContainsKey($Choice)) {
        $SelectedInterval = $IntervalMap[$Choice]
    } else {
        Write-Host "    [!] Invalid choice. Please enter 1-10." -ForegroundColor Red
    }
} while (-not $SelectedInterval)

$IntervalSeconds = $SelectedInterval.Seconds
$IntervalLabel   = $SelectedInterval.Label
$RepeatMins      = $SelectedInterval.RepeatMins

Write-Host ""
Write-Host "    [+] Selected interval: $IntervalLabel ($IntervalSeconds seconds)" -ForegroundColor Green

# ─── STEP 1: DETECT PYTHON ───────────────────────────────────────────────────
Write-Host ""
Write-Host "[1] Detecting System-Wide Python..." -ForegroundColor Yellow

$PythonExe  = $null
$PythonWExe = $null

$PythonPaths = @(
    "C:\Program Files\Python313\python.exe",
    "C:\Program Files\Python312\python.exe",
    "C:\Program Files\Python311\python.exe",
    "C:\Program Files\Python310\python.exe",
    "C:\Program Files (x86)\Python312\python.exe",
    "C:\Python312\python.exe",
    "C:\Python311\python.exe",
    "C:\Python310\python.exe"
)

foreach ($p in $PythonPaths) {
    if (Test-Path $p) { $PythonExe = $p; break }
}

if (-not $PythonExe) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*\Users\*") {
        $PythonExe = $cmd.Source
    }
}

if (-not $PythonExe) {
    Write-Host ""
    Write-Host "[-] Python 3 not found (system-wide)." -ForegroundColor Red
    Write-Host ""
    Write-Host "  ACTION REQUIRED:" -ForegroundColor Yellow
    Write-Host "  1. Download Python from: https://python.org/downloads" -ForegroundColor White
    Write-Host "  2. During install, CHECK these two boxes:" -ForegroundColor White
    Write-Host "       [x] Install for All Users" -ForegroundColor Cyan
    Write-Host "       [x] Add Python to PATH" -ForegroundColor Cyan
    Write-Host "  3. After install, re-run this script." -ForegroundColor White
    Write-Host ""
    exit 1
}

$PyDir = Split-Path $PythonExe -Parent
$PythonWExe = Join-Path $PyDir "pythonw.exe"
if (-not (Test-Path $PythonWExe)) { $PythonWExe = $PythonExe }

Write-Host "    [+] Python   : $PythonExe" -ForegroundColor Green
Write-Host "    [+] PythonW  : $PythonWExe" -ForegroundColor Green

# ─── STEP 2: CREATE INSTALL DIRECTORY ────────────────────────────────────────
Write-Host ""
Write-Host "[2] Creating $InstallDir..." -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

$Acl = Get-Acl $InstallDir
$Ar  = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Users","Modify","ContainerInherit,ObjectInherit","None","Allow"
)
$Acl.SetAccessRule($Ar)
Set-Acl $InstallDir $Acl
Write-Host "    [+] Created with BUILTIN\Users:Modify permissions" -ForegroundColor Green

# ─── STEP 3: WRITE CONFIG FILE ───────────────────────────────────────────────
Write-Host ""
Write-Host "[3] Writing config file with interval=$IntervalLabel..." -ForegroundColor Yellow
$Config = @{
    scan_interval_seconds = $IntervalSeconds
    scan_interval_label   = $IntervalLabel
    installed_at          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    version               = "3.0"
} | ConvertTo-Json
Set-Content -Path $ConfigFile -Value $Config -Encoding UTF8
Write-Host "    [+] Config written: $ConfigFile" -ForegroundColor Green

# ─── STEP 4: DOWNLOAD PYTHON COLLECTOR ───────────────────────────────────────
Write-Host ""
Write-Host "[4] Downloading collector from repo..." -ForegroundColor Yellow
Write-Host "    URL: $CollectorUrl" -ForegroundColor Gray

try {
    Invoke-WebRequest -Uri $CollectorUrl -OutFile $CollectorDst -UseBasicParsing
    $fileSize = (Get-Item $CollectorDst).Length
    if ($fileSize -lt 1000) {
        Write-Host "[-] Download too small ($fileSize bytes) — possible network error." -ForegroundColor Red
        exit 1
    }
    Write-Host "    [+] Downloaded: $CollectorDst ($fileSize bytes)" -ForegroundColor Green
} catch {
    Write-Host "[-] Download failed: $_" -ForegroundColor Red
    exit 1
}

# ─── STEP 5: CREATE SCHEDULED TASK ───────────────────────────────────────────
Write-Host ""
Write-Host "[5] Creating Scheduled Task: $TaskName (interval=$IntervalLabel)..." -ForegroundColor Yellow

# Remove existing task
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action    = New-ScheduledTaskAction `
    -Execute $PythonWExe `
    -Argument "`"$CollectorDst`"" `
    -WorkingDirectory $InstallDir

# Primary trigger: at logon
$TriggerLogon = New-ScheduledTaskTrigger -AtLogon

# Repetition trigger: repeat every N minutes indefinitely
$TriggerBoot  = New-ScheduledTaskTrigger -AtStartup
$TriggerBoot.Repetition = New-Object Microsoft.Management.Infrastructure.CimInstance('MSFT_TaskRepetitionPattern', 'Root/Microsoft/Windows/TaskScheduler')
$TriggerBoot.Repetition.Interval  = "PT${RepeatMins}M"
$TriggerBoot.Repetition.StopAtDurationEnd = $false

$Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited
$Settings  = New-ScheduledTaskSettingsSet `
    -Hidden `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes $RepeatMins)

# Register with both triggers
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger @($TriggerLogon, $TriggerBoot) `
        -Principal $Principal `
        -Settings $Settings | Out-Null
    Write-Host "    [+] Task registered with repeat interval: $IntervalLabel" -ForegroundColor Green
} catch {
    # Fallback: logon only
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $TriggerLogon `
        -Principal $Principal | Out-Null
    Set-ScheduledTask -TaskName $TaskName -Settings $Settings | Out-Null
    Write-Host "    [+] Task registered (logon trigger, interval enforced by Python loop)" -ForegroundColor Yellow
}

# ─── STEP 6: STARTUP SHORTCUT ────────────────────────────────────────────────
Write-Host ""
Write-Host "[6] Creating All-Users startup shortcut..." -ForegroundColor Yellow
$StartupDir   = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$ShortcutPath = Join-Path $StartupDir "WazuhBrowserMonitorP2.lnk"
$WShell = New-Object -ComObject WScript.Shell
$SC = $WShell.CreateShortcut($ShortcutPath)
$SC.TargetPath       = $PythonWExe
$SC.Arguments        = "`"$CollectorDst`""
$SC.WorkingDirectory = $InstallDir
$SC.Save()
Write-Host "    [+] Shortcut: $ShortcutPath" -ForegroundColor Green

# ─── STEP 7: WAZUH OSSEC.CONF ────────────────────────────────────────────────
Write-Host ""
Write-Host "[7] Updating Wazuh ossec.conf..." -ForegroundColor Yellow
$Marker = "<!-- BROWSER_MONITOR_P2 -->"

if (Test-Path $WazuhConf) {
    $Content = Get-Content $WazuhConf -Raw
    if ($Content -notmatch [regex]::Escape($Marker)) {
        $Block = @"

  <!-- BROWSER_MONITOR_P2 -->
  <localfile>
    <location>$LogFile</location>
    <log_format>syslog</log_format>
  </localfile>
"@
        $Content = $Content -replace "</ossec_config>", "$Block`n</ossec_config>"
        Set-Content -Path $WazuhConf -Value $Content -Encoding UTF8
        Write-Host "    [+] localfile block added" -ForegroundColor Green
        Restart-Service -Name $WazuhSvc -ErrorAction SilentlyContinue
        Start-Sleep 3
        $svc = Get-Service $WazuhSvc -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Host "    [+] Wazuh agent restarted — Running" -ForegroundColor Green
        }
    } else {
        Write-Host "    [=] Already configured — skipping" -ForegroundColor Gray
    }
} else {
    Write-Host "    [!] ossec.conf not found at $WazuhConf" -ForegroundColor Yellow
    Write-Host "        Add manually inside <ossec_config>:" -ForegroundColor Yellow
    Write-Host "          <localfile>" -ForegroundColor Gray
    Write-Host "            <location>$LogFile</location>" -ForegroundColor Gray
    Write-Host "            <log_format>syslog</log_format>" -ForegroundColor Gray
    Write-Host "          </localfile>" -ForegroundColor Gray
}

# ─── STEP 8: START NOW ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "[8] Starting monitoring now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

if (Test-Path $LogFile) {
    $lines = (Get-Content $LogFile -ErrorAction SilentlyContinue).Count
    Write-Host "    [+] Log file active: $LogFile ($lines lines)" -ForegroundColor Green
} else {
    Write-Host "    [~] Log file will appear after first browser visit (up to $IntervalLabel)" -ForegroundColor Yellow
}

# ─── DONE ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  [SUCCESS] Phase 2 Deployment Complete!                 ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Collector   : $CollectorDst"
Write-Host "  Config      : $ConfigFile"
Write-Host "  Log file    : $LogFile"
Write-Host "  Task        : $TaskName (interval=$IntervalLabel, hidden at logon + startup)"
Write-Host ""
Write-Host "  Watch live logs:"
Write-Host "    Get-Content '$LogFile' -Tail 20 -Wait" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Change interval (re-run installer or edit $ConfigFile)"
Write-Host "  Repo: https://github.com/Ramkumar2545/browsing-monitoring-history-phases-2" -ForegroundColor Cyan
Write-Host ""
