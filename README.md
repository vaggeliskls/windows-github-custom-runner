# Windows Github Custom Runner 
A implementation of windows github custom runner based on vagrant VM, libvirt and docker compose. The VM is created inside a container using vagrant and libvirt. This strategy makes the deployment of windows action runners trivial and plug and play. 

# Prerequisites

- [docker](https://www.docker.com/) >= 24
- [docker-compose](https://www.docker.com/) >= 1.18

# Deployment Guide

1. Create/Update the environmental file `.env`
    - Organization URL
    - PAT: Personal access token
```
# Github action settings
GITHUB_RUNNER_NAME=windows_x64_vagrant
GITHUB_RUNNER_VERSION=2.305.0
GITHUB_RUNNER_FILE=actions-runner-win-x64-${GITHUB_RUNNER_VERSION}.zip
GITHUB_RUNNER_URL=https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${GITHUB_RUNNER_FILE}
GITHUB_RUNNER_LABELS=windows,win_x64,windows_x64
PAT=<Replace with your personal access token>
ORGANIZATION_URL=<Organization url>
# Vagrant image settings
MEMORY=10000 # 10GB
CPU=4
DISK_SIZE=100
```
2. Create `docker-compose.yml`
```yaml
version: "3.9"

services:
  win10:
    image: ghcr.io/vaggeliskls/windows-github-custom-runner:latest
    container_name: win10
    hostname: win10
    env_file: .env
    stdin_open: true
    tty: true
    privileged: true
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
    devices:
      - /dev/kvm
      - /dev/net/tun
    ports:
      - 3389:3389
```
3. Run: `docker-compose up -d`

> The PAT token needs Read and Write access to organization self hosted runners


# Remote Desktop
For debugging purposes or testing you can always connect to the VM with remote desktop softwares.

Some software that used when developed was 
1. Linux: Remote desktop connect `rdesktop <ip>:3389`
2. MacOS: `xfreerdp <ip>:3389`

## User login
The default users based on vagrant image are 

1. Administrator
    - Username: Administrator
    - Password: vagrant
1. User
    - Username: vagrant
    - Password: vagrant



# References

- [Windows Vagrant Tutorial](https://github.com/SecurityWeekly/vulhub-lab)
- [Vagrant image: peru/windows-server-2022-standard-x64-eval](https://app.vagrantup.com/peru/boxes/windows-server-2022-standard-x64-eval)
- [Vagrant by HashiCorp](https://www.vagrantup.com/)