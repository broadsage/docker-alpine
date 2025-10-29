#!/usr/bin/env bash
#
# Alpine Linux Docker Image Branch Preparation Script
#
# Description: Automates the preparation and management of Alpine Linux Docker images
# Author: broadsage-containers
# License: See LICENSE file
#

set -euo pipefail

# Script constants
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use a temp directory that's more likely to work with Podman on macOS
# On macOS, Podman VM typically mounts the home directory
if [[ "$OSTYPE" == "darwin"* ]] && command -v podman >/dev/null 2>&1; then
	readonly TEMP_DIR_PREFIX="${HOME}/.cache/docker-brew-alpine"
	mkdir -p "${HOME}/.cache" 2>/dev/null || true
else
	readonly TEMP_DIR_PREFIX="/tmp/docker-brew-alpine"
fi

readonly DEFAULT_BRANCH="edge"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_NO_CONTAINER_RUNTIME=2
readonly EXIT_MISSING_DEPENDENCY=3

# Logging functions
log_info() {
	echo "=> [INFO] $*" >&2
}

log_error() {
	echo "=> [ERROR] $*" >&2
}

log_success() {
	echo "=> [SUCCESS] $*" >&2
}

log_warn() {
	echo "=> [WARN] $*" >&2
}

# Error handling with automatic exit
die() {
	local exit_code="${1:-1}"
	shift
	log_error "$@"
	exit "$exit_code"
}

# Cleanup trap handler
cleanup() {
	if [[ -n "${CLEANUP_TEMP_DIR:-}" && -d "${CLEANUP_TEMP_DIR}" ]]; then
		log_info "Cleaning up temporary directory: $CLEANUP_TEMP_DIR"
		rm -rf "$CLEANUP_TEMP_DIR"
	fi
}

trap cleanup EXIT INT TERM

# Validate directory exists and is not empty
validate_directory() {
	local dir="$1"
	local error_context="${2:-directory}"
	
	[[ -d "$dir" ]] || die "$EXIT_INVALID_ARGS" "Directory does not exist: $dir"
	[[ -n "$(ls -A "$dir" 2>/dev/null)" ]] || die "$EXIT_INVALID_ARGS" "Directory is empty: $dir"
}

# Validate directory has required file
require_file() {
	local file="$1"
	local context="${2:-file}"
	
	if [[ ! -f "$file" ]]; then
		log_error "$context not found: $file"
		if [[ -d "$(dirname "$file")" ]]; then
			log_error "Directory contents:"
			ls -la "$(dirname "$file")" >&2
		fi
		die "$EXIT_INVALID_ARGS" "Make sure the 'prepare' command completed successfully"
	fi
}

# Execute container command with error handling
run_container() {
	local description="$1"
	shift
	
	log_info "$description"
	"$CONTAINER_CMD" "$@" || die 1 "Failed: $description"
}

# Build container image
build_container_image() {
	local tag="$1"
	local context="$2"
	
	run_container "Building container image: $tag" build -t "$tag" "$context"
}

# Remove container image
remove_container_image() {
	local image="$1"
	
	"$CONTAINER_CMD" rmi "$image" 2>/dev/null || log_warn "Could not remove image: $image"
}

# Detect available container runtime (Podman or Docker)
detect_container_runtime() {
	# Force Docker if FORCE_DOCKER environment variable is set
	if [[ "${FORCE_DOCKER:-}" == "true" ]] && command -v docker >/dev/null 2>&1; then
		echo "docker"
		return
	fi
	
	# Prefer Podman, fallback to Docker
	local runtime
	for runtime in podman docker; do
		if command -v "$runtime" >/dev/null 2>&1; then
			echo "$runtime"
			return
		fi
	done
	
	die "$EXIT_NO_CONTAINER_RUNTIME" "Neither podman nor docker is available"
}

