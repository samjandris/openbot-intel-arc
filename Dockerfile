# BASE_IMAGE must be the inspected official 0.52.1 digest at build time.
ARG BASE_IMAGE=ghcr.io/nightly-labs/openbot:0.52.1
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
       ffmpeg vainfo intel-media-va-driver-non-free \
    && rm -rf /var/lib/apt/lists/* \
    && test -s /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so \
    && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_vaapi
COPY --chmod=0755 scripts/gpu-test.sh /usr/local/bin/openbot-gpu-test
COPY --chmod=0755 scripts/video-encode.sh /usr/local/bin/openbot-video-encode
LABEL io.openbot.a380.extension.version="1" \
      io.openbot.a380.scope="agent video-processing commands"
# Keep all upstream entrypoint, command, workdir, volume and sandbox behavior.
# LIBVA_DRIVER_NAME is intentionally scoped to individual video commands.
USER openbot
