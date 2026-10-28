#!/usr/bin/env bash
set -euo pipefail
task_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
for task_file in "$task_repo"/scripts/*.sh; do bash -n "$task_file"; done
php -l "$task_repo/scripts/update-template.php" >/dev/null
cat >"$task_tmp/old.json" <<'JSON'
[{"Config":{"Image":"official:0.52.1","User":"openbot","Env":["PRESERVE_THIS=fake-fixture-value"],"Entrypoint":["tini","--","openbot-container"],"Cmd":null,"StopTimeout":60,"Labels":{"fixture":"preserve"}},"HostConfig":{"Devices":[],"GroupAdd":null,"SecurityOpt":["seccomp=fixture","no-new-privileges:true"],"Binds":["/example/data:/data:rw"],"PortBindings":{},"Privileged":false,"ShmSize":1073741824,"RestartPolicy":{"Name":"unless-stopped","MaximumRetryCount":0}},"NetworkSettings":{"Networks":{"bridge":{"IPAMConfig":null,"Aliases":null,"DriverOpts":null,"NetworkID":"drop-runtime-value","IPAddress":"drop-runtime-value"}}}}]
JSON
jq --arg image ghcr.io/samjandris/openbot-intel-arc:unraid --arg device /dev/dri/renderD128 --arg gid 18 \
  -f "$task_repo/scripts/create-request.jq" "$task_tmp/old.json" >"$task_tmp/new.json"
jq -e --slurpfile old "$task_tmp/old.json" '
  .Image == "ghcr.io/samjandris/openbot-intel-arc:unraid" and
  .User == "openbot" and .Env == $old[0][0].Config.Env and
  .Entrypoint == $old[0][0].Config.Entrypoint and
  .HostConfig.SecurityOpt == $old[0][0].HostConfig.SecurityOpt and
  .HostConfig.Binds == $old[0][0].HostConfig.Binds and
  .HostConfig.PortBindings == {} and .HostConfig.Privileged == false and
  .HostConfig.ShmSize == 1073741824 and .StopTimeout == 60 and
  .HostConfig.GroupAdd == ["18"] and
  .HostConfig.Devices == [{PathOnHost:"/dev/dri/renderD128",PathInContainer:"/dev/dri/renderD128",CgroupPermissions:"rw"}] and
  .NetworkingConfig.EndpointsConfig.bridge == {}
' "$task_tmp/new.json" >/dev/null
cat >"$task_tmp/template.xml" <<'XML'
<?xml version="1.0"?><Container version="2"><Name>openbot</Name><Repository>official:0.52.1</Repository><Privileged>false</Privileged><ExtraParams>--security-opt=seccomp=/mnt/user/appdata/openbot/seccomp.json --security-opt=no-new-privileges:true --shm-size=1g --stop-timeout=60 --restart=unless-stopped</ExtraParams><Config Name="Data" Type="Path" Target="/data" Mode="rw">/example/data</Config></Container>
XML
php "$task_repo/scripts/update-template.php" "$task_tmp/template.xml" "$task_tmp/proposed.xml" \
  ghcr.io/samjandris/openbot-intel-arc:unraid /dev/dri/renderD128 18
php -r '
  $x=simplexml_load_file($argv[1]);
  assert((string)$x->Repository === "ghcr.io/samjandris/openbot-intel-arc:unraid");
  assert(str_contains((string)$x->ExtraParams,"--group-add=18"));
  assert(str_contains((string)$x->ExtraParams,"--security-opt=no-new-privileges:true"));
  assert((string)$x->Config[0] === "/example/data");
  assert((string)$x->Config[1]["Type"] === "Device");
  assert((string)$x->Config[1] === "/dev/dri/renderD128");
' -d zend.assertions=1 -d assert.exception=1 "$task_tmp/proposed.xml"
if php "$task_repo/scripts/update-template.php" "$task_tmp/proposed.xml" "$task_tmp/duplicate.xml" image /dev/dri/renderD128 18 2>/dev/null; then
  echo 'Duplicate group/device settings should require review.' >&2; exit 1
fi
printf 'PASS: shell/PHP syntax and private configuration preservation transforms.\n'