# Validate required dependencies
validate_dependencies() {
	local check_bats="${1:-false}"
	local -a required_deps=(git sha512sum)
	local -a missing_deps=()
	
	[[ "$check_bats" == "true" ]] && required_deps+=(bats)
	
	for dep in "${required_deps[@]}"; do
		command -v "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
	done
	
	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		log_error "Missing required dependencies: ${missing_deps[*]}"
		if [[ " ${missing_deps[*]} " =~ " bats " ]]; then
			log_error "Install bats to run tests. On macOS: brew install bats-core"
			log_error "Or skip the test command and use 'prepare' and 'organize' separately"
		fi
		exit "$EXIT_MISSING_DEPENDENCY"
	fi
}

# Set the container runtime command
readonly CONTAINER_CMD=$(detect_container_runtime)
log_info "Using container runtime: $CONTAINER_CMD"

# Run tests for a specific branch
run_tests() {
	local branch="${1:?Branch name required}"
	local dir="${2:?Directory path required}"
	local arch="$(uname -m)"
	local testimage="alpine:${branch#v}-test"
	
	log_info "Running tests for branch '$branch' on architecture '$arch'"
	
	validate_directory "$dir/$arch" "test directory"
	
	build_container_image "$testimage" "$dir/$arch/"
	
	# Run tests and cleanup regardless of result
	local test_result=0
	BRANCH="$branch" bats ./tests/common.bats || test_result=$?
	
	remove_container_image "$testimage"
	
	if [[ $test_result -ne 0 ]]; then
		die 1 "Tests failed for branch '$branch'"
	fi
	
	log_success "Tests passed for branch '$branch'"
}

# Create temporary directory for Alpine release preparation
create_temp_directory() {
	local dir
	dir="$(mktemp -d "${TEMP_DIR_PREFIX}-XXXXXX")" || die 1 "Failed to create temporary directory"
	
	# Get absolute path and set cleanup trap
	dir="$(cd "$dir" && pwd)"
	CLEANUP_TEMP_DIR="$dir"
	
	log_info "Using temporary directory: $dir"
	
	# Verify directory is writable (important for Podman on macOS)
	[[ -w "$dir" ]] || die 1 "Directory is not writable: $dir"
	
	echo "$dir"
}

# Fetch Alpine release files using container
fetch_alpine_release() {
	local branch="$1"
	local dir="$2"
	
	build_container_image "docker-brew-alpine-fetch" "."
	
	log_info "Fetching Alpine release files for branch: $branch"
	
	# Special notice for Podman on macOS
	if [[ "$OSTYPE" == "darwin"* && "$CONTAINER_CMD" == "podman" ]]; then
		log_info "Using Podman on macOS - directory accessible to Podman VM"
	fi
	
	"$CONTAINER_CMD" run \
		${MIRROR+ -e "MIRROR=$MIRROR"} \
		--user "$(id -u)" --rm \
		-v "$dir:/out" \
		docker-brew-alpine-fetch "$branch" /out || {
		log_error "Failed to fetch release files"
		if [[ "$OSTYPE" == "darwin"* && "$CONTAINER_CMD" == "podman" ]]; then
			log_error "Podman on macOS troubleshooting:"
			log_error "  - Ensure Podman machine is running: 'podman machine start'"
			log_error "  - Check volume mounts: 'podman machine ssh'"
			log_error "  - Directory used: $dir"
		fi
		die 1 "Release fetch failed"
	}
}

# Verify checksums of downloaded files
verify_checksums() {
	local dir="$1"
	
	log_info "Verifying checksums..."
	(cd "$dir" && sha512sum -c checksums.sha512) || die 1 "Checksum verification failed"
	log_success "Checksums verified successfully"
}

