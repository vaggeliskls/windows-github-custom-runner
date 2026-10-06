# syntax=docker/dockerfile:1
FROM ghcr.io/vaggeliskls/windows-in-docker-container:1.0.1

LABEL org.opencontainers.image.source="https://github.com/vaggeliskls/windows-github-custom-runner" \
      org.opencontainers.image.description="Self-hosted GitHub Actions runners on a Windows VM (Vagrant + libvirt) inside a Linux container"

# GitHub Actions runner defaults. All of these can be overridden at runtime via .env;
# the download URL is derived from GITHUB_RUNNER_VERSION inside the Vagrantfile.
ENV GITHUB_RUNNER_VERSION=2.338.0
ENV GITHUB_RUNNER_NAME=windows_x64_vagrant
ENV GITHUB_RUNNER_LABELS=windows,win_x64,windows_x64,windows_vagrant_action

# Provision elevated and in an interactive session so runners can drive GUI tooling
ENV PRIVILEGED=true
ENV INTERACTIVE=true

# Replace the base image's generic Vagrantfile with the runner one.
# The base image's /app/startup.sh (libvirtd startup, KVM/QEMU fallback, graceful halt) is reused as-is.
COPY Vagrantfile /app/Vagrantfile
