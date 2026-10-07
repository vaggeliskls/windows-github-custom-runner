<#
.SYNOPSIS
    Turns a dockur/windows guest into one or more GitHub Actions runners.

.DESCRIPTION
    dockur/windows copies the /oem folder to C:\OEM and runs C:\OEM\install.bat
    once, at the end of the unattended installation, as the auto-logon
    administrator (its answer file disables UAC and the firewall). install.bat
    hands over to this script, which installs the build toolchain and registers
    the runners.

    Settings come from runner.env, a KEY=VALUE file with the layout of the
    repo's .env. docker-compose.yml bind-mounts .env to /shared/runner.env,
    which the guest sees as \\host.lan\Data\runner.env (drive Z:). Nothing
    secret is placed in /oem because dockur bakes that folder into the install
    ISO it keeps in /storage.

    Progress is written to C:\OEM\install.log and copied to the shared folder
    together with an install.done or install.failed marker.

    The first run registers a "GitHub runner setup" scheduled task that runs
    this script with -AtLogon at every logon. That run repeats the install when
    a previous run did not finish (wrong PAT, download failure, ...) or
    re-registers the runners when runner.env changed, so fixing .env on the
    host and restarting the container is enough. It does nothing otherwise.

.EXAMPLE
    # Re-run from an RDP session after changing runner.env (RUNNERS, labels,
    # version, ...). Skips the toolchain and re-registers the runners.
    powershell -ExecutionPolicy Bypass -File C:\OEM\install.ps1 -RunnersOnly
#>
[CmdletBinding()]
param(
    # Path to runner.env. Default: the shared folder, then C:\OEM\runner.env.
    [string]$ConfigPath,

    # Skip Chocolatey, Visual Studio and Rtools; only (re)configure the runners.
    [switch]$RunnersOnly,

    # Used by the "GitHub runner setup" scheduled task. Runs only when the
    # toolchain install never finished or runner.env changed since the runners
    # were last registered; exits quietly otherwise.
    [switch]$AtLogon
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is much faster without the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Share = '\\host.lan\Data'
$LogFile = 'C:\OEM\install.log'            # last real run
$LogonLogFile = 'C:\OEM\install-logon.log' # last logon check that found nothing to do
$ConfigMarker = 'C:\OEM\runner.env.sha256'  # hash of the runner.env the runners were last registered from
$SetupTask = 'GitHub runner setup'
$Temp = Join-Path $env:TEMP 'runner-install'
$RebootRequired = $false

function Write-Log([string]$Message) {
    Write-Host ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message)
}

# Runs a native command so that its stdout and stderr end up in the transcript
# as well as on the console. Windows PowerShell does not record output a program
# writes straight to the console, and 2>&1 under ErrorActionPreference=Stop
# would abort the run at the first stderr line. Returns the exit code.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
    return $LASTEXITCODE
}

# Appends whatever the transcript gained to the copy in the shared folder every
# 2 seconds, so the host sees the same log as the console and 'tail -f' keeps
# working: the copy only grows, it is never rewritten.
function Start-LogMirror {
    $from = $LogFile
    $to = "$Share\install.log"
    Remove-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
    return Start-Job -ScriptBlock {
        $offset = 0
        while ($true) {
            try {
                $src = [IO.File]::Open($using:from, 'Open', 'Read', 'ReadWrite')
                try {
                    if ($src.Length -gt $offset) {
                        $buffer = New-Object byte[] ($src.Length - $offset)
                        $src.Seek($offset, 'Begin') | Out-Null
                        $read = $src.Read($buffer, 0, $buffer.Length)
                        $dst = [IO.File]::Open($using:to, 'Append', 'Write', 'Read')
                        try { $dst.Write($buffer, 0, $read) } finally { $dst.Close() }
                        $offset += $read
                    }
                } finally { $src.Close() }
            } catch { Write-Verbose "$_" }
            Start-Sleep -Seconds 2
        }
    }
}

function Update-ProcessPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Add-MachinePath([string[]]$Dirs) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine').Split(';') | Where-Object { $_ }
    $new = @($current) + @($Dirs | Where-Object { $current -notcontains $_ })
    [Environment]::SetEnvironmentVariable('Path', ($new -join ';'), 'Machine')
    Update-ProcessPath
}

