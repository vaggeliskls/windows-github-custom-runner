# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Everything is driven by environment variables: the Dockerfile sets the
# GITHUB_RUNNER_* defaults and .env supplies the rest (see README).
require "socket"

cpu_count   = (ENV["CPU"] || 4).to_i
memory_size = (ENV["MEMORY"] || 8000).to_i
disk_size   = (ENV["DISK_SIZE"] || 100).to_i
privileged  = (ENV["PRIVILEGED"] || "true") == "true"
interactive = (ENV["INTERACTIVE"] || "true") == "true"

runners        = (ENV["RUNNERS"] || 1).to_i
runner_url     = ENV["RUNNER_URL"].to_s
runner_version = ENV["GITHUB_RUNNER_VERSION"].to_s
runner_name    = ENV["GITHUB_RUNNER_NAME"] || "windows_x64_vagrant"
runner_labels  = ENV["GITHUB_RUNNER_LABELS"] || "windows,win_x64,windows_x64,windows_vagrant_action"
runner_file    = "actions-runner-win-x64-#{runner_version}.zip"
runner_pkg_url = ENV["GITHUB_RUNNER_URL"] || "https://github.com/actions/runner/releases/download/v#{runner_version}/#{runner_file}"
pat            = ENV["PAT"].to_s
token          = ENV["TOKEN"].to_s

# Runner names must be stable across container restarts so `config.cmd --replace`
# reuses the existing registration instead of leaving offline duplicates in GitHub.
# The container hostname is the stable part; set `hostname:` in docker-compose.yml.
host_id = ENV["HOSTNAME"] || Socket.gethostname

abort "RUNNER_URL must be set to an org (https://github.com/<org>) or repo (https://github.com/<org>/<repo>) URL" if runner_url.empty?
abort "GITHUB_RUNNER_VERSION must be set" if runner_version.empty?
abort "Set PAT or TOKEN so the runners can register" if pat.empty? && token.empty?
auth_arg = pat.empty? ? "--token #{token}" : "--pat #{pat}"

Vagrant.configure("2") do |config|
    config.vm.box = ENV["VAGRANT_BOX"] || "peru/windows-server-2022-standard-x64-eval"
    config.vm.box_check_update = false
    config.vm.network "forwarded_port", guest: 22,   host: 2222, id: "ssh"
    config.vm.network "forwarded_port", guest: 3389, host: 3389, id: "rdp"

    config.vm.provider "libvirt" do |libvirt|
        libvirt.driver = ENV["LIBVIRT_DRIVER"] || "kvm"
        libvirt.memory = memory_size
        libvirt.cpus = cpu_count
        libvirt.machine_virtual_size = disk_size
        libvirt.forward_ssh_port = true
    end
    config.winrm.max_tries = 300 # default is 20
    config.winrm.retry_delay = 5 # seconds (default)

    config.vm.provision "shell", inline: "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"
    config.vm.provision "shell", powershell_elevated_interactive: interactive, privileged: privileged, inline: <<~SHELL
        # PowerShell 7 and Chocolatey (also pulls in 7-Zip)
        Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -AddToPath"
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        choco install 7zip.install git.install jq -y
        # Work from C:\\
        Set-Location /
        # Visual Studio 2022 Enterprise, native desktop (C++) workload.
        # The bootstrapper returns immediately unless told to wait, which would let
        # runners register and pick up jobs before the toolchain exists.
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_enterprise.exe" -OutFile "vs_enterprise.exe"
        Start-Process -FilePath ".\\vs_enterprise.exe" -ArgumentList "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended" -Wait
        Remove-Item -Path ./vs_enterprise.exe
        # Rtools 4.0 + mingw-w64 make
        Invoke-WebRequest -Uri "https://cran.r-project.org/bin/windows/Rtools/rtools40-x86_64.exe" -OutFile "rtools.exe"
        Start-Process "./rtools.exe" -ArgumentList "/Silent" -PassThru -Wait
        [Environment]::SetEnvironmentVariable("PATH", $env:Path + ";C:\\rtools40\\usr\\bin;C:\\rtools40\\mingw64\\bin", [EnvironmentVariableTarget]::Machine)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        C:\\rtools40\\msys2.exe pacman -Sy --noconfirm mingw-w64-x86_64-make
        Remove-Item -Path ./rtools.exe
        # Grow C: to the full virtual disk
        Resize-Partition -DriveLetter "C" -Size (Get-PartitionSupportedSize -DriveLetter "C").SizeMax
        # Enable long paths
        New-ItemProperty -Path "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
        # GitHub Actions runners: one directory each, run as the vagrant user
        $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @("VAGRANTVM\\vagrant", (ConvertTo-SecureString -String "vagrant" -AsPlainText -Force))
        Invoke-WebRequest -Uri "#{runner_pkg_url}" -OutFile "#{runner_file}"
        Remove-Item -Path C:\\runner-* -Recurse -Force -ErrorAction SilentlyContinue
        for ($i = 1; $i -le #{runners}; $i++) {
            $dir = "C:\\runner-$i"
            Write-Host "Configuring runner $i of #{runners} in $dir"
            Expand-Archive -LiteralPath "#{runner_file}" -DestinationPath $dir -Force
            & "$dir\\config.cmd" --unattended --replace --name "#{runner_name}_#{host_id}_$i" --url "#{runner_url}" --labels "#{runner_labels}" #{auth_arg}
            Start-Process -FilePath "$dir\\run.cmd" -Credential $credentials
        }
        Remove-Item -Path "#{runner_file}"
    SHELL
end
