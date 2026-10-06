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
    [switch]$RunnersOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is much faster without the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Share = '\\host.lan\Data'
$LogFile = 'C:\OEM\install.log'
$Temp = Join-Path $env:TEMP 'runner-install'
$RebootRequired = $false

function Write-Log([string]$Message) {
    Write-Host ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message)
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

function Find-Config {
    if ($ConfigPath) { return $ConfigPath }
    $candidates = @("$Share\runner.env", 'Z:\runner.env', 'C:\OEM\runner.env')
    # The samba share can take a moment to become reachable after first logon.
    $deadline = (Get-Date).AddMinutes(5)
    do {
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    throw "runner.env not found (looked in $($candidates -join ', ')). Check the volumes in docker-compose.yml."
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

function Install-BaseTools {
    Write-Log 'Installing PowerShell 7'
    Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -UseMSI -Quiet"

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log 'Installing Chocolatey'
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Update-ProcessPath
    }

    Write-Log 'Installing Git, jq, 7-Zip'
    choco install -y --no-progress git.install jq 7zip.install
    if ($LASTEXITCODE -notin 0, 1641, 3010) { throw "choco install failed with exit code $LASTEXITCODE" }
    Update-ProcessPath
    git config --system core.longpaths true
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
    & 'C:\rtools40\usr\bin\pacman.exe' -Sy --noconfirm mingw-w64-x86_64-make
    if ($LASTEXITCODE -ne 0) { throw "pacman failed with exit code $LASTEXITCODE" }
}

# --- Runners -----------------------------------------------------------------

function Resolve-RunnerVersion([string]$Version) {
    if ($Version) { return $Version.TrimStart('v') }
    Write-Log 'GITHUB_RUNNER_VERSION not set, using the latest actions/runner release'
    $release = Invoke-RestMethod 'https://api.github.com/repos/actions/runner/releases/latest' -Headers @{ 'User-Agent' = 'windows-github-custom-runner' }
    return $release.tag_name.TrimStart('v')
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

    $names = @()
    for ($i = 1; $i -le $count; $i++) {
        $dir = "C:\runner-$i"
        $name = "${prefix}_${hostId}_$i"
        $names += $name
        Write-Log "Configuring runner $i of ${count}: $name in $dir"

        # A previous registration (re-run) is removed first so --replace has nothing stale to fight.
        if (Test-Path -LiteralPath "$dir\.runner") {
            Write-Log 'Removing the previous registration'
            & "$dir\config.cmd" remove --unattended @auth | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Log "config.cmd remove exited with $LASTEXITCODE, continuing" }
        }
        Get-ScheduledTask -TaskName "GitHub runner $i" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force

        $cfgArgs = @('--unattended', '--replace', '--name', $name, '--url', $url, '--labels', $labels) + $auth
        if ($group) { $cfgArgs += @('--runnergroup', $group) }
        if ($mode -eq 'service') {
            $cfgArgs += @('--runasservice', '--windowslogonaccount', $serviceAccount)
            if (-not $builtinAccount) { $cfgArgs += @('--windowslogonpassword', $servicePassword) }
        }
        & "$dir\config.cmd" @cfgArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "config.cmd failed for $name with exit code $LASTEXITCODE" }

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

Start-Transcript -Path $LogFile -Append | Out-Null
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
$status = 'failed'
try {
    $configFile = Find-Config
    Write-Log "Using settings from $configFile"
    $config = Read-EnvFile $configFile

    if (-not $RunnersOnly) {
        Initialize-System
        Install-BaseTools
        if (Test-Enabled $config 'INSTALL_VISUAL_STUDIO') {
            Install-VisualStudio (Get-Setting $config 'VS_EDITION' 'enterprise') (Get-Setting $config 'VS_WORKLOADS' 'Microsoft.VisualStudio.Workload.NativeDesktop')
        }
        if (Test-Enabled $config 'INSTALL_RTOOLS') { Install-Rtools }
    }

    $result = Install-Runners $config

    # Only the fallback location is on the Windows disk; do not leave a PAT there.
    if ($configFile -ieq 'C:\OEM\runner.env') { Remove-Item -LiteralPath $configFile -Force }

    $status = 'done'
    Write-Log "Registered $($result.Names.Count) runner(s), actions/runner $($result.Version), mode $($result.Mode): $($result.Names -join ', ')"
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

    # Report back to the host through the shared folder (./shared)
    try {
        Copy-Item -LiteralPath $LogFile -Destination "$Share\install.log" -Force
        Remove-Item -LiteralPath "$Share\install.done", "$Share\install.failed" -Force -ErrorAction SilentlyContinue
        Set-Content -Path "$Share\install.$status" -Value (Get-Date -Format o)
    } catch {
        Write-Host "Could not write to $Share ($_)"
    }
}

if ($status -ne 'done') { exit 1 }
