# syntax=docker/dockerfile:1
ARG ATLANTIS_TAG=v0.30.0
FROM ghcr.io/runatlantis/atlantis:${ATLANTIS_TAG}
COPY --chown=root:root --chmod=0755 extract-blindfold.sh /docker-entrypoint.d/extract-blindfold.sh

# Install supporting tools to /usr/local/bin - need to be root to do this
USER root

ARG UNSEAL_VER=1.2.1
RUN curl -sfLo /usr/local/bin/unseal https://github.com/memes/f5xc/releases/download/v${UNSEAL_VER}/unseal_${UNSEAL_VER}_linux_amd64 && \
    chmod 0755 /usr/local/bin/unseal && \
    chown root:root /usr/local/bin/unseal

ARG TERRAGRUNT_VER=0.68.7
RUN curl -sfLo /usr/local/bin/terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VER}/terragrunt_linux_amd64 && \
    chmod 0755 /usr/local/bin/terragrunt && \
    chown root:root /usr/local/bin/terragrunt

ARG TERRAGRUNT_ATLANTIS_CONFIG_VER=1.19.0
RUN curl -sfLo /usr/local/bin/terragrunt-atlantis-config https://github.com/transcend-io/terragrunt-atlantis-config/releases/download/v${TERRAGRUNT_ATLANTIS_CONFIG_VER}/terragrunt-atlantis-config_${TERRAGRUNT_ATLANTIS_CONFIG_VER}_linux_amd64 && \
    chmod 0755 /usr/local/bin/terragrunt-atlantis-config && \
    chown root:root /usr/local/bin/terragrunt-atlantis-config

ARG VESCTL_VER=0.2.47
# /bin/sh is busybox with support for pipefail; use it to ensure vesctl is extracted correctly.
# hadolint ignore=SC3040,DL4006
RUN <<EOS /bin/sh
set -o pipefail
curl -sfL https://vesio.azureedge.net/releases/vesctl/${VESCTL_VER}/vesctl.linux-amd64.gz | \
    zcat > /usr/local/bin/vesctl
chmod 0755 /usr/local/bin/vesctl
chown root:root /usr/local/bin/vesctl
EOS

# Switch back to atlantis account
USER atlantis
