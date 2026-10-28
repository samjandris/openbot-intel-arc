# BASE_IMAGE must be the inspected official 0.52.1 digest at build time.
ARG BASE_IMAGE=ghcr.io/nightly-labs/openbot:0.52.1
FROM ${BASE_IMAGE} AS upstream

FROM python:3.13-slim-bookworm AS graphics-patch
COPY --from=upstream /opt/OpenBot/app/resources/app.asar /upstream/app.asar
COPY scripts/patch-graphics.py /patch-graphics.py
RUN python /patch-graphics.py /upstream/app.asar /patched/app.asar /patched/policy.json

FROM upstream

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
       ffmpeg vainfo intel-media-va-driver-non-free \
       libegl-mesa0 libegl1 libgl1-mesa-dri libgbm1 mesa-vulkan-drivers vulkan-tools \
    && rm -rf /var/lib/apt/lists/* \
    && test -s /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so \
    && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_vaapi
COPY --chmod=0755 scripts/gpu-test.sh /usr/local/bin/openbot-gpu-test
COPY --chmod=0755 scripts/video-encode.sh /usr/local/bin/openbot-video-encode
COPY --from=graphics-patch --chmod=0644 /patched/app.asar /opt/OpenBot/app/resources/app.asar
COPY --from=graphics-patch --chmod=0644 /patched/policy.json /usr/local/share/openbot-graphics/policy.json
COPY --chmod=0644 scripts/graphics-runtime.mjs /usr/local/lib/openbot-graphics/runtime.mjs
LABEL io.openbot.a380.extension.version="1" \
      io.openbot.a380.scope="agent video-processing and opt-in browser graphics" \
      io.openbot.graphics.patch.version="1"
ENV OPENBOT_SERVER_GPU=1 OPENBOT_GPU_SELF_TEST=1
# Keep all upstream entrypoint, command, workdir, volume and sandbox behavior.
# LIBVA_DRIVER_NAME is intentionally scoped to individual video commands.
USER openbot
