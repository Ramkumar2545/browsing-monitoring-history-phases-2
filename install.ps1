<#
.SYNOPSIS
    Wazuh Browser Monitor Phase 2 - Windows One-Line Installer
    Author  : Ram Kumar G (IT Fortress)
    Version : 3.0 (Phase 2 - Configurable Interval)

.DESCRIPTION
    Downloads the Phase 2 collector from GitHub and installs it.
    Prompts for scan interval during installation.
    Registers a Scheduled Task with AtLogon + Repeat triggers.
    Updates Wazuh ossec.conf automatically.

    REQUIREMENTS:
      1. Run as Administrator.
      2. Python 3.8+ installed System-Wide (Install for All Users + Add to PATH).

.USAGE
    powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iwr -UseBasicParsing 'https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main/install.ps1' | iex"
#>

$REPO_RAW     = "https://raw.githubusercontent.com/Ramkumar2545/browsing-monitoring-history-phases-2/main"
$InstallDir   = "C:\BrowserMonitor"
$ScriptName   = "browser-history-monitor.py"
$ConfigName   = ".browser_monitor_config.json"
$TaskName     = "BrowserHistoryMonitor"
$LogFile      = "$InstallDir\browser_history.log"
$WazuhConf    = "C:\Program Files (x86)\ossec-agent\ossec.conf"
$WazuhSvc     = "WazuhSvc"
$DestScript   = "$InstallDir\$ScriptName"
$DestConfig   = "$InstallDir\$ConfigName"

# ─── BANNER ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Wazuh Browser Monitor Phase 2 - Windows Installer           ║" -ForegroundColor Cyan
Write-Host "║  IT Fortress | Configurable Interval | Task Scheduler        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── ADMIN CHECK ──────────────────────────────────────────────────────────────
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] ERROR: Run this script as Administrator." -ForegroundColor Red
    exit 1
}

# ─── STEP 1: PYTHON DETECTION ─────────────────────────────────────────────────
Write-Host "[1] Detecting Python (System-Wide)..." -ForegroundColor Yellow
$PythonExe  = $null
$CommonPaths = @(
    "C:\Program Files\Python313\python.exe",
    "C:\Program Files\Python312\python.exe",
    "C:\Program Files\Python311\python.exe",
    "C:\Program Files\Python310\python.exe",
    "C:\Program Files (x86)\Python312\python.exe",
    "C:\Python312\python.exe",
    "C:\Python311\python.exe"
)
foreach ($path in $CommonPaths) {
    if (Test-Path $path) { $PythonExe = $path; Write-Host "    [+] Found: $path" -ForegroundColor Green; break }
}
if (-not $PythonExe) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*\Users\*") { $PythonExe = $cmd.Source; Write-Host "    [+] Found via PATH: $PythonExe" -ForegroundColor Green }
}
if (-not $PythonExe) {
    Write-Host "[-] Python not found. Install Python 3.x from https://python.org (Install for All Users + Add to PATH)" -ForegroundColor Red
    exit 1
}
$PyDir      = Split-Path $PythonExe -Parent
$PythonWExe = Join-Path $PyDir "pythonw.exe"
if (-not (Test-Path $PythonWExe)) { $PythonWExe = $PythonExe }
Write-Host "    [+] Windowless Python: $PythonWExe" -ForegroundColor Green

# ─── STEP 2: INTERVAL SELECTION ───────────────────────────────────────────────
Write-Host ""
Write-Host "[2] Select scan interval:" -ForegroundColor Yellow
Write-Host "     1)  1  minute   (high I/O)" -ForegroundColor Gray
Write-Host "     2)  5  minutes" -ForegroundColor Gray
Write-Host "     3)  10 minutes" -ForegroundColor Gray
Write-Host "     4)  20 minutes" -ForegroundColor Gray
Write-Host "     5)  30 minutes  (recommended)" -ForegroundColor Cyan
Write-Host "     6)  60 minutes / 1 hour" -ForegroundColor Gray
Write-Host "     7)  2  hours" -ForegroundColor Gray
Write-Host "     8)  6  hours" -ForegroundColor Gray
Write-Host "     9)  12 hours" -ForegroundColor Gray
Write-Host "    10)  24 hours    (once per day)" -ForegroundColor Gray
Write-Host ""
$choice = Read-Host "    Enter choice [1-10] (default: 5 = 30 minutes)"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "5" }

$IntervalMap = @{
    "1"  = @{ Secs = 60;    Label = "1m";  Mins = 1   }
    "2"  = @{ Secs = 300;   Label = "5m";  Mins = 5   }
    "3"  = @{ Secs = 600;   Label = "10m"; Mins = 10  }
    "4"  = @{ Secs = 1200;  Label = "20m"; Mins = 20  }
    "5"  = @{ Secs = 1800;  Label = "30m"; Mins = 30  }
    "6"  = @{ Secs = 3600;  Label = "60m"; Mins = 60  }
    "7"  = @{ Secs = 7200;  Label = "2h";  Mins = 120 }
    "8"  = @{ Secs = 21600; Label = "6h";  Mins = 360 }
    "9"  = @{ Secs = 43200; Label = "12h"; Mins = 720 }
    "10" = @{ Secs = 86400; Label = "24h"; Mins = 1440}
}
if (-not $IntervalMap.ContainsKey($choice)) { $choice = "5" }
$SECS       = $IntervalMap[$choice].Secs
$LABEL      = $IntervalMap[$choice].Label
$MINS       = $IntervalMap[$choice].Mins
$RepeatMins = if ($MINS -ge 1440) { "1440" } else { "$MINS" }
Write-Host "    [+] Selected: $LABEL ($SECS seconds)" -ForegroundColor Green

