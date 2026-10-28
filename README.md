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
# Browser graphics candidate

The Linux image has an explicit `OPENBOT_SERVER_GPU=1` opt-in. The extension adjusts only the
released server-mode input to the existing GPU policy. `OPENBOT_DISABLE_GPU=1`, GPU crash records
and unfinished-start records still select software rendering. The patch fails the build when the
upstream policy or expected configuration changes. It retains the original Electron binary, fuses,
entrypoint and sandbox. No host driver, primary DRM device or Docker socket is needed.

ANGLE uses Vulkan through the container's Intel Mesa driver. The X11 displays stay in place.
The explicit A380 opt-in selects Chromium's native Vulkan compositor with pixel-copy presentation.
This forces its Vulkan compatibility decision only for the expected Intel device; driver
workarounds and the sandbox stay in place. Hardware operation must be checked on the target GPU;
software CI cannot certify it. Another or missing render device selects software rendering.

Each opted-in startup writes a private GPU feature report in a newly created
`/tmp/openbot-graphics-*/report.json`. The default `OPENBOT_GPU_SELF_TEST=1` runs a transient browser
fixture in an in-memory partition. It checks Intel rendering, GPU compositing, WebGL, text input,
navigation, a green WebGL screenshot and CDP JPEG capture. It opens no remote debug port and reads
no existing browser profile. Set it to `0` to skip the fixture. These reports and images must stay private.

New builds publish immutable `VERSION-graphics.1-RUN-ATTEMPT` candidate tags. Until the repository
variable `GRAPHICS_ROLLING_APPROVED=true` is set, builds leave `:unraid` unchanged. The separate
promotion workflow moves an exact reviewed digest to `:unraid` without rebuilding. Enable rolling
publication only after target-machine validation. Daily upstream stable-release checks continue;
an incompatible patch fails the build and leaves the last published deployment tag intact.