# KEY=VALUE lines; blank lines and # comments ignored; surrounding quotes stripped.
function Read-EnvFile([string]$Path) {
    $cfg = @{}
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val.Length -ge 2 -and (($val[0] -eq '"' -and $val[-1] -eq '"') -or ($val[0] -eq "'" -and $val[-1] -eq "'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $cfg[$key] = $val
    }
    return $cfg
}

# Returns the path of runner.env, or $null with -Optional when there is none.
function Find-Config([switch]$Optional) {
    if ($ConfigPath) { return $ConfigPath }
    $candidates = @("$Share\runner.env", 'Z:\runner.env', 'C:\OEM\runner.env')
    # The samba share can take a moment to become reachable after logon.
    $deadline = (Get-Date).AddMinutes(5)
    do {
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            # Docker creates a missing bind-mount source as an empty directory, so a
            # folder here means .env did not exist on the host when compose started.
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                throw "$candidate is a directory, not a file. .env was missing on the host when 'docker compose up' ran: remove the .env directory, create .env from .env.example, then 'docker compose down' and 'docker compose up -d'."
            }
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    if ($Optional) { return $null }
    throw "runner.env not found (looked in $($candidates -join ', ')). Check the volumes in docker-compose.yml."
}

function Get-ConfigHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Re-runs this script with -AtLogon at every logon of the auto-logon user, so a
# corrected or changed runner.env is applied by restarting the container.
function Register-SetupTask {
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -AtLogon"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $settings.ExecutionTimeLimit = 'PT0S' # a full install can take over an hour
    Register-ScheduledTask -TaskName $SetupTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Get-Setting($Config, [string]$Key, $Default = '') {
    if ($Config.ContainsKey($Key) -and $Config[$Key] -ne '') { return $Config[$Key] }
    return $Default
}

function Test-Enabled($Config, [string]$Key, [bool]$Default = $true) {
    $value = (Get-Setting $Config $Key ($Default.ToString())).ToLower()
    return $value -in 'true', '1', 'yes', 'y'
}

function Invoke-Download([string]$Uri, [string]$OutFile) {
    Write-Log "Downloading $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

# --- Toolchain ---------------------------------------------------------------

function Initialize-System {
    Write-Log 'Enabling long paths'
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force | Out-Null

    # Grow C: when DISK_SIZE is larger than the partition dockur created
    try {
        $max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
        $cur = (Get-Partition -DriveLetter C).Size
        if (($max - $cur) -gt 1GB) {
            Write-Log 'Growing C: to the full virtual disk'
            Resize-Partition -DriveLetter C -Size $max
        }
    } catch {
        Write-Log "Could not resize C: ($_)"
    }
}

function Test-VisualStudio {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    return [bool](& $vswhere -products * -version '[17.0,18.0)' -property installationPath)
}

# Names of the toolchain parts that are not installed yet. Decides whether a
# logon run has anything to do and which installers Install-Toolchain runs.
function Get-MissingTools($Config) {
    Update-ProcessPath
    $checks = [ordered]@{
        'PowerShell 7' = { Test-Path -LiteralPath "$env:ProgramFiles\PowerShell\7\pwsh.exe" }
        'Chocolatey'   = { [bool](Get-Command choco -ErrorAction SilentlyContinue) }
        'Git'          = { [bool](Get-Command git -ErrorAction SilentlyContinue) }
        'jq'           = { [bool](Get-Command jq -ErrorAction SilentlyContinue) }
        '7-Zip'        = { Test-Path -LiteralPath "$env:ProgramFiles\7-Zip\7z.exe" }
    }
    if (Test-Enabled $Config 'INSTALL_VISUAL_STUDIO') { $checks['Visual Studio'] = { Test-VisualStudio } }
    if (Test-Enabled $Config 'INSTALL_RTOOLS') {
        $checks['Rtools'] = { (Test-Path -LiteralPath 'C:\rtools40\usr\bin\pacman.exe') -and (Test-Path -LiteralPath 'C:\rtools40\mingw64\bin\mingw32-make.exe') }
    }
    return @($checks.Keys | Where-Object { -not (& $checks[$_]) })
}

function Install-Toolchain($Config, [string[]]$Missing) {
    if ($Missing -contains 'PowerShell 7') {
        Write-Log 'Installing PowerShell 7'
        Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -UseMSI -Quiet"
    }

    if ($Missing -contains 'Chocolatey') {
        Write-Log 'Installing Chocolatey'
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Update-ProcessPath
    }

    $packages = @{ 'Git' = 'git.install'; 'jq' = 'jq'; '7-Zip' = '7zip.install' }
    $wanted = @($packages.Keys | Where-Object { $Missing -contains $_ } | ForEach-Object { $packages[$_] })
    if ($wanted) {
        Write-Log "Installing $($wanted -join ', ') with Chocolatey"
        $code = Invoke-Native 'choco' (@('install', '-y', '--no-progress') + $wanted)
        if ($code -notin 0, 1641, 3010) { throw "choco install failed with exit code $code" }
        Update-ProcessPath
        Invoke-Native 'git' @('config', '--system', 'core.longpaths', 'true') | Out-Null
    }

    if ($Missing -contains 'Visual Studio') {
        Install-VisualStudio (Get-Setting $Config 'VS_EDITION' 'enterprise') (Get-Setting $Config 'VS_WORKLOADS' 'Microsoft.VisualStudio.Workload.NativeDesktop')
    }
    if ($Missing -contains 'Rtools') { Install-Rtools }
}

function Install-VisualStudio([string]$Edition, [string]$Workloads) {
    $exe = Join-Path $Temp "vs_$Edition.exe"
    Invoke-Download "https://aka.ms/vs/17/release/vs_$Edition.exe" $exe

    $vsArgs = @('--quiet', '--wait', '--norestart', '--includeRecommended')
    foreach ($workload in ($Workloads -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $vsArgs += @('--add', $workload)
    }

    Write-Log "Installing Visual Studio 2022 $Edition with $Workloads (this takes a while)"
    $proc = Start-Process -FilePath $exe -ArgumentList $vsArgs -Wait -PassThru
    switch ($proc.ExitCode) {
        0 { Write-Log 'Visual Studio installed' }
        3010 { Write-Log 'Visual Studio installed, reboot required'; $script:RebootRequired = $true }
        default { throw "Visual Studio installer failed with exit code $($proc.ExitCode)" }
    }
}

function Install-Rtools {
    $exe = Join-Path $Temp 'rtools40.exe'
    Invoke-Download 'https://cran.r-project.org/bin/windows/Rtools/rtools40-x86_64.exe' $exe

    Write-Log 'Installing Rtools 4.0'
    $proc = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Rtools installer failed with exit code $($proc.ExitCode)" }
    Add-MachinePath 'C:\rtools40\usr\bin', 'C:\rtools40\mingw64\bin'

    Write-Log 'Installing mingw-w64-x86_64-make'
    $code = Invoke-Native 'C:\rtools40\usr\bin\pacman.exe' @('-Sy', '--noconfirm', 'mingw-w64-x86_64-make')
    if ($code -ne 0) { throw "pacman failed with exit code $code" }
}

# --- Runners -----------------------------------------------------------------

function Resolve-RunnerVersion([string]$Version) {
    if ($Version) { return $Version.TrimStart('v') }
    Write-Log 'GITHUB_RUNNER_VERSION not set, using the latest actions/runner release'
    # The releases/latest page redirects to the tag. Unlike the REST API this has
    # no rate limit, which an unauthenticated call shares with everyone behind
    # the same public IP (60 per hour).
    $request = [Net.WebRequest]::Create('https://github.com/actions/runner/releases/latest')
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $response = $request.GetResponse()
    try { $location = $response.Headers['Location'] } finally { $response.Close() }
    if ($location -notmatch '/tag/v?([\d.]+)$') { throw "Could not determine the latest actions/runner release from '$location'. Set GITHUB_RUNNER_VERSION in .env." }
    return $Matches[1]
}

# Interactive mode: run.cmd as a scheduled task in the auto-logon desktop session,
# restarted at every logon, so jobs can drive GUI tooling.
function Register-InteractiveRunner([int]$Index, [string]$Dir) {
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $taskName = "GitHub runner $Index"
    $action = New-ScheduledTaskAction -Execute "$Dir\run.cmd" -WorkingDirectory $Dir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $settings.ExecutionTimeLimit = 'PT0S' # no time limit
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
}

# Takes runner $Index out of GitHub (its service or scheduled task with it) and
# deletes its folder. Safe to call when there is nothing to remove.
function Remove-Runner([int]$Index, [string[]]$Auth) {
    $dir = "C:\runner-$Index"
    $task = Get-ScheduledTask -TaskName "GitHub runner $Index" -ErrorAction SilentlyContinue
    if ($task) {
        $task | Stop-ScheduledTask -ErrorAction SilentlyContinue
        $task | Unregister-ScheduledTask -Confirm:$false
    }
    # Interactive mode: the listener outlives its cmd window and holds files open
    Get-Process Runner.Listener -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir\*" } | Stop-Process -Force
    if (Test-Path -LiteralPath "$dir\.runner") {
        Write-Log 'Removing the previous registration'
        $code = Invoke-Native "$dir\config.cmd" (@('remove', '--unattended') + $Auth)
        if ($code -ne 0) { Write-Log "config.cmd remove exited with $code, continuing" }
    }
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
}

function Install-Runners($Config) {
    $url = Get-Setting $Config 'RUNNER_URL'
    $pat = Get-Setting $Config 'PAT'
    $token = Get-Setting $Config 'TOKEN'
    $count = [int](Get-Setting $Config 'RUNNERS' 1)
    $prefix = Get-Setting $Config 'GITHUB_RUNNER_NAME' 'windows_x64_dockur'
    $labels = Get-Setting $Config 'GITHUB_RUNNER_LABELS' 'windows,win_x64,windows_x64,windows_dockur_action'
    $group = Get-Setting $Config 'GITHUB_RUNNER_GROUP'
    $hostId = Get-Setting $Config 'RUNNER_HOST_ID' $env:COMPUTERNAME
    $mode = (Get-Setting $Config 'RUNNER_MODE' 'service').ToLower()
    $version = Resolve-RunnerVersion (Get-Setting $Config 'GITHUB_RUNNER_VERSION')

    if (-not $url) { throw 'RUNNER_URL must be set to https://github.com/<org> or https://github.com/<org>/<repo>' }
    if (-not $pat -and -not $token) { throw 'Set PAT or TOKEN in runner.env so the runners can register' }
    if ($mode -notin 'service', 'interactive') { throw "RUNNER_MODE must be 'service' or 'interactive', got '$mode'" }
    $auth = if ($pat) { @('--pat', $pat) } else { @('--token', $token) }

    # Service account: the auto-logon user unless RUNNER_SERVICE_ACCOUNT says otherwise.
    # config.cmd turns ".\user" into "<computer>\user" and grants it "Log on as a service".
    $serviceAccount = Get-Setting $Config 'RUNNER_SERVICE_ACCOUNT' ".\$env:USERNAME"
    $servicePassword = Get-Setting $Config 'WIN_PASSWORD' 'runner'
    $builtinAccount = $serviceAccount -like 'NT AUTHORITY\*' -or $serviceAccount -eq 'LocalSystem'

    $zip = Join-Path $Temp "actions-runner-win-x64-$version.zip"
    $pkgUrl = Get-Setting $Config 'GITHUB_RUNNER_URL' "https://github.com/actions/runner/releases/download/v$version/actions-runner-win-x64-$version.zip"
    Invoke-Download $pkgUrl $zip

    # Runners from a previous run: the first $count are replaced in place, any
    # above the new count (RUNNERS was lowered) are removed for good.
    $existing = @(Get-ChildItem -LiteralPath 'C:\' -Directory -Filter 'runner-*' | ForEach-Object { [int]($_.Name -replace '^runner-', '') })
    foreach ($i in ($existing | Where-Object { $_ -gt $count })) {
        Write-Log "Removing runner $i (RUNNERS is now $count)"
        Remove-Runner $i $auth
    }

    $names = @()
    for ($i = 1; $i -le $count; $i++) {
        $dir = "C:\runner-$i"
        $name = "${prefix}_${hostId}_$i"
        $names += $name
        Write-Log "Configuring runner $i of ${count}: $name in $dir"

        # A previous registration (re-run) is removed first so --replace has nothing stale to fight.
        Remove-Runner $i $auth
        Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force

        $cfgArgs = @('--unattended', '--replace', '--name', $name, '--url', $url, '--labels', $labels) + $auth
        if ($group) { $cfgArgs += @('--runnergroup', $group) }
        if ($mode -eq 'service') {
            $cfgArgs += @('--runasservice', '--windowslogonaccount', $serviceAccount)
            if (-not $builtinAccount) { $cfgArgs += @('--windowslogonpassword', $servicePassword) }
        }
        $code = Invoke-Native "$dir\config.cmd" $cfgArgs
        if ($code -ne 0) { throw "config.cmd failed for $name with exit code $code" }

        if ($mode -eq 'interactive') { Register-InteractiveRunner $i $dir }
    }
    Remove-Item -LiteralPath $zip -Force

    return @{ Version = $version; Mode = $mode; Names = $names }
}

# --- Main --------------------------------------------------------------------

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell'
}

# One transcript per run. A logon check writes to its own file so that a boot
# with nothing to do does not overwrite the log of the last real run.
Start-Transcript -Path $(if ($AtLogon) { $LogonLogFile } else { $LogFile }) | Out-Null
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
$status = 'failed'
$mirror = $null
try {
    # Registered before anything that can fail, so a bad runner.env still gets
    # a retry at the next boot. Not re-registered from the task itself.
    if (-not $AtLogon) { Register-SetupTask }

    $configFile = Find-Config -Optional:$AtLogon
    if (-not $configFile) {
        Write-Log 'runner.env not found, nothing to do'
        $status = 'skipped'
        return
    }
    $config = Read-EnvFile $configFile

    # What is left to do: toolchain parts that are not on the machine, and the
    # runners when runner.env differs from the one they were registered from.
    $missing = if ($RunnersOnly) { @() } else { @(Get-MissingTools $config) }
    $registerRunners = $true
    if ($AtLogon) {
        $applied = if (Test-Path -LiteralPath $ConfigMarker) { Get-Content -LiteralPath $ConfigMarker } else { '' }
        $registerRunners = (Get-ConfigHash $configFile) -ne $applied
        if (-not $missing -and -not $registerRunners) {
            $status = 'skipped'
            return
        }
    }
    # A real run from here on: switch to the main log, clear the old markers and
    # start mirroring the log to the host.
    if ($AtLogon) {
        Stop-Transcript | Out-Null
        Start-Transcript -Path $LogFile | Out-Null
    }
    Remove-Item -LiteralPath "$Share\install.done", "$Share\install.failed" -Force -ErrorAction SilentlyContinue
    $mirror = Start-LogMirror
    Write-Log "Using settings from $configFile"

    # Idempotent and quick; also grows C: after a DISK_SIZE change on the host.
    Initialize-System
    if ($RunnersOnly) { Write-Log 'Toolchain: skipped (-RunnersOnly)' }
    elseif ($missing) { Write-Log "Toolchain: installing $($missing -join ', ')"; Install-Toolchain $config $missing }
    else { Write-Log 'Toolchain: all present' }

    if ($registerRunners) {
        $result = Install-Runners $config
        Set-Content -LiteralPath $ConfigMarker -Value (Get-ConfigHash $configFile)
        Write-Log "Registered $($result.Names.Count) runner(s), actions/runner $($result.Version), mode $($result.Mode): $($result.Names -join ', ')"
    } else {
        Write-Log 'Runners: runner.env unchanged, left as they are'
    }

    # Only the fallback location is on the Windows disk; do not leave a PAT there.
    if ($configFile -ieq 'C:\OEM\runner.env') { Remove-Item -LiteralPath $configFile -Force }

    $status = 'done'
    if ($RebootRequired) {
        Write-Log 'Rebooting in 60 seconds to finish the Visual Studio installation'
        shutdown.exe /r /t 60 /c 'Finishing GitHub runner setup'
    }
} catch {
    Write-Log "FAILED: $_"
    Write-Log $_.ScriptStackTrace
} finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    if ($mirror) {
        Start-Sleep -Seconds 3 # one more pass of the mirror picks up the transcript footer
        $mirror | Stop-Job
        $mirror | Remove-Job -Force
    }

    # Report back to the host through the shared folder (./shared). A logon run
    # that found nothing to do leaves the previous log and marker alone.
    if ($status -ne 'skipped') {
        try {
            # Without a mirror (failed before the run started) the host has no log yet.
            if (-not $mirror) { Copy-Item -LiteralPath $LogFile -Destination "$Share\install.log" -Force }
            Remove-Item -LiteralPath "$Share\install.done", "$Share\install.failed" -Force -ErrorAction SilentlyContinue
            Set-Content -Path "$Share\install.$status" -Value (Get-Date -Format o)
        } catch {
            Write-Host "Could not write to $Share ($_)"
        }
    }
}

if ($status -eq 'failed') { exit 1 }
