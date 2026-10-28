# OpenBot with Intel Arc video encoding

A small image derived from `ghcr.io/nightly-labs/openbot`, adding Ubuntu FFmpeg,
`vainfo`, Intel's full-feature iHD media driver, and explicit video helpers.
GitHub Actions builds it; Unraid only pulls it.

The first image uses OpenBot **0.52.1**. CI resolves each official version to a
digest, preserves its nonroot user and entrypoint, validates the software, then
publishes an immutable version/run tag and the rolling `unraid` tag:

```text
ghcr.io/samjandris/openbot-intel-arc:unraid
ghcr.io/samjandris/openbot-intel-arc:0.52.1-a380.1-RUN_ID-RUN_ATTEMPT
```

Only agent video-processing commands select hardware encoding. Electron/browser
rendering, virtual displays, remote-desktop encoding, and inference are outside
this extension's scope. The upstream sandbox and security options stay enabled.

## Video commands

Run as OpenBot's configured UID/GID 1000:1000 with the render device's numeric
supplementary group. The tested deployment maps only `/dev/dri/renderD128` for
PCI `0000:2b:00.0` (Intel A380 `8086:56a5`) with group `18`; recheck these values
before deploying to a different host or after hardware changes.

```sh
docker exec openbot openbot-gpu-test /dev/dri/renderD128
docker exec openbot openbot-video-encode /data/input.mp4 /data/output.mp4
docker exec openbot openbot-video-encode /data/input.mp4 /data/cropped.mp4 'crop=1280:720:0:0'
```

CPU crop/subtitle filters run before `format=nv12,hwupload`; H.264 encoding uses
`h264_vaapi` in CQP mode. Existing outputs are not overwritten automatically.
`LIBVA_DRIVER_NAME=iHD` is scoped to the video commands. No CPU encoder fallback
is used by the hardware helper. `OPENBOT_VAAPI_DEVICE` selects a verified mapped
render node for the encode helper.

## Updates

The workflow starts pinned to `upstream-version.txt` (0.52.1). After initial
hardware validation, set repository variable `TRACK_UPSTREAM_STABLE=true`.
Scheduled and subsequent builds then select the latest non-draft, non-prerelease
OpenBot release. Daily checks rebuild the derived image with current Ubuntu media
packages. A failed build or software check cannot move the rolling tag. Each
successful run retains an immutable version/run tag and records its digest in
the Actions summary.

GitHub-hosted runners do **not** have an A380. CI checks installation, inherited
nonroot/entrypoint behavior, helper syntax and configuration transforms; the
actual VA-API initialization and encode test must run on Unraid. Future automatic
versions receive software checks, not advance hardware certification.

Actions uses its ephemeral `GITHUB_TOKEN` with `contents:read` and
`packages:write`. Public GHCR pulls need no persistent registry token on Unraid.
Keep the package public for the credential-free update path.

See [deployment and rollback](DEPLOYMENT.md) and [validation status](validation/RESULTS.md).

## Source boundary

The image context is assembled from exactly four explicit source files:
`Dockerfile`, `.dockerignore`, `scripts/gpu-test.sh`, and `scripts/video-encode.sh`.
The additional `.dockerignore` allowlist provides a second boundary. Git has an
explicit source allowlist. No appdata, inspect snapshots, credentials, keyrings,
browser profiles, backups, or deployment logs belong in this repository.

References: [official OpenBot 0.52.1 Docker documentation](https://github.com/nightly-labs/openbot/blob/v0.52.1/docs/docker.md),
[Intel media driver](https://github.com/intel/media-driver),
[GHCR authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