# ─── STEP 3: CREATE INSTALL DIR ───────────────────────────────────────────────
Write-Host ""
Write-Host "[3] Creating $InstallDir..." -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }
$Acl = Get-Acl $InstallDir
$Ar  = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users","Modify","ContainerInherit,ObjectInherit","None","Allow")
$Acl.SetAccessRule($Ar); Set-Acl $InstallDir $Acl
Write-Host "    [+] Permissions set (BUILTIN\Users: Modify)" -ForegroundColor Green

# ─── STEP 4: DOWNLOAD COLLECTOR ───────────────────────────────────────────────
Write-Host ""
Write-Host "[4] Downloading Phase 2 collector..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    Invoke-WebRequest -UseBasicParsing "$REPO_RAW/collector/browser-history-monitor.py" -OutFile $DestScript
    Write-Host "    [+] Downloaded: $DestScript" -ForegroundColor Green
} catch {
    Write-Host "[-] Download failed: $_" -ForegroundColor Red; exit 1
}

# ─── STEP 5: WRITE CONFIG ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "[5] Writing interval config..." -ForegroundColor Yellow
$ConfigJson = "{`"scan_interval_seconds`": $SECS, `"scan_interval_label`": `"$LABEL`"}"
Set-Content -Path $DestConfig -Value $ConfigJson -Encoding UTF8
Write-Host "    [+] Config: $DestConfig  [$LABEL = $SECS s]" -ForegroundColor Green

# ─── STEP 6: SCHEDULED TASK WITH REPEAT TRIGGER ───────────────────────────────
Write-Host ""
Write-Host "[6] Creating Scheduled Task: $TaskName (AtLogon + Repeat every $RepeatMins min)..." -ForegroundColor Yellow

$Action    = New-ScheduledTaskAction -Execute $PythonWExe -Argument "`"$DestScript`"" -WorkingDirectory $InstallDir
$Trigger   = New-ScheduledTaskTrigger -AtLogon
$Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited
$Settings  = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartInterval (New-TimeSpan -Minutes $RepeatMins) -RestartCount 9999

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null
Set-ScheduledTask -TaskName $TaskName -Settings $Settings | Out-Null

# Inject RepetitionInterval into the XML for native Task Scheduler repeat
$TaskXml  = (Export-ScheduledTask -TaskName $TaskName)
$RepeatPT = "PT${RepeatMins}M"
$TaskXml  = $TaskXml -replace "(<Triggers>.*?<AtLogon>.*?</AtLogon>)(.*?</Triggers>)", `
    "<Triggers><AtLogon><Repetition><Interval>$RepeatPT</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></AtLogon></Triggers>"
$TaskXml | Register-ScheduledTask -TaskName $TaskName -Force | Out-Null

Write-Host "    [+] Scheduled Task registered (AtLogon + repeat every $RepeatMins min)" -ForegroundColor Green

# ─── STEP 7: STARTUP SHORTCUT FAILSAFE ────────────────────────────────────────
Write-Host ""
Write-Host "[7] Creating startup shortcut (failsafe)..." -ForegroundColor Yellow
$StartupDir   = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$ShortcutPath = Join-Path $StartupDir "WazuhBrowserMonitor.lnk"
$WShell = New-Object -ComObject WScript.Shell
$SC = $WShell.CreateShortcut($ShortcutPath)
$SC.TargetPath = $PythonWExe; $SC.Arguments = "`"$DestScript`""; $SC.WorkingDirectory = $InstallDir; $SC.Save()
Write-Host "    [+] Shortcut: $ShortcutPath" -ForegroundColor Green

# ─── STEP 8: WAZUH OSSEC.CONF ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[8] Updating Wazuh ossec.conf..." -ForegroundColor Yellow
$Marker = "<!-- BROWSER_MONITOR_P2 -->"
if (Test-Path $WazuhConf) {
    $Content = Get-Content $WazuhConf -Raw
    if ($Content -notmatch [regex]::Escape($Marker)) {
        $Block = "`n  <!-- BROWSER_MONITOR_P2 -->`n  <localfile>`n    <location>$LogFile</location>`n    <log_format>syslog</log_format>`n  </localfile>"
        $Content = $Content -replace "</ossec_config>", "$Block`n</ossec_config>"
        Set-Content -Path $WazuhConf -Value $Content -Encoding UTF8
        Write-Host "    [+] localfile block added" -ForegroundColor Green
        Restart-Service -Name $WazuhSvc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svc = Get-Service $WazuhSvc -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Write-Host "    [+] Wazuh agent: Running" -ForegroundColor Green }
        else { Write-Host "    [!] Wazuh agent may need manual restart." -ForegroundColor Yellow }
    } else { Write-Host "    [=] localfile block already present" -ForegroundColor Gray }
} else {
    Write-Host "    [!] ossec.conf not found at $WazuhConf — add localfile block manually." -ForegroundColor Yellow
    Write-Host "    Location: $LogFile  Format: syslog"
}

# ─── STEP 9: START NOW ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[9] Starting collector now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Write-Host "    [+] Task started" -ForegroundColor Green

# ─── DONE ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  [SUCCESS] Phase 2 Installation Complete!                    ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Interval : $LABEL ($SECS seconds)"
Write-Host "  Log file : $LogFile"
Write-Host "  Watch    : Get-Content '$LogFile' -Tail 20 -Wait" -ForegroundColor Cyan
Write-Host "  Task     : Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
Write-Host ""
