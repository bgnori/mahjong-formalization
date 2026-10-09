FROM debian:bookworm-slim

ARG GIT_COMMIT=unknown

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
COPY Mahjong ./Mahjong
COPY MahjongComputations ./MahjongComputations
COPY scripts/remote_compute.py ./scripts/remote_compute.py
COPY scripts/remote-compute-requirements.txt ./scripts/remote-compute-requirements.txt

RUN python3 -m venv /opt/venv \
    && pip install --no-cache-dir -r scripts/remote-compute-requirements.txt \
    && lake exe cache get \
    && lake build four-tile-report-gen \
    && test -x .lake/build/bin/four-tile-report-gen \
    && chmod -R a-w /opt/mahjong \
    && useradd --uid 65532 --create-home --home-dir /home/worker worker

LABEL org.opencontainers.image.revision="${GIT_COMMIT}"

ENV HOME=/home/worker

USER worker

ENTRYPOINT ["python3", "/opt/mahjong/scripts/remote_compute.py", "worker"]
