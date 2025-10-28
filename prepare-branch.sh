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

# Detect available container runtime (Podman or Docker)
detect_container_runtime() {
	if command -v podman >/dev/null 2>&1; then
		echo "podman"
	elif command -v docker >/dev/null 2>&1; then
		echo "docker"
	else
		log_error "Neither podman nor docker is available"
		exit "$EXIT_NO_CONTAINER_RUNTIME"
	fi
}

# Validate required dependencies
validate_dependencies() {
	local missing_deps=()
	local check_bats="${1:-false}"
	local dep
	
	for dep in git sha512sum; do
		if ! command -v "$dep" >/dev/null 2>&1; then
			missing_deps+=("$dep")
		fi
	done
	
	# Only check for bats if running tests
	if [ "$check_bats" = "true" ]; then
		if ! command -v bats >/dev/null 2>&1; then
			missing_deps+=("bats")
		fi
	fi
	
	if [ ${#missing_deps[@]} -gt 0 ]; then
		log_error "Missing required dependencies: ${missing_deps[*]}"
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
	local arch
	local testimage
	
	arch="$(uname -m)"
	testimage="alpine:${branch#v}-test"
	
	log_info "Running tests for branch '$branch' on architecture '$arch'"
	
	if [ ! -d "$dir/$arch" ]; then
		log_error "Directory not found: $dir/$arch"
		return "$EXIT_INVALID_ARGS"
	fi
	
	"$CONTAINER_CMD" build -t "$testimage" "$dir/$arch/" || {
		log_error "Failed to build test image"
		return 1
	}
	
	BRANCH="$branch" bats ./tests/common.bats || {
		log_error "Tests failed"
		"$CONTAINER_CMD" rmi "$testimage" 2>/dev/null || true
		return 1
	}
	
	"$CONTAINER_CMD" rmi "$testimage" || log_error "Failed to remove test image"
	log_success "Tests passed for branch '$branch'"
}

# Prepare release directory
prepare() {
	local branch="${1:-$DEFAULT_BRANCH}"
	local dir
	
	log_info "Preparing branch: $branch"
	
	dir="$(mktemp -d "${TEMP_DIR_PREFIX}-XXXXXX")" || {
		log_error "Failed to create temporary directory"
		return 1
	}
	
	# Ensure directory exists and get absolute path
	if [ ! -d "$dir" ]; then
		log_error "Temporary directory was not created properly: $dir"
		return 1
	fi
	
	# Get absolute path
	dir="$(cd "$dir" && pwd)"
	log_info "Using temporary directory: $dir"
	
	log_info "Building fetch container..."
	"$CONTAINER_CMD" build -t docker-brew-alpine-fetch . || {
		log_error "Failed to build fetch container"
		rm -rf "$dir"
		return 1
	}
	
	log_info "Fetching Alpine release files..."
	
	# Special handling for Podman on macOS
	if [[ "$OSTYPE" == "darwin"* ]] && [ "$CONTAINER_CMD" = "podman" ]; then
		log_info "Detected Podman on macOS - ensuring directory is accessible to Podman VM"
		# Verify the directory is created and accessible
		if [ ! -w "$dir" ]; then
			log_error "Directory is not writable: $dir"
			rm -rf "$dir"
			return 1
		fi
	fi
	
	"$CONTAINER_CMD" run \
		${MIRROR+ -e "MIRROR=$MIRROR"} \
		--user "$(id -u)" --rm \
		-v "$dir:/out" \
		docker-brew-alpine-fetch "$branch" /out || {
		log_error "Failed to fetch release files"
		if [[ "$OSTYPE" == "darwin"* ]] && [ "$CONTAINER_CMD" = "podman" ]; then
			log_error "Podman on macOS may require specific mount points."
			log_error "Try: 'podman machine ssh' and check if volume mounts are configured."
			log_error "Directory used: $dir"
		fi
		rm -rf "$dir"
		return 1
	}
	
	log_info "Verifying checksums..."
	(cd "$dir" && sha512sum -c checksums.sha512) || {
		log_error "Checksum verification failed"
		rm -rf "$dir"
		return 1
	}
	
	log_success "Temporary directory created: $dir"
	
	# Run tests if bats is available
	if command -v bats >/dev/null 2>&1; then
		run_tests "$branch" "$dir" || {
			log_error "Tests failed, cleaning up"
			rm -rf "$dir"
			return 1
		}
	else
		log_info "Skipping tests (bats not installed)"
	fi
	
	echo ""
	log_info "To organize Dockerfiles into version directories run:"
	echo ""
	echo "  $SCRIPT_NAME organize $branch $dir"
	echo ""
	
	# Export for use by 'all' command
	TMPDIR="$dir"
}

# Organize Dockerfiles into version/architecture structure
organize_dockerfiles() {
	local branch="${1:?Branch name required}"
	local dir="${2:?Directory path required}"
	local version
	local target_dir
	local arch_dir
	
	if [ ! -d "$dir" ]; then
		log_error "Directory does not exist: $dir"
		show_help
		exit "$EXIT_INVALID_ARGS"
	fi
	
	# Check if directory is empty or doesn't have expected files
	if [ ! "$(ls -A "$dir" 2>/dev/null)" ]; then
		log_error "Directory is empty: $dir"
		log_error "Make sure the 'prepare' command completed successfully before running 'organize'"
		exit "$EXIT_INVALID_ARGS"
	fi
	
	if [ ! -f "$dir/VERSION" ]; then
		log_error "VERSION file not found in: $dir"
		log_error "Directory contents:"
		ls -la "$dir" >&2
		log_error "Make sure the 'prepare' command completed successfully before running 'organize'"
		exit "$EXIT_INVALID_ARGS"
	fi
	
	version="$(cat "$dir/VERSION")"
	
	# For edge branch, use 'edge' as directory name instead of version number
	if [ "$branch" = "edge" ]; then
		target_dir="${SCRIPT_DIR}/edge"
		log_info "Organizing Dockerfiles for edge branch (version: $version)"
	else
		target_dir="${SCRIPT_DIR}/${version}"
		log_info "Organizing Dockerfiles for version $version"
	fi
	
	# Create version directory if it doesn't exist
	if [ -d "$target_dir" ]; then
		log_info "Version directory already exists: $target_dir"
		if [ -t 0 ]; then
			# Interactive mode - ask user
			read -p "Do you want to overwrite it? (y/N): " -n 1 -r
			echo
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				log_error "Operation cancelled by user"
				exit "$EXIT_INVALID_ARGS"
			fi
		else
			# Non-interactive mode - fail safely
			log_error "Version directory already exists. Remove it first or run interactively."
			exit "$EXIT_INVALID_ARGS"
		fi
		rm -rf "$target_dir"
	fi
	
	mkdir -p "$target_dir"
	log_success "Created version directory: $target_dir"
	
	# Copy VERSION file to version directory
	cp "$dir/VERSION" "$target_dir/" || {
		log_error "Failed to copy VERSION file"
		exit 1
	}
	
	# Process each architecture directory
	for arch_src in "$dir"/*/; do
		[ -d "$arch_src" ] || continue
		
		local arch_name
		arch_name="$(basename "$arch_src")"
		
		# Skip if not a valid architecture directory (must contain Dockerfile)
		if [ ! -f "$arch_src/Dockerfile" ]; then
			log_info "Skipping $arch_name (no Dockerfile found)"
			continue
		fi
		
		arch_dir="$target_dir/$arch_name"
		mkdir -p "$arch_dir"
		
		log_info "Copying Dockerfile for architecture: $arch_name"
		
		# Copy all files from architecture directory
		cp -r "$arch_src"* "$arch_dir/" || {
			log_error "Failed to copy files for $arch_name"
			exit 1
		}
		
		log_success "Created: $arch_dir/Dockerfile"
	done
	
	# Clean up temporary directory
	rm -rf "$dir"
	
	echo ""
	log_success "Dockerfiles organized successfully!"
	echo ""
	log_info "Directory structure:"
	tree -L 2 "$target_dir" 2>/dev/null || find "$target_dir" -maxdepth 2 -type f -name "Dockerfile" | sort
	echo ""
	
	# Use the directory name (edge or version) for git instructions
	local dir_name
	dir_name="$(basename "$target_dir")"
	
	log_info "You can now commit these changes to git:"
	echo "  git add ${dir_name}"
	echo "  git commit -m 'feat: add Alpine ${dir_name} Dockerfiles'"
	echo ""
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
	local branch
	local dir
	
	# Show help immediately if requested
	if [ "$cmd" = "help" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "-h" ] || [ $# -eq 0 ]; then
		show_help
		exit "$EXIT_SUCCESS"
	fi
	
	# Validate basic dependencies first (git, sha512sum)
	validate_dependencies false
	
	shift
	
	branch="${1:-$DEFAULT_BRANCH}"
	dir="${2:-}"
	
	case "$cmd" in
		prepare)
			prepare "$branch"
			;;
		test)
			# Validate bats is available for test command
			validate_dependencies true
			if [ -z "$dir" ]; then
				log_error "Directory argument required for test command"
				show_help
				exit "$EXIT_INVALID_ARGS"
			fi
			run_tests "$branch" "$dir"
			;;
		organize)
			if [ -z "$dir" ]; then
				log_error "Directory argument required for organize command"
				show_help
				exit "$EXIT_INVALID_ARGS"
			fi
			organize_dockerfiles "$branch" "$dir"
			;;
		all)
			prepare "$branch"
			if [ -n "${TMPDIR:-}" ]; then
				organize_dockerfiles "$branch" "$TMPDIR"
			else
				log_error "TMPDIR not set after prepare"
				exit 1
			fi
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