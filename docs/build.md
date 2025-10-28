# Build

Normally, it is sufficient to simply run `docker pull alpine:tag` to get a locally cached image.
However, you can use the scripts present in this repository to build your own local copies.

## Automatic

You can use `prepare-branch.sh` in order to generate the tarballs and Dockerfiles necessary to create an Alpine image for all of the supported architectures.
Simply decide which release of alpine you wish to be able to build (such as `v3.19` or `edge`) and call the `prepare` function of `prepare-branch.sh`.

For example, to generate edge images, you would run:

```bash
prepare-branch.sh prepare edge
```

This will create a directory under `~/.cache/docker-brew-alpine` (on macOS) or `/tmp` (on Linux), download release tarballs for the selected version, generate necessary Dockerfiles, run tests and print the directory.

To organize the Dockerfiles into version/architecture structure:

```bash
prepare-branch.sh organize edge /path/to/temp/directory
```

Or run the complete workflow:

```bash
prepare-branch.sh all edge
```

> **Note**: This process currently relies on Alpine already being available as a specific tagged image.
