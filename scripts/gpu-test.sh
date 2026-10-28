#!/usr/bin/env bash
set -euo pipefail
umask 077
task_device=${1:-/dev/dri/renderD128}
task_out=${2:-$(mktemp -d /tmp/openbot-vaapi.XXXXXX)}
[[ $(id -u) == 1000 && $(id -g) == 1000 ]] || { echo 'Run as the OpenBot user (1000:1000).' >&2; exit 1; }
[[ $task_device =~ ^/dev/dri/renderD[0-9]+$ && -c $task_device && -r $task_device && -w $task_device ]] || {
  echo 'Required render device is missing or inaccessible.' >&2; exit 1;
}
mkdir -p -- "$task_out"
id | tee "$task_out/identity.log"
stat -c 'device=%n uid=%u gid=%g mode=%a' "$task_device" | tee "$task_out/device.log"
LIBVA_DRIVER_NAME=iHD vainfo --display drm --device "$task_device" >"$task_out/vainfo.log" 2>&1
LIBVA_DRIVER_NAME=iHD ffmpeg -hide_banner -loglevel verbose -nostdin -y \
  -vaapi_device "$task_device" -f lavfi -i testsrc2=size=1280x720:rate=30 -t 2 \
  -vf format=nv12,hwupload -an -c:v h264_vaapi -rc_mode CQP -qp 24 \
  "$task_out/a380-h264.mp4" >"$task_out/encode.log" 2>&1
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=codec_name,width,height,nb_read_frames,duration:format=duration \
  -of json "$task_out/a380-h264.mp4" | tee "$task_out/ffprobe.json"
ffmpeg -hide_banner -v error -nostdin -i "$task_out/a380-h264.mp4" -f null - \
  >"$task_out/decode.log" 2>&1
grep -q '"codec_name": "h264"' "$task_out/ffprobe.json"
grep -q '"nb_read_frames": "60"' "$task_out/ffprobe.json"
printf 'PASS: iHD initialized and h264_vaapi encoded 60 frames; decode passed. Logs: %s\n' "$task_out"
