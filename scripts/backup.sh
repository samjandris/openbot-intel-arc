#!/usr/bin/env bash
# Leaves only openbot stopped on success, for immediate replacement.
set -euo pipefail
umask 077
task_private=${1:?Usage: backup.sh NEW_PRIVATE_BACKUP_DIR}
[[ $(id -u) == 0 && ! -e $task_private ]] || exit 1
install -d -m 0700 -- "$task_private"
task_restart=false
trap 'task_rc=$?; if [[ $task_restart == true ]]; then docker start openbot >/dev/null || true; fi; exit "$task_rc"' EXIT
docker inspect openbot >"$task_private/container-before.json"
task_data=$(jq -r '.[0].Mounts[] | select(.Destination=="/data") | .Source' "$task_private/container-before.json")
[[ $task_data == /mnt/user/appdata/openbot/data && -d $task_data ]]
[[ $(jq -r '.[0].State.Running' "$task_private/container-before.json") == true ]]
task_id=$(jq -r '.[0].Id' "$task_private/container-before.json")
task_ids=$(docker ps -q)
if [[ -n $task_ids ]]; then
  docker inspect $task_ids | jq -e --arg data "$task_data" --arg id "$task_id" \
    'all(.[]; .Id == $id or all(.Mounts[]; .Source != $data))' >/dev/null
fi
cp -p /boot/config/plugins/dockerMan/templates-user/my-openbot.xml "$task_private/template-before.xml"
cp -p /mnt/user/appdata/openbot/seccomp.json "$task_private/seccomp-before.json"
cp -p /var/lib/docker/unraid-autostart "$task_private/unraid-autostart-before"
if [[ -f /boot/config/plugins/ca.update.applications/DockerUpdateSettings.json ]]; then
  cp -p /boot/config/plugins/ca.update.applications/DockerUpdateSettings.json "$task_private/updater-before.json"
fi
docker image inspect "$(jq -r '.[0].Image' "$task_private/container-before.json")" >"$task_private/image-before.json"
docker exec openbot openbot status >"$task_private/status-before.txt" 2>&1 || true
task_restart=true
docker stop --time 60 openbot >"$task_private/stop.log"
docker inspect openbot >"$task_private/container-stopped.json"
jq -e '.[0] | .State.Running == false and .State.OOMKilled == false and .State.ExitCode != 137' \
  "$task_private/container-stopped.json" >/dev/null
tar --xattrs --acls --numeric-owner --sparse -cpf "$task_private/data.tar" -C "$task_data" . \
  2>"$task_private/tar.log"
# Compare every archived regular file and its metadata with the stopped source.
tar --xattrs --acls --numeric-owner --compare -f "$task_private/data.tar" -C "$task_data" \
  >"$task_private/tar-compare.log" 2>&1
gzip -1 "$task_private/data.tar"
gzip -t "$task_private/data.tar.gz"
(cd "$task_private" && sha256sum data.tar.gz >data.tar.gz.sha256 && sha256sum -c data.tar.gz.sha256 >backup-verify.log)
chmod 0600 "$task_private"/*
touch "$task_private/BACKUP_VERIFIED"
task_restart=false
printf 'Consistent full data backup verified: %s/data.tar.gz\n' "$task_private"
