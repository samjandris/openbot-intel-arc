#!/usr/bin/env bash
# Restores the original container and template; keeps the current /data contents.
set -euo pipefail
umask 077
task_private=${1:?Usage: rollback.sh PRIVATE_BACKUP_DIR}
[[ $(id -u) == 0 && -f $task_private/BACKUP_VERIFIED ]] || exit 1
task_old=$(cat "$task_private/original-container-name.txt")
task_original_id=$(jq -r '.[0].Id' "$task_private/container-before.json")
[[ $(docker inspect -f '{{.Id}}' "$task_old") == "$task_original_id" ]] || exit 1
if docker inspect openbot >/dev/null 2>&1; then
  [[ $(docker inspect -f '{{.Id}}' openbot) != "$task_original_id" ]] || exit 1
  docker stop --time 60 openbot >/dev/null
  docker rm openbot >/dev/null
fi
cp -p "$task_private/template-before.xml" /boot/config/plugins/dockerMan/templates-user/my-openbot.xml
docker rename "$task_old" openbot
task_restart=$(jq -r '.[0].HostConfig.RestartPolicy.Name' "$task_private/container-before.json")
docker update --restart "$task_restart" openbot >/dev/null
docker start openbot >/dev/null
printf 'Original OpenBot container and template restored. Current /data retained. Backup: %s\n' "$task_private"
