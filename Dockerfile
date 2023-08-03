# syntax=docker/dockerfile:1.5
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm-256color

RUN apt-get update -y && \
    apt-get install -y \
    qemu-kvm \
    build-essential \
    libvirt-daemon-system \
    libvirt-dev \
    openssh-server \
    linux-image-$(uname -r) \
    curl \
    net-tools \
    gettext-base \
    jq && \
    apt-get autoremove -y && \
    apt-get clean

RUN curl -O https://releases.hashicorp.com/vagrant/2.2.19/vagrant_2.2.19_x86_64.deb && \
    dpkg -i vagrant_2.2.19_x86_64.deb && \
    vagrant plugin install vagrant-libvirt && \
    vagrant box add --provider libvirt peru/windows-server-2022-standard-x64-eval && \
    vagrant init peru/windows-server-2022-standard-x64-eval

# Github action settings
ENV GITHUB_RUNNER_NAME=windows_x64_vagrant
ENV GITHUB_RUNNER_VERSION=2.306.0
ENV GITHUB_RUNNER_FILE=actions-runner-win-x64-${GITHUB_RUNNER_VERSION}.zip
ENV GITHUB_RUNNER_URL=https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${GITHUB_RUNNER_FILE}
ENV GITHUB_RUNNER_LABELS=windows,win_x64,windows_x64,windows_vagrant_action
ENV PRIVILEGED=false
ENV INTERACTIVE=false
ENV DOLLAR=$

COPY Vagrantfile /Vagrantfile.tmp
COPY startup.sh /
RUN chmod +x startup.sh

CMD ["/startup.sh"]