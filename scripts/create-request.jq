# Input: complete docker inspect snapshot. Output: private Docker API create body.
.[0] as $old
| $old.Config
| .Image = $image
| .HostConfig = $old.HostConfig
| .HostConfig.Devices = ((.HostConfig.Devices // []) + [{PathOnHost:$device, PathInContainer:$device, CgroupPermissions:"rw"}])
| .HostConfig.GroupAdd = (((.HostConfig.GroupAdd // []) + [$gid]) | unique)
| .NetworkingConfig = {EndpointsConfig: ($old.NetworkSettings.Networks | with_entries(.value |= {IPAMConfig, Links, Aliases, DriverOpts} | .value |= with_entries(select(.value != null))))}
