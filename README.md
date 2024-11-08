# 🏃 Windows Github Custom Runner 

Explore an innovative, efficient, and cost-effective approach to deploying a custom GitHub Runner that runs in a containerized Windows OS (x64) environment on a Linux system. This project leverages the robust capabilities of Vagrant VM, libvirt, and docker-compose which allows for seamless management of a Windows instance just like any Docker container. The added value here lies in the creation of a plug-and-play solution, significantly enhancing convenience, optimizing resource allocation, and integrating flawlessly with existing workflows. This strategy enriches CI/CD pipeline experiences in various dev-ops environments, providing a smooth and comprehensive approach that does not require prior knowledge of VM creation. 

⭐ **Don't forget to star the project if it helped you!**

# 📋 Prerequisites

- [docker](https://www.docker.com/)  version 24 or higher.
- [docker-compose](https://www.docker.com/) version 1.18 or higher.

# 🚥 Authentication for Self-Hosted Runners
For the purpose of authenticating your custom self-hosted runners, we offer two viable authentication methods:

1. Personal Access Token (`PAT`) - The Personal Access Token is a static, manually created token that provides secure access to GitHub. This offers a long-lived method of authentication (The PAT token needs Read and Write access to organization self-hosted runners).

2. Registration Token (`TOKEN`) - The Registration Token is a dynamic, short-lived token generated automatically by GitHub during the creation of a new self-hosted runner. This provides a temporary but immediate method of authentication.

> **Note:** Only one of these authentication methods is necessary. Choose the method that best fits your

# 🚀 Deployment Guide

1. Create/Update the environmental file `.env`
  - `PAT`: Personal access token from GitHub
  - `TOKEN`: Short lived Github token
  - `RUNNER_URL`: The URL of the GitHub that the runner connects to
  - `RUNNERS`: Number of runners
  - `MEMORY`: Amount of memory for the Vagrant image (in MB)
  - `CPU`: Number of CPUs for the Vagrant image
  - `DISK_SIZE`: Disk size for the Vagrant image (in GB)

### Example with PAT
```env
# Runner settings
PAT=<Your Personal access token>
RUNNER_URL=<runner url>
RUNNERS=1
# Vagrant image settings
MEMORY=8000 # 8GB
CPU=4
DISK_SIZE=100
```
### Example with TOKEN
```env
# Runner settings
TOKEN=<Your short lived acess token>
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
  windows-github-runner-vm:
    image: docker.io/vaggeliskls/windows-github-custom-runner:latest
    env_file: .env
    stdin_open: true
    tty: true
    privileged: true
    ports:
      - 3389:3389
```
3. Run: `docker-compose up -d`

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
