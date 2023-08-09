# syntax=docker/dockerfile:1.5
FROM ghcr.io/vaggeliskls/windows-in-docker-container:latest

# Github action settings
ENV GITHUB_RUNNER_NAME=windows_x64_vagrant
ENV GITHUB_RUNNER_VERSION=2.307.1
ENV GITHUB_RUNNER_FILE=actions-runner-win-x64-${GITHUB_RUNNER_VERSION}.zip
ENV GITHUB_RUNNER_URL=https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${GITHUB_RUNNER_FILE}
ENV GITHUB_RUNNER_LABELS=windows,win_x64,windows_x64,windows_vagrant_action
ENV PRIVILEGED=true
ENV INTERACTIVE=true
ENV DOLLAR=$

RUN rm -rf /Vagrantfile
RUN rm -rf /Vagrantfile.tmp
RUN rm -rf /startup.sh

COPY Vagrantfile /Vagrantfile.tmp
COPY startup.sh /
RUN chmod +x startup.sh

ENTRYPOINT ["/startup.sh"]
CMD ["/bin/bash"]
