ARG ATLANTIS_TAG=v0.28.3
FROM ghcr.io/runatlantis/atlantis:${ATLANTIS_TAG}
COPY --chown=root:root --chmod=0755 extract-blindfold.sh /docker-entrypoint.d/extract-blindfold.sh

# Install supporting tools to /usr/local/bin - need to be root to do this
USER root

ARG UNSEAL_VER=1.2.0
RUN curl -sfLo /usr/local/bin/unseal https://github.com/memes/f5xc/releases/download/v${UNSEAL_VER}/unseal_${UNSEAL_VER}_linux_amd64 && \
    chmod 0755 /usr/local/bin/unseal && \
    chown root:root /usr/local/bin/unseal

ARG TERRAGRUNT_VER=0.59.5
RUN curl -sfLo /usr/local/bin/terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VER}/terragrunt_linux_amd64 && \
    chmod 0755 /usr/local/bin/terragrunt && \
    chown root:root /usr/local/bin/terragrunt

ARG TERRAGRUNT_ATLANTIS_CONFIG_VER=1.18.0
RUN curl -sfL https://github.com/transcend-io/terragrunt-atlantis-config/releases/download/v${TERRAGRUNT_ATLANTIS_CONFIG_VER}/terragrunt-atlantis-config_${TERRAGRUNT_ATLANTIS_CONFIG_VER}_linux_amd64.tar.gz | \
        tar xzf - -C /usr/local/bin --strip-components 1 --exclude 'README.md' && \
    mv /usr/local/bin/terragrunt-atlantis-config_* /usr/local/bin/terragrunt-atlantis-config && \
    chmod 0755 /usr/local/bin/terragrunt-atlantis-config && \
    chown root:root /usr/local/bin/terragrunt-atlantis-config

ARG VESCTL_VER=0.2.47
RUN curl -sfL https://vesio.azureedge.net/releases/vesctl/${VESCTL_VER}/vesctl.linux-amd64.gz | \
        zcat > /usr/local/bin/vesctl && \
    chmod 0755 /usr/local/bin/vesctl && \
    chown root:root /usr/local/bin/vesctl

# Switch back to atlantis account
USER atlantis
