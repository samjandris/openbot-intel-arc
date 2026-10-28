#!/usr/bin/env bash
# Usage: openbot-video-encode INPUT OUTPUT [CPU_FILTERS]
set -euo pipefail
[[ $# == 2 || $# == 3 ]] || { echo 'Usage: openbot-video-encode INPUT OUTPUT [CPU_FILTERS]' >&2; exit 2; }
task_device=${OPENBOT_VAAPI_DEVICE:-/dev/dri/renderD128}
[[ $task_device =~ ^/dev/dri/renderD[0-9]+$ && -c $task_device && -r $task_device && -w $task_device ]] || {
  echo 'Required VA-API render node is unavailable; no CPU encoder fallback.' >&2; exit 1;
}
task_filters=${3:-null}
exec env LIBVA_DRIVER_NAME=iHD ffmpeg -hide_banner -nostdin \
  -vaapi_device "$task_device" -i "$1" \
  -vf "${task_filters},format=nv12,hwupload" \
  -c:v h264_vaapi -rc_mode CQP -qp 24 -c:a aac -movflags +faststart "$2"
