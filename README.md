# 🏃 Windows Github Custom Runner 

Explore an innovative, efficient, and cost-effective approach to deploying a custom GitHub Runner that runs in a containerized Windows OS (x64) environment on a Linux system. This project leverages the robust capabilities of Vagrant VM, libvirt, and docker-compose which allows for seamless management of a Windows instance just like any Docker container. The added value here lies in the creation of a plug-and-play solution, significantly enhancing convenience, optimizing resource allocation, and integrating flawlessly with existing workflows. This strategy enriches CI/CD pipeline experiences in various dev-ops environments, providing a smooth and comprehensive approach that does not require prior knowledge of VM creation. 

# 📋 Prerequisites

- [docker](https://www.docker.com/)  version 24 or higher.
- [docker-compose](https://www.docker.com/) version 1.18 or higher.

# 🚀 Deployment Guide

1. Create/Update the environmental file `.env`
  - `PAT`: Personal access token from GitHub
  - `RUNNER_URL`: The URL of the GitHub that the runner connects to
  - `RUNNERS`: Number of runners
  - `MEMORY`: Amount of memory for the Vagrant image (in MB)
  - `CPU`: Number of CPUs for the Vagrant image
  - `DISK_SIZE`: Disk size for the Vagrant image (in GB)
```env
# Runner settings
PAT=<Replace with your personal access token>
RUNNER_URL=<runner url>
RUNNERS=1
# Vagrant image settings
MEMORY=8000 # 8GB
CPU=4
DISK_SIZE=100
```
2. Create `docker-compose.yml`
```yaml
version: "3.9"

services:
  win10:
    image: ghcr.io/vaggeliskls/windows-github-custom-runner:latest
    env_file: .env
    stdin_open: true
    tty: true
    privileged: true
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
    ports:
      - 3389:3389
```
3. Run: `docker-compose up -d`

> The PAT token needs Read and Write access to organization self-hosted runners


# 🌐 Access via Remote Desktop
For debugging purposes or testing you can always connect to the VM with remote desktop softwares.

Some software that used when developed was 
1. Linux: rdesktop `rdesktop <ip>:3389` or [remina](https://remmina.org/)
2. MacOS: [Windows remote desktop](https://apps.apple.com/us/app/microsoft-remote-desktop/id1295203466?mt=12)
3. Windows: buildin `Remote Windows Connection` 

# 🔑 User Login
The default users based on vagrant image are 

1. Administrator
    - Username: Administrator
    - Password: vagrant
1. User
    - Username: vagrant
    - Password: vagrant



# 📚 Further Reading and Resources

- [Windows in docker container](https://github.com/vaggeliskls/windows-in-docker-container)
- [Windows Vagrant Tutorial](https://github.com/SecurityWeekly/vulhub-lab)
- [Vagrant image: peru/windows-server-2022-standard-x64-eval](https://app.vagrantup.com/peru/boxes/windows-server-2022-standard-x64-eval)
- [Vagrant by HashiCorp](https://www.vagrantup.com/)
- [Windows Virtual Machine in a Linux Docker Container](https://medium.com/axon-technologies/installing-a-windows-virtual-machine-in-a-linux-docker-container-c78e4c3f9ba1)
