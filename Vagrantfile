Vagrant.configure("2") do |config|

    config.vm.box = "${VAGRANT_BOX}"
    config.vm.network "private_network", ip: "192.168.121.10"
    config.vm.network "forwarded_port", guest: 445, host: 445
    config.vm.provision "shell", inline: "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"
    config.vm.provider "libvirt" do |libvirt|
        libvirt.memory = ${MEMORY}
        libvirt.cpus = ${CPU}
        libvirt.machine_virtual_size = ${DISK_SIZE}
        libvirt.forward_ssh_port = true
    end
    config.winrm.max_tries = 300 # default is 20
    config.winrm.retry_delay = 5 #seconds. This is the defaul value and just here for documentation.
    config.vm.provision "shell", powershell_elevated_interactive: ${INTERACTIVE}, privileged: ${PRIVILEGED}, inline: <<-SHELL
        # Install Chocolatey - Also Grabs 7Zip
        Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -AddToPath"
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        choco install 7zip.install git.install jq -y 
        # c:/ default location
        Set-Location /
        # Install build tools
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_enterprise.exe" -OutFile "vs_enterprise.exe"
        ./vs_enterprise.exe --quiet --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended # --passive
        # Install rtools40
        Invoke-WebRequest -Uri "https://cran.r-project.org/bin/windows/Rtools/rtools40-x86_64.exe" -OutFile "rtools.exe"
        Start-Process "./rtools.exe" -Argument "/Silent" -PassThru -Wait
        [Environment]::SetEnvironmentVariable("PATH", $env:Path + ";C:\\rtools40\\usr\\bin;C:\\rtools40\\mingw64\\bin", [EnvironmentVariableTarget]::Machine)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
        C:\\rtools40\\msys2.exe pacman -Sy --noconfirm mingw-w64-x86_64-make
        Remove-Item -Path ./rtools.exe
        # Resize disk
        Resize-Partition -DriveLetter "C" -Size (Get-PartitionSupportedSize -DriveLetter "C").SizeMax
        # Enable too long paths
        New-ItemProperty -Path "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
        $username = "VAGRANTVM\\vagrant"
        $password = "vagrant"
        $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username,(ConvertTo-SecureString -String $password -AsPlainText -Force))
        # github actions
        Invoke-WebRequest -Uri ${GITHUB_RUNNER_URL} -OutFile ${GITHUB_RUNNER_FILE}
        Remove-Item -Path C:\\runner-* -Recurse -Force
        for ($runner = 1 ; $runner -le ${RUNNERS} ; $runner++){  
            Write-Host "Running  $runner";
            $random = -join ((48..57) + (97..122) | Get-Random -Count 8 | % {[char]$_});
            Expand-Archive -LiteralPath ${GITHUB_RUNNER_FILE} -DestinationPath runner-$random -Force;
            Invoke-Expression -Command "C:\\runner-$random\\config.cmd --name ${GITHUB_RUNNER_NAME}_$random --replace --unattended --url ${ORGANIZATION_URL} --labels ${GITHUB_RUNNER_LABELS} --pat ${PAT}";
            Start-Process "C:\\runner-$random\\run.cmd" -Credential ($credentials);
        }
    SHELL
end
  