# Prepare release directory
prepare() {
	local branch="${1:-$DEFAULT_BRANCH}"
	local dir
	
	log_info "Preparing branch: $branch"
	
	dir="$(create_temp_directory)"
	fetch_alpine_release "$branch" "$dir"
	verify_checksums "$dir"
	
	# Run tests if bats is available
	if command -v bats >/dev/null 2>&1; then
		run_tests "$branch" "$dir"
	else
		log_info "Skipping tests (bats not installed)"
	fi
	
	echo ""
	log_success "Preparation completed successfully!"
	log_info "To organize Dockerfiles into version directories run:"
	echo ""
	echo "  $SCRIPT_NAME organize $branch $dir"
	echo ""
	
	# Export for use by 'all' command
	TMPDIR="$dir"
	# Prevent automatic cleanup since user needs this directory
	unset CLEANUP_TEMP_DIR
}

# Determine target directory name based on branch
get_target_directory() {
	local branch="$1"
	local version="$2"
	
	if [[ "$branch" == "edge" ]]; then
		echo "${SCRIPT_DIR}/edge"
	else
		# Extract major.minor from version (e.g., 3.19.9 -> 3.19)
		local major_minor
		major_minor="$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+' || echo "$version")"
		echo "${SCRIPT_DIR}/${major_minor}"
	fi
}

# Prompt user for directory overwrite confirmation
confirm_overwrite() {
	local target_dir="$1"
	
	[[ ! -d "$target_dir" ]] && return 0
	
	log_info "Version directory already exists: $target_dir"
	
	if [[ -t 0 ]]; then
		# Interactive mode - ask user
		read -p "Do you want to overwrite it? (y/N): " -n 1 -r
		echo
		[[ $REPLY =~ ^[Yy]$ ]] || die "$EXIT_INVALID_ARGS" "Operation cancelled by user"
		rm -rf "$target_dir"
	else
		# Non-interactive mode - fail safely
		die "$EXIT_INVALID_ARGS" "Version directory already exists. Remove it first or run interactively."
	fi
}

# Copy architecture Dockerfiles to target directory
copy_architecture_files() {
	local arch_src="$1"
	local target_dir="$2"
	local arch_name
	
	arch_name="$(basename "$arch_src")"
	
	# Skip if not a valid architecture directory
	if [[ ! -f "$arch_src/Dockerfile" ]]; then
		log_info "Skipping $arch_name (no Dockerfile found)"
		return 0
	fi
	
	local arch_dir="$target_dir/$arch_name"
	mkdir -p "$arch_dir"
	
	log_info "Copying Dockerfile for architecture: $arch_name"
	cp -r "$arch_src"* "$arch_dir/" || die 1 "Failed to copy files for $arch_name"
	log_success "Created: $arch_dir/Dockerfile"
}

# Display organized directory structure
show_directory_structure() {
	local target_dir="$1"
	local dir_name="$(basename "$target_dir")"
	
	echo ""
	log_success "Dockerfiles organized successfully!"
	echo ""
	log_info "Directory structure:"
	tree -L 2 "$target_dir" 2>/dev/null || find "$target_dir" -maxdepth 2 -type f -name "Dockerfile" | sort
	echo ""
	log_info "You can now commit these changes to git:"
	echo "  git add ${dir_name}"
	echo "  git commit -m 'feat: add Alpine ${dir_name} Dockerfiles'"
	echo ""
}

# Organize Dockerfiles into version/architecture structure
organize_dockerfiles() {
	local branch="${1:?Branch name required}"
	local dir="${2:?Directory path required}"
	
	validate_directory "$dir" "source directory"
	require_file "$dir/VERSION" "VERSION file"
	
	local version target_dir dir_name
	version="$(cat "$dir/VERSION")"
	target_dir="$(get_target_directory "$branch" "$version")"
	dir_name="$(basename "$target_dir")"
	
	# Log what we're doing
	if [[ "$branch" == "edge" ]]; then
		log_info "Organizing Dockerfiles for edge branch (version: $version)"
	else
		log_info "Organizing Dockerfiles for Alpine $version -> $dir_name/ directory"
	fi
	
	# Handle existing directory
	confirm_overwrite "$target_dir"
	
	# Create version directory and copy VERSION file
	mkdir -p "$target_dir"
	log_success "Created version directory: $target_dir"
	cp "$dir/VERSION" "$target_dir/" || die 1 "Failed to copy VERSION file"
	
	# Process each architecture directory
	for arch_src in "$dir"/*/; do
		[[ -d "$arch_src" ]] || continue
		copy_architecture_files "$arch_src" "$target_dir"
	done
	
	# Cleanup and display results
	rm -rf "$dir"
	show_directory_structure "$target_dir"
}

# Display help information
show_help() {
	cat <<EOF
Usage: $SCRIPT_NAME COMMAND [OPTIONS]

DESCRIPTION:
    Automates the preparation and management of Alpine Linux Docker images.
    Organizes Dockerfiles in version/architecture directory structure.

COMMANDS:
    prepare [BRANCH]     Fetch release latest minirootfs to a temp directory and
                         create Dockerfiles. Defaults to '$DEFAULT_BRANCH' branch.
                         
    test BRANCH DIR      Run tests for a specific branch and directory.
    
    organize BRANCH DIR  Organize Dockerfiles from temp directory into 
                         version/architecture structure.
                         Creates: <version>/<architecture>/Dockerfile
    
    all [BRANCH]         Run prepare and organize commands in sequence.

ENVIRONMENT VARIABLES:
    MIRROR               Override the Alpine mirror URL (optional).

DIRECTORY STRUCTURE:
    After running organize command, the structure will be:
    
    <version>/
    ├── VERSION
    ├── x86_64/
    │   └── Dockerfile
    ├── aarch64/
    │   └── Dockerfile
    └── armv7/
        └── Dockerfile

EXAMPLES:
    # Prepare the edge branch
    $SCRIPT_NAME prepare edge
    
    # Run tests
    $SCRIPT_NAME test v3.18 /tmp/docker-brew-alpine-xyz123
    
    # Organize Dockerfiles into version directories
    $SCRIPT_NAME organize v3.18 /tmp/docker-brew-alpine-xyz123
    
    # Run complete workflow
    $SCRIPT_NAME all v3.18

EXIT CODES:
    $EXIT_SUCCESS - Success
    $EXIT_INVALID_ARGS - Invalid arguments
    $EXIT_NO_CONTAINER_RUNTIME - No container runtime found
    $EXIT_MISSING_DEPENDENCY - Required dependency missing

REQUIREMENTS:
    - Container runtime (podman or docker)
    - git, sha512sum
    - bats (only required for test command)

NOTES:
    - On macOS with Podman, temporary files are stored in ~/.cache/docker-brew-alpine
      to ensure the Podman VM can access them.
    - Ensure your Podman machine is running: 'podman machine start'

EOF
}

# Main execution
main() {
	local cmd="${1:-}"
	
	# Show help if requested or no arguments
	if [[ "$cmd" =~ ^(help|--help|-h)$ || $# -eq 0 ]]; then
		show_help
		exit "$EXIT_SUCCESS"
	fi
	
	# Validate basic dependencies (git, sha512sum)
	validate_dependencies false
	
	shift
	local branch="${1:-$DEFAULT_BRANCH}"
	local dir="${2:-}"
	
	case "$cmd" in
		prepare)
			prepare "$branch"
			;;
		test)
			validate_dependencies true
			[[ -n "$dir" ]] || die "$EXIT_INVALID_ARGS" "Directory argument required for test command"
			run_tests "$branch" "$dir"
			;;
		organize)
			[[ -n "$dir" ]] || die "$EXIT_INVALID_ARGS" "Directory argument required for organize command"
			organize_dockerfiles "$branch" "$dir"
			;;
		all)
			prepare "$branch"
			[[ -n "${TMPDIR:-}" ]] || die 1 "TMPDIR not set after prepare"
			organize_dockerfiles "$branch" "$TMPDIR"
			;;
		*)
			log_error "Unknown command: $cmd"
			echo ""
			show_help
			exit "$EXIT_INVALID_ARGS"
			;;
	esac
}

# Run main function
main "$@"