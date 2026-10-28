# Deployment and exact rollback procedure

These scripts target the inspected Unraid installation. Run as root on Unraid
from a clean checkout of this repository. Never run a second OpenBot instance
against the same `/data` directory. Build only through GitHub Actions.

## Initial replacement

1. Confirm the published workflow built **0.52.1**, and copy the published digest
   from its summary. Confirm public, anonymous pulling works before stopping
   production. Verify the A380 PCI node and device group still match the script.
2. Obtain action-time approval for mapping only `/dev/dri/renderD128` and adding
   numeric group `18`. Preserve seccomp, no-new-privileges, nonroot user, 1 GiB
   shared memory, all original ports/mounts/environment, and the stop timeout.
3. Run, replacing the timestamp and digest with the concrete reviewed values:

```sh
cd /mnt/user/appdata/openbot-intel-arc-source
bash scripts/deploy.sh --device-access-approved \
  /mnt/user/appdata/openbot/.a380-private/YYYYMMDDTHHMMSSZ \
  ghcr.io/samjandris/openbot-intel-arc:unraid \
  sha256:PUBLISHED_DIGEST
```

Before stopping, the script pulls and verifies the approved image. It privately
captures the complete Docker inspect, image configuration, original managed
template, seccomp, Unraid autostart and updater settings. It stops only OpenBot,
requires a non-OOM/non-forced-kill exit, archives **all** `/data` including hidden
keyring/config material with ownership, ACLs, xattrs and sparse files, compares
the archive against the stopped source, tests gzip, and records SHA-256.
Private directories are root-owned mode 0700; records are mode 0600.

The original stopped container is renamed and retained with restart disabled.
The replacement inherits the original configuration through the host Docker API;
only image and the approved device/group change. The socket is never mounted
inside OpenBot. The managed template retains the new repository/device/group so
future Unraid edits and updates preserve them. The script checks configuration
preservation, real nonroot iHD/H.264 encode and decode, and OpenBot status. On
failure after replacement it attempts to restore the retained original container.

Verify the existing account/server and configuration in the OpenBot client. Raw
status and application logs remain private. Only synthetic test logs may be
copied into a sanitized report after review.

## Roll back the initial image/configuration, retaining current data

Use the **same concrete private directory printed by deployment**:

```sh
cd /mnt/user/appdata/openbot-intel-arc-source
bash scripts/rollback.sh /mnt/user/appdata/openbot/.a380-private/YYYYMMDDTHHMMSSZ
```

This stops/removes only the replacement container (without `-v`), copies the
original template back, renames the retained original container to `openbot`,
restores its restart policy and starts it. The complete current data directory
stays in place. Never start the retained original while the replacement runs.

## Restore the pre-deployment data as well, if necessary

This deliberately moves the current data aside instead of deleting it. Run only
with OpenBot stopped; make sure the backup path is the correct verified one.

```sh
docker stop --time 60 openbot
cd /mnt/user/appdata/openbot/.a380-private/YYYYMMDDTHHMMSSZ
sha256sum -c data.tar.gz.sha256
gzip -t data.tar.gz
mv /mnt/user/appdata/openbot/data /mnt/user/appdata/openbot/data-before-restore-YYYYMMDDTHHMMSSZ
mkdir -m 0700 /mnt/user/appdata/openbot/data
tar --xattrs --acls --numeric-owner --same-owner -xzpf data.tar.gz -C /mnt/user/appdata/openbot/data
docker start openbot
```

Archive extraction restores ownership and permissions, including the data root.
Do not recursively chown shared appdata or change host device permissions.

## Normal Unraid updates

Use the installed CA Auto Update Applications plugin and its existing schedule.
Confirm `openbot` is included in its current global/per-container policy. No
replacement scheduler, Docker socket mount, or extra OpenBot instance is needed.
The rolling `unraid` tag is updated only after CI software checks succeed.
An immutable tag/digest can be put in the managed template to pin or roll back a
later version. A later upstream database migration may require a matching data
backup; preserve complete `/data` before such a restore.
