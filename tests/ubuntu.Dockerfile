FROM ubuntu:24.04

# Bootstrap only: the installer must supply the actual developer toolchains.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash setup-test \
    && printf 'setup-test ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/setup-test \
    && chmod 0440 /etc/sudoers.d/setup-test

WORKDIR /opt/devready
COPY devready setup-dev-environment.sh ./
COPY lib/ ./lib/
COPY scripts/ ./scripts/
COPY tests/smoke-ubuntu.sh ./tests/smoke-ubuntu.sh
USER setup-test
CMD ["bash", "tests/smoke-ubuntu.sh"]
