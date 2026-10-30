FROM debian:bookworm-slim

ARG DEPENDENCY_HASH

ENV ELAN_HOME=/opt/elan \
    PATH=/opt/elan/bin:/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      python3 \
      python3-venv \
      time \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "$ELAN_HOME" \
    && curl -fsSL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
      | sh -s -- -y --no-modify-path --default-toolchain none

WORKDIR /opt/mahjong

COPY lean-toolchain lakefile.lean lake-manifest.json ./
COPY scripts/remote-compute-requirements.txt ./scripts/remote-compute-requirements.txt

RUN python3 -m venv /opt/venv \
    && pip install --no-cache-dir -r scripts/remote-compute-requirements.txt \
    && lake exe cache get \
    && chmod -R a-w /opt/mahjong \
    && useradd --uid 65532 --create-home --home-dir /home/worker worker

LABEL io.github.bgnori.mahjong.dependency-hash="${DEPENDENCY_HASH}"
