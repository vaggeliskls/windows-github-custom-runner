# https://github.com/SecurityWeekly/vulhub-lab
Vagrant.configure("2") do |config|

    config.vm.box = "peru/windows-server-2022-standard-x64-eval"
    config.vm.network "private_network", ip: "192.168.121.10"
    config.vm.network "forwarded_port", guest: 445, host: 445
    config.vm.provision "shell", inline: "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"
    config.vm.provider "libvirt" do |libvirt|
        libvirt.memory = 50000 # 50GB
        libvirt.cpus = 10
        libvirt.machine_virtual_size = 100
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
        # Resize disk
        # Variable specifying the drive you want to extend  
        $drive_letter = "C"  
        # Script to get the partition sizes and then resize the volume  
        $size = (Get-PartitionSupportedSize -DriveLetter $drive_letter)  
        Resize-Partition -DriveLetter $drive_letter -Size $size.SizeMax  
        # github actions
        mkdir actions-runner 
        Set-Location actions-runner
        Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.305.0/actions-runner-win-x64-2.305.0.zip -OutFile actions-runner-win-x64-2.305.0.zip
        if((Get-FileHash -Path actions-runner-win-x64-2.305.0.zip -Algorithm SHA256).Hash.ToUpper() -ne '3a4afe6d9056c7c63ecc17f4db32148e946454f2384427b0a4565b7690ef7420'.ToUpper()){ throw 'Computed checksum did not match' }
        Expand-Archive actions-runner-win-x64-2.305.0.zip -DestinationPath .
        ./config.cmd --name windows_x64_vagrant --replace --unattended --url https://github.com/turintech --labels windows,win_x64,windows_x64 --pat <HERE WE ADD OUR PERSONAL ACCESS TOKEN WITH GITHUB ACTIONS PERMISSIONS>
        ./run.cmd
    SHELL
end
  
