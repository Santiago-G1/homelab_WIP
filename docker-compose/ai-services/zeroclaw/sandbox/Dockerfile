# What the agent may reach: every sandboxed command runs in a throwaway,
# network-less container from this image. Anything missing has to be baked in.
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

# Only the fallback for commands the sandbox runs without a workspace.
WORKDIR /tmp

CMD ["bash"]