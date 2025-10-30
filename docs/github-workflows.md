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

## Image Registry

Images are published to GitHub Container Registry (ghcr.io) as multi-architecture images:

```bash
# Pull edge image (multi-arch)
docker pull ghcr.io/broadsage/alpine:edge

# Pull specific version (multi-arch)
docker pull ghcr.io/broadsage/alpine:3.19.9

# Pull latest stable (multi-arch)
docker pull ghcr.io/broadsage/alpine:latest

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
