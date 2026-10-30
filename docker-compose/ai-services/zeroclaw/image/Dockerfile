# Upstream ZeroClaw plus the two things it shells out to and the image lacks:
# the `docker` CLI for the sandbox backend, and the browser behind the `browser`
# tool. Bump the tags and the version below together when upgrading.
FROM docker:27-cli AS dockercli

FROM ghcr.io/zeroclaw-labs/zeroclaw:v0.8.5-debian

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

# `agent-browser` is one Rust binary per platform inside the npm package, so the
# tarball is enough: no Node in the image. Chromium comes from apt because
# `agent-browser install` downloads Chrome into $HOME, which is a mount here.
ARG AGENT_BROWSER_VERSION=0.41.0

# apt and the tarball need root (the upstream image runs as nobody).
USER root

# `--version` is the smoke test: it is what breaks on a glibc bump.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl chromium \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://registry.npmjs.org/agent-browser/-/agent-browser-${AGENT_BROWSER_VERSION}.tgz" \
    | tar -xzf - -O package/bin/agent-browser-linux-x64 > /usr/local/bin/agent-browser \
 && chmod 0755 /usr/local/bin/agent-browser \
 && agent-browser --version

USER 65534:65534
