# Scheduled fetcher: takes the URLs listed in urls.txt, turns each one into an
# epub and drops it in the library folder. The engine is FanFicFare because it
# already knows how to walk a paginated document and produce a clean epub, and
# because its adapters are maintained; they break over time, so the version is
# pinned and bumped on purpose, never floated.
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b

ARG FANFICFARE_VERSION=4.63.0

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir "fanficfare==${FANFICFARE_VERSION}"

COPY urls.example.txt /opt/fetcher/urls.example.txt
COPY entrypoint.sh /usr/local/bin/epub-fetcher
RUN chmod 0755 /usr/local/bin/epub-fetcher

ENTRYPOINT ["/usr/local/bin/epub-fetcher"]
