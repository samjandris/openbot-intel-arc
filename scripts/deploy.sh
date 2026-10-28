#!/usr/bin/env bash
# Run only after exact render-device/group access has been approved.
set -euo pipefail
umask 077
[[ ${1:-} == --device-access-approved ]] || { echo 'Exact render device/group approval required.' >&2; exit 2; }
shift
task_private=${1:?Usage: deploy.sh --device-access-approved NEW_PRIVATE_DIR IMAGE_TAG EXPECTED_DIGEST}
task_image=${2:?published image tag required}
task_expected=${3:?expected published sha256 digest required}
task_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_device=/dev/dri/renderD128
task_gid=18
[[ $(id -u) == 0 && $task_image == ghcr.io/samjandris/openbot-intel-arc:* && $task_expected =~ ^sha256:[a-f0-9]{64}$ ]]
[[ -c $task_device && $(stat -c %g "$task_device") == "$task_gid" ]]
[[ $(cat /sys/class/drm/renderD128/device/vendor) == 0x8086 && $(cat /sys/class/drm/renderD128/device/device) == 0x56a5 ]]
[[ $(basename "$(readlink -f /sys/class/drm/renderD128/device)") == 0000:2b:00.0 ]]
[[ $(docker inspect -f '{{.Config.Image}}' openbot) == ghcr.io/nightly-labs/openbot:0.52.1 ]]
[[ $(docker inspect -f '{{.HostConfig.Privileged}}' openbot) == false ]]
docker pull "$task_image" >/dev/null
docker image inspect "$task_image" | jq -e --arg digest "$task_expected" \
  '.[0].RepoDigests | any(.[]; endswith("@"+$digest))' >/dev/null
[[ $(docker image inspect -f '{{index .Config.Labels "io.openbot.a380.upstream.version"}}' "$task_image") == 0.52.1 ]]
task_probe=$(mktemp -d /tmp/openbot-a380-proposal.XXXXXX)
trap 'rm -rf -- "$task_probe"' EXIT
php "$task_repo/scripts/update-template.php" \
  /boot/config/plugins/dockerMan/templates-user/my-openbot.xml "$task_probe/template.xml" "$task_image" "$task_device" "$task_gid"
"$task_repo/scripts/backup.sh" "$task_private"
task_renamed=false
task_complete=false
task_original=$(jq -r '.[0].Id' "$task_private/container-before.json")
task_old=openbot-pre-a380-${task_original:0:12}
printf '%s\n' "$task_old" >"$task_private/original-container-name.txt"
task_recover() {
  local task_rc=$?
  rm -rf -- "$task_probe"
  if [[ $task_complete != true ]]; then
    if [[ $task_renamed == true ]]; then
      "$task_repo/scripts/rollback.sh" "$task_private" >"$task_private/automatic-rollback.log" 2>&1 || {
        echo "Automatic rollback needs attention; see private $task_private/automatic-rollback.log" >&2;
      }
    else
      docker start openbot >/dev/null || true
    fi
  fi
  exit "$task_rc"
}
trap task_recover EXIT
jq --arg image "$task_image" --arg device "$task_device" --arg gid "$task_gid" \
  -f "$task_repo/scripts/create-request.jq" "$task_private/container-before.json" >"$task_private/create-request.json"
docker rename openbot "$task_old"
task_renamed=true
docker update --restart no "$task_old" >/dev/null
# Host Docker API only. The socket is never mounted into OpenBot.
curl --silent --show-error --fail --unix-socket /var/run/docker.sock \
  -H 'Content-Type: application/json' --data-binary "@$task_private/create-request.json" \
  'http://localhost/containers/create?name=openbot' >"$task_private/create-response.json"
cp -p "$task_probe/template.xml" /boot/config/plugins/dockerMan/templates-user/my-openbot.xml
docker start openbot >/dev/null
docker inspect openbot >"$task_private/container-after.json"
jq -e --slurpfile before "$task_private/container-before.json" --arg device "$task_device" --arg gid "$task_gid" '
  .[0] as $n | $before[0][0] as $o |
  $n.Config.User == $o.Config.User and $n.Config.Env == $o.Config.Env and
  $n.Config.Entrypoint == $o.Config.Entrypoint and $n.Config.Cmd == $o.Config.Cmd and
  $n.Config.StopTimeout == $o.Config.StopTimeout and
  $n.HostConfig.SecurityOpt == $o.HostConfig.SecurityOpt and
  $n.HostConfig.Privileged == false and
  $n.HostConfig.Binds == $o.HostConfig.Binds and
  $n.HostConfig.PortBindings == $o.HostConfig.PortBindings and
  $n.HostConfig.ShmSize == $o.HostConfig.ShmSize and
  $n.HostConfig.RestartPolicy == $o.HostConfig.RestartPolicy and
  $n.HostConfig.Devices == [{PathOnHost:$device,PathInContainer:$device,CgroupPermissions:"rw"}] and
  ($n.HostConfig.GroupAdd | index($gid)) != null
' "$task_private/container-after.json" >/dev/null
# docker exec inherits the configured nonroot user and supplementary groups.
docker exec openbot openbot-gpu-test "$task_device" /tmp/openbot-a380-validation \
  >"$task_private/gpu-test-summary.log" 2>&1
docker cp openbot:/tmp/openbot-a380-validation "$task_private/hardware-validation" >/dev/null
for task_attempt in {1..12}; do
  if docker exec openbot openbot status >"$task_private/status-after.txt" 2>&1; then break; fi
  sleep 5
done
docker exec openbot openbot status >"$task_private/status-after.txt" 2>&1
docker exec openbot sh -c 'test -s /data/.config/OpenBot/openbot.db && test -d /data/.local/share/keyrings && test -d /data/.config/openbot-container'
[[ $(docker inspect -f '{{.State.Running}}' openbot) == true ]]
docker logs --since 5m openbot >"$task_private/openbot-after.log" 2>&1
touch "$task_private/DEPLOYMENT_VERIFIED"
task_complete=true
printf 'Deployed %s. GPU encode and preserved config checks passed. Private rollback: %s\n' "$task_image" "$task_private"
