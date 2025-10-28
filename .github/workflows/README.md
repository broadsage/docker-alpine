# GitHub Actions Workflows

This directory contains automated workflows for building and publishing Alpine Linux Docker images.

## Workflows

### 1. Build and Push Alpine Images (`build-and-push.yml`)

Automatically builds and publishes multi-architecture Docker images to GitHub Container Registry.

**Triggers:**

- Push to `master` branch (when Alpine version directories change)
- Pull requests (builds without pushing)
- Manual workflow dispatch with version selection

**Features:**

- Multi-architecture support (amd64, arm64, armv7, armhf, i386, ppc64le, s390x, riscv64)
- Automatic version detection from directory structure
- Creates manifest lists for multi-arch images
- Tags images appropriately:
  - `edge`: Latest edge build
  - `X.Y.Z`: Full version number
  - `X.Y`: Major.minor version
  - `latest`: Latest stable release
- Uses Docker layer caching for faster builds

**Manual Usage:**

```bash
# Build all versions
gh workflow run build-and-push.yml

# Build specific version
gh workflow run build-and-push.yml -f version=edge
gh workflow run build-and-push.yml -f version=3.19.9
```

### 2. Prepare Alpine Release (`prepare-release.yml`)

Prepares new Alpine Linux releases by downloading minirootfs tarballs and generating Dockerfiles.

**Triggers:**

- Manual workflow dispatch

**Inputs:**

- `branch`: Alpine branch to prepare (e.g., `edge`, `v3.19`, `v3.20`)
- `create_pr`: Whether to create a pull request (default: true)

**Process:**

1. Downloads Alpine minirootfs tarballs for all architectures
2. Verifies checksums
3. Generates Dockerfiles
4. Runs automated tests
5. Creates a pull request (or commits directly)

**Usage:**

```bash
# Prepare edge release (creates PR)
gh workflow run prepare-release.yml -f branch=edge -f create_pr=true

# Prepare v3.19 release (commit directly)
gh workflow run prepare-release.yml -f branch=v3.19 -f create_pr=false
```

### 3. Update Alpine Releases (`update-releases.yml`)

Scheduled workflow that checks for new Alpine releases and automatically prepares them.

**Triggers:**

- Daily at 2 AM UTC (cron schedule)
- Manual workflow dispatch

**Process:**

1. Checks if edge has been updated
2. Checks for new stable version releases
3. Automatically triggers prepare-release workflow if updates found
4. Creates pull requests for review

## Image Registry

Images are published to GitHub Container Registry (ghcr.io) as multi-architecture images:

```bash
# Pull edge image (multi-arch)
docker pull ghcr.io/broadsage-containers/alpine:edge

# Pull specific version (multi-arch)
docker pull ghcr.io/broadsage-containers/alpine:3.19.9

# Pull latest stable (multi-arch)
docker pull ghcr.io/broadsage-containers/alpine:latest

# Docker automatically pulls the correct architecture for your platform
# Supported: linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6, 
#            linux/386, linux/ppc64le, linux/s390x, linux/riscv64
```

## Architecture Support

All images are published as multi-architecture manifests, supporting:

| Alpine Arch | Docker Platform |
|-------------|----------------|
| x86_64      | linux/amd64    |
| aarch64     | linux/arm64    |
| armv7       | linux/arm/v7   |
| armhf       | linux/arm/v6   |
| x86         | linux/386      |
| ppc64le     | linux/ppc64le  |
| s390x       | linux/s390x    |
| riscv64     | linux/riscv64  |

**Note:** Docker/Podman automatically selects the correct architecture for your platform when pulling images.

## Secrets and Permissions

### Required Permissions

The workflows use `GITHUB_TOKEN` which is automatically provided by GitHub Actions. Ensure the following permissions are granted in repository settings:

- **contents**: write (for committing changes)
- **packages**: write (for pushing to GHCR)
- **pull-requests**: write (for creating PRs)

### No Additional Secrets Required

All workflows use the built-in `GITHUB_TOKEN` and don't require additional secrets.

## Manual Operations

### Prepare a New Release Locally

```bash
# Prepare edge
./prepare-branch.sh all edge

# Prepare v3.19
./prepare-branch.sh all v3.19

# Commit and push
git add edge/  # or version directory
git commit -m "feat: add Alpine edge Dockerfiles"
git push
```

The build workflow will automatically trigger and build the images.

### Trigger Builds Manually

```bash
# Using GitHub CLI
gh workflow run build-and-push.yml

# Using GitHub web interface
# Navigate to Actions -> Build and Push Alpine Images -> Run workflow
```

## Troubleshooting

### Build Failures

1. **Architecture-specific failures**: Check if the Dockerfile exists for that architecture
2. **Manifest creation failures**: Ensure all architecture builds completed successfully
3. **Permission errors**: Verify repository has packages write permission

### Update Detection Issues

If automatic updates aren't being detected:

1. Check the schedule in `update-releases.yml`
2. Review workflow run logs
3. Manually trigger the update workflow

## Development

### Testing Workflow Changes

1. Create a feature branch
2. Modify workflows in `.github/workflows/`
3. Push to branch
4. Test using workflow_dispatch or create a PR

### Adding New Architectures

1. Add architecture to the matrix in `build-and-push.yml`
2. Add architecture mapping in metadata extraction step
3. Update documentation

## Monitoring

View workflow status:

- GitHub Actions tab in repository
- Workflow badges (add to README.md)
- GitHub notifications for failed workflows

## Cost Optimization

- Workflows use GitHub-hosted runners (free for public repos)
- Docker layer caching reduces build times
- Conditional jobs prevent unnecessary runs
- Matrix strategy allows parallel builds
