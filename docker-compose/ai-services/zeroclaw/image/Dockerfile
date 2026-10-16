# Thin layer over the upstream ZeroClaw image.
#
# The Docker sandbox backend shells out to the `docker` CLI, which the upstream
# images do not ship (the `debian` variant carries bash, curl, git and
# vim-tiny only). Take the static CLI from Docker's own CLI image and add it to
# the `debian` variant, which also keeps a shell around for
# `docker compose exec zeroclaw ...` troubleshooting.
#
# Pinned to the release the config in this repo was written against (the docs
# in the upstream tree are for 0.8.5). Bump both tags together when upgrading.
FROM docker:27-cli AS dockercli

FROM ghcr.io/zeroclaw-labs/zeroclaw:v0.8.5-debian

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker