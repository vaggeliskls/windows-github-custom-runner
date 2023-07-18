Vagrant.configure("2") do |config|

    config.vm.box = "peru/windows-server-2022-standard-x64-eval"
    config.vm.network "private_network", ip: "192.168.121.10"
    config.vm.network "forwarded_port", guest: 445, host: 445
    config.vm.provision "shell", inline: "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"
    config.vm.provider "libvirt" do |libvirt|
        libvirt.memory = $MEMORY
        libvirt.cpus = $CPU
        libvirt.machine_virtual_size = $DISK_SIZE
    end
    config.winrm.max_tries = 300 # default is 20
    config.winrm.retry_delay = 5 #seconds. This is the defaul value and just here for documentation.
    config.vm.provision "shell", powershell_elevated_interactive: false, privileged: false, inline: <<-SHELL
        # Install Chocolatey - Also Grabs 7Zip
        Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -AddToPath"
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        choco install 7zip.install -y 
        choco install git.install -y
        choco install jq -y
        # c:/ default location
        Set-Location /
        # Install build tools
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_enterprise.exe" -OutFile "vs_enterprise.exe"
        ./vs_enterprise.exe --quiet --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended # --passive
        # Install rtools40
        Invoke-WebRequest -Uri "https://cran.r-project.org/bin/windows/Rtools/rtools40-x86_64.exe" -OutFile "rtools.exe"
        Start-Process "./rtools.exe" -Argument "/Silent" -PassThru -Wait
        ${DOLLAR}env:PATH += ";C:\rtools40\usr\bin;C:\rtools40\mingw64\bin"
        C:\rtools40\msys2.exe pacman -Sy --noconfirm mingw-w64-x86_64-make
        Remove-Item -Path ./rtools.exe
        # Resize disk
        Resize-Partition -DriveLetter "C" -Size (Get-PartitionSupportedSize -DriveLetter "C").SizeMax  
        # github actions
        mkdir actions-runner 
        Set-Location actions-runner
        Invoke-WebRequest -Uri $GITHUB_RUNNER_URL -OutFile $GITHUB_RUNNER_FILE
        Expand-Archive $GITHUB_RUNNER_FILE -DestinationPath .
        ./config.cmd --name ${GITHUB_RUNNER_NAME}_${RANDOM_STR} --replace --unattended --url $ORGANIZATION_URL --labels $GITHUB_RUNNER_LABELS --pat $PAT
        ./run.cmd
    SHELL
end
  
