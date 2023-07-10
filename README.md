# Windows Github Custom Runner 
A Windows github custom runner based on vagrant vm and docker compose

# Prerequisites

- [docker](https://www.docker.com/) >= 24
- [docker-compose](https://www.docker.com/) >= 1.18

# Deployment Guide

1. Update on Vagrantfile
    - Organization URL
    - PAT: Personal access token
2. Run: `docker-compose up -d`

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
- [Vagrant image: peru/windows-server-2022-standard-x64-eval](peru/windows-server-2022-standard-x64-eval)