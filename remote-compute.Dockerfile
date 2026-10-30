ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG DEPENDENCY_HASH
ARG GIT_COMMIT=unknown

COPY Mahjong ./Mahjong
COPY MahjongComputations ./MahjongComputations
COPY scripts/remote_compute.py ./scripts/remote_compute.py

# Only chmod writable files to avoid copying read-only dependency files into this layer.
RUN lake build four-tile-report-gen seven-tile-report-gen ten-tile-report-gen \
        thirteen-tile-report-gen \
    && test -x .lake/build/bin/four-tile-report-gen \
    && test -x .lake/build/bin/seven-tile-report-gen \
    && test -x .lake/build/bin/ten-tile-report-gen \
    && test -x .lake/build/bin/thirteen-tile-report-gen \
    && find /opt/mahjong -perm /222 -exec chmod a-w {} +

LABEL org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      io.github.bgnori.mahjong.dependency-hash="${DEPENDENCY_HASH}"

ENV HOME=/home/worker

USER worker

ENTRYPOINT ["python3", "/opt/mahjong/scripts/remote_compute.py", "worker"]
