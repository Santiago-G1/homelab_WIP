# signal-cli 0.14.x is Java 25 bytecode (class file 69); 21 dies at load.
FROM eclipse-temurin:25-jre-noble@sha256:a98128a57de944a72bd31fbc79b898edd5a5864d3652071d5bbd2160ab7d7dce

ARG SIGNAL_CLI_VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL -o /tmp/signal-cli.tar.gz \
      "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}.tar.gz"; \
    tar -xzf /tmp/signal-cli.tar.gz -C /opt; \
    mv "/opt/signal-cli-${SIGNAL_CLI_VERSION}" /opt/signal-cli; \
    rm -f /tmp/signal-cli.tar.gz; \
    ln -s /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli; \
    signal-cli --version

# The account store follows XDG_DATA_HOME; SIGNAL_CLI_CONFIG_DIR only moves the config dir.
ENV XDG_DATA_HOME=/var/lib/signal-cli
ENV JAVA_TOOL_OPTIONS="-Xmx384m -XX:MaxMetaspaceSize=192m -XX:+ExitOnOutOfMemoryError"

VOLUME ["/var/lib/signal-cli"]
EXPOSE 8080
ENTRYPOINT ["/opt/signal-cli/bin/signal-cli"]
CMD ["daemon", "--http", "0.0.0.0:8080", "--no-receive-stdout"]
