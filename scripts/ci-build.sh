#!/usr/bin/env bash
# GitHub runner only. Unraid pulls the published image and never builds it.
set -euo pipefail
[[ ${CI:-} == true ]] || { echo 'Run through the GitHub Actions image workflow.' >&2; exit 1; }
task_version=${1:?upstream version required}
[[ $task_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
task_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_base_tag=ghcr.io/nightly-labs/openbot:$task_version
docker pull --platform linux/amd64 "$task_base_tag"
task_base=$(docker image inspect "$task_base_tag" --format '{{index .RepoDigests 0}}')
[[ $task_base == ghcr.io/nightly-labs/openbot@sha256:* ]] || exit 1
task_context=$(mktemp -d)
trap 'rm -rf -- "$task_context"' EXIT
mkdir "$task_context/scripts"
for task_file in Dockerfile .dockerignore scripts/gpu-test.sh scripts/video-encode.sh; do
  [[ -f $task_repo/$task_file && ! -L $task_repo/$task_file ]] || exit 1
  cp -- "$task_repo/$task_file" "$task_context/$task_file"
done
docker build --platform linux/amd64 --build-arg "BASE_IMAGE=$task_base" \
  --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" \
  --label "org.opencontainers.image.revision=$GITHUB_SHA" \
  --label "io.openbot.a380.upstream.version=$task_version" \
  --label "io.openbot.a380.upstream.digest=${task_base#*@}" \
  --tag openbot-a380-ci "$task_context"
[[ $(docker image inspect -f '{{.Config.User}}' openbot-a380-ci) == openbot ]]
[[ $(docker image inspect -f '{{json .Config.Entrypoint}}' openbot-a380-ci) == \
   $(docker image inspect -f '{{json .Config.Entrypoint}}' "$task_base") ]]
[[ $(docker image inspect -f '{{json .Config.Cmd}}' openbot-a380-ci) == \
   $(docker image inspect -f '{{json .Config.Cmd}}' "$task_base") ]]
docker run --rm --network none --entrypoint /bin/bash openbot-a380-ci -euc '
  test "$(id -u):$(id -g)" = 1000:1000
  test -s /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so
  test -x /usr/local/bin/openbot-gpu-test
  test -x /usr/local/bin/openbot-video-encode
  test -z "${LIBVA_DRIVER_NAME:-}"
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_vaapi
  bash -n /usr/local/bin/openbot-gpu-test /usr/local/bin/openbot-video-encode
  dpkg-query -W ffmpeg vainfo intel-media-va-driver-non-free
  if openbot-gpu-test /dev/dri/renderD128 >/tmp/no-device.log 2>&1; then
    echo "Hardware test must fail when no render device is mapped." >&2; exit 1
  fi
  grep -q "Required render device is missing" /tmp/no-device.log
'
printf 'Validated derived image from %s. GPU encoding requires the Unraid hardware test.\n' "$task_base"
