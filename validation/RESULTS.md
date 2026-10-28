# Validation procedure

GitHub Actions validates package installation, nonroot user and inherited
entrypoint/command, helper syntax, and configuration-preservation fixtures.
GitHub-hosted runners cannot certify hardware encoding without a GPU runner.

Run `openbot-gpu-test` on the actual host as OpenBot's nonroot user. It requires
an accessible mapped render node, initializes iHD through `vainfo`, performs a
two-second synthetic `h264_vaapi` CQP encode, counts frames with `ffprobe`, and
decodes the resulting file to check integrity. Encoder-list presence alone is
not a successful hardware test.

Keep host-specific results, Docker configuration, application status, backup
records, and complete logs private and outside this repository. Review any
proposed public validation excerpt separately before publication.
