# signal-cli is the JVM build of the daemon Hermes' Signal adapter speaks to: JSON-RPC
# 2.0 on /api/v1/rpc, envelopes as SSE on /api/v1/events. 0.14.x is compiled for
# Java 25 (class file 69), so the runtime has to be 25: 21 fails at load with
# UnsupportedClassVersionError.
FROM eclipse-temurin:25-jre-noble@sha256:a98128a57de944a72bd31fbc79b898edd5a5864d3652071d5bbd2160ab7d7dce

ARG SIGNAL_CLI_VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# The release tarball carries the launcher and libsignal's native library.
RUN set -eux; \
    test -n "${SIGNAL_CLI_VERSION}"; \
    curl -fsSL -o /tmp/signal-cli.tar.gz \
      "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}.tar.gz"; \
    tar -xzf /tmp/signal-cli.tar.gz -C /opt; \
    mv "/opt/signal-cli-${SIGNAL_CLI_VERSION}" /opt/signal-cli; \
    rm -f /tmp/signal-cli.tar.gz; \
    ln -s /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli; \
    signal-cli --version

# The linked account (keys, sessions) lives in $XDG_DATA_HOME/signal-cli: the only state to
# keep. SIGNAL_CLI_CONFIG_DIR is the misleading name here — it only moves the config dir.
ENV XDG_DATA_HOME=/var/lib/signal-cli
# A 35B agent does the thinking: this JVM only relays, and the CT has no RAM to spare.
# JAVA_TOOL_OPTIONS is read by the JVM itself; the launcher script ignores JAVA_OPTS.
ENV JAVA_TOOL_OPTIONS="-Xmx384m -XX:MaxMetaspaceSize=192m -XX:+ExitOnOutOfMemoryError"

VOLUME ["/var/lib/signal-cli"]
EXPOSE 8080
ENTRYPOINT ["/opt/signal-cli/bin/signal-cli"]
CMD ["daemon", "--http", "0.0.0.0:8080", "--no-receive-stdout"]
