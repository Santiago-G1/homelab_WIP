# Upstream ZeroClaw plus the `docker` CLI, which the sandbox backend shells out
# to and the upstream images do not ship. Bump both tags together when upgrading.
FROM docker:27-cli AS dockercli

FROM ghcr.io/zeroclaw-labs/zeroclaw:v0.8.5-debian

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker