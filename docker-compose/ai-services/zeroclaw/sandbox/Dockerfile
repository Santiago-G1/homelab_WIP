# Sandbox image for ZeroClaw's Docker sandbox backend.
#
# Every sandboxed shell command runs in a throwaway container from this image
# (`docker run --rm --network none --memory 512m --cpus 1.0 ...`), with the
# agent workspace bind-mounted read-only at the same absolute path. This
# Dockerfile is therefore the list of what the agent may reach: keep it
# curated, and remember there is no network inside the sandbox, so anything
# missing has to be baked in here.
FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        file \
        git \
        jq \
        less \
        procps \
        python3 \
        ripgrep \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The sandbox overrides the working directory with the workspace path when it
# has one; this is only the fallback for commands that run without it.
WORKDIR /tmp

CMD ["bash"]