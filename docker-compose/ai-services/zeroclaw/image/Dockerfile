# Upstream ZeroClaw plus the two things it shells out to and the upstream image
# does not ship: the `docker` CLI for the sandbox backend, and the browser stack
# behind the `browser` tool. Bump the tags and the version below together when
# upgrading.
FROM docker:27-cli AS dockercli

FROM ghcr.io/zeroclaw-labs/zeroclaw:v0.8.5-debian

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

# The `browser` tool's default backend (`agent_browser`) shells out to the
# `agent-browser` CLI; without it the tool answers "agent-browser CLI is
# unavailable. Install with: npm install -g agent-browser". The npm package is
# only a launcher around one Rust binary per platform, so the tarball is
# enough: no Node in the image and nothing to download when the container
# starts. The `--version` call is the smoke test (it is what breaks on a
# glibc bump).
ARG AGENT_BROWSER_VERSION=0.41.0

# The upstream image runs as `nobody` (65534); apt and the tarball need root.
# Restored below, even though the Compose stack forces `user: "0:0"` anyway.
USER root

# Chromium comes from Debian, not from `agent-browser install` (which downloads
# Chrome for Testing into $HOME — here a bind mount — on first use): apt resolves
# the ~200 MB of shared libraries and the compose env points the CLI at it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl chromium \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://registry.npmjs.org/agent-browser/-/agent-browser-${AGENT_BROWSER_VERSION}.tgz" \
    | tar -xzf - -O package/bin/agent-browser-linux-x64 > /usr/local/bin/agent-browser \
 && chmod 0755 /usr/local/bin/agent-browser \
 && agent-browser --version

USER 65534:65534
