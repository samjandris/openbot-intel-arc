#!/usr/bin/env bash
# Emergency host-side restore when the Docker tab cannot restore the pinned image.
# Keeps current /data; never removes volumes or starts the retained original container.
set -euo pipefail
umask 077
task_private=${1:?Usage: rollback-graphics.sh VERIFIED_BACKUP_DIR PINNED_LOCAL_IMAGE}
task_pin=${2:?pinned working local image tag required}
[[ $(id -u) == 0 && -f $task_private/BACKUP_VERIFIED ]]
task_expected=$(jq -r '.[0].Image' "$task_private/container-before.json")
[[ $(docker image inspect -f '{{.Id}}' "$task_pin") == "$task_expected" ]]
jq -e '.[0] | .Name == "/openbot" and .HostConfig.Privileged == false and
  ([.Mounts[] | select(.Destination == "/data") | .Source] == ["/mnt/user/appdata/openbot/data"])' \
  "$task_private/container-before.json" >/dev/null
jq --arg image "$task_pin" '
  .[0] as $old | $old.Config | .Image = $image | .HostConfig = $old.HostConfig |
  .NetworkingConfig = {EndpointsConfig: ($old.NetworkSettings.Networks |
    with_entries(.value |= {IPAMConfig, Links, Aliases, DriverOpts} |
    .value |= with_entries(select(.value != null))))}
' "$task_private/container-before.json" >"$task_private/rollback-create.json"
php -r '
  $x=simplexml_load_file($argv[1]); if(!$x)exit(1);
  $x->Repository=$argv[3]; if(!$x->asXML($argv[2]))exit(1);
' "$task_private/template-before.xml" "$task_private/rollback-template.xml" "$task_pin"
if docker inspect openbot >/dev/null 2>&1; then
  docker stop --time 60 openbot >/dev/null
  docker rm openbot >/dev/null
fi
curl --silent --show-error --fail --unix-socket /var/run/docker.sock \
  -H 'Content-Type: application/json' --data-binary "@$task_private/rollback-create.json" \
  'http://localhost/containers/create?name=openbot' >"$task_private/rollback-response.json"
cp -p "$task_private/rollback-template.xml" /boot/config/plugins/dockerMan/templates-user/my-openbot.xml
docker start openbot >/dev/null
docker inspect openbot >"$task_private/rollback-container.json"
jq -e --arg image "$task_expected" '.[0] | .Image == $image and .State.Running == true' \
  "$task_private/rollback-container.json" >/dev/null
printf 'Pinned working image restored. Current data retained. Private record: %s\n' "$task_private"
