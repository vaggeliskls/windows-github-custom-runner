# Windows Github Custom Runner 
A implementation of windows github custom runner based on vagrant VM, libvirt and docker compose. The VM is created inside a container using vagrant and libvirt. This strategy makes the deployment of windows action runners trivial and plug and play. 

# Prerequisites

- [docker](https://www.docker.com/) >= 24
- [docker-compose](https://www.docker.com/) >= 1.18

# Deployment Guide

1. Update the environmental file .env
    - Organization URL
    - PAT: Personal access token
2. Run: `docker-compose up -d`

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