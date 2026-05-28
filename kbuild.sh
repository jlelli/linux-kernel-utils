#!/bin/bash

# Minimalistic kernel build script
# Based on linux-kernel-vscode by Florent Revest
# Original: https://github.com/FlorentRevest/linux-kernel-vscode
# Stripped down for build-only workflows

set -e

# Help function
function show_help() {
  cat <<EOF
Linux Kernel Build Utilities

Usage: $0 <command> [args...]

Commands:
  help            - Show this help message
  defconfig       - Generate default .config if absent
  menuconfig      - Interactive kernel configuration (ncurses)
  nconfig         - Alternative ncurses-based configuration
  build           - Build kernel with compile_commands.json
  run             - Run built kernel in VM with virtme-ng
  run-shell       - Run built kernel and drop to interactive shell
  clean           - Clean build artifacts (keeps .config)
  mrproper        - Deep clean (removes .config too)

Environment Variables:
  KERNEL_DIR      - Kernel source directory (default: current directory)
  BUILD_DIR       - Build output directory (default: \${KERNEL_DIR}/build)
  TARGET_ARCH     - Target architecture (default: x86_64, also: arm64)
  MAKE            - Make command with flags (default: LLVM/Clang with ccache)
  SPINNER         - Show build spinner (default: 1, set to 0 to disable)
  VIRTME_OPTS     - Extra options to pass to virtme-ng (default: empty)

Examples:
  # Basic usage
  $0 defconfig
  $0 menuconfig
  $0 build
  $0 run

  # Interactive shell in VM
  $0 run-shell

  # Run command in VM
  $0 run -- dmesg

  # Build for ARM64
  TARGET_ARCH=arm64 $0 build

  # Use custom build directory
  BUILD_DIR=build-rt $0 build

  # Run with custom virtme-ng options
  VIRTME_OPTS="--memory 4G --cpus 4" $0 run

  # Permanent customization via local.sh
  Edit: $(dirname "$0")/local.sh

Based on linux-kernel-vscode by Florent Revest
https://github.com/FlorentRevest/linux-kernel-vscode
EOF
}

# Arguments extraction
if [ "$#" -lt 1 ]; then
  show_help
  exit 1
fi
COMMAND=$1

# See https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
# for the `: ${var:=DEFAULT}` syntax
: ${SCRIPT:=`realpath -s "$0"`}
: ${SCRIPT_DIR:=`dirname "${SCRIPT}"`}

# Default context variables, can be overridden by local.sh or in environment.
: ${KERNEL_DIR:=`pwd`}
: ${BUILD_DIR:="${KERNEL_DIR}/build"}
: ${MAKE:="make -j`nproc` LLVM=1 LLVM_IAS=1 CC='ccache clang'"}
: ${TARGET_ARCH:="x86_64"}
: ${SILENT_BUILD_FLAG:="-s"}
: ${SPINNER:=1}
: ${VIRTME_OPTS:=""}

# Let the user override environment variables for their special needs
if [ -f "${SCRIPT_DIR}/local.sh" ]; then
  source "${SCRIPT_DIR}/local.sh"
fi

# Convenience environment variables derived from the context
if [ "${TARGET_ARCH}" = "x86_64" ]; then
  : ${VMLINUX:="bzImage"}
  : ${TOOLS_SRCARCH:="x86"}
elif [ "${TARGET_ARCH}" = "arm64" ]; then
  : ${VMLINUX:="Image"}
  : ${TOOLS_SRCARCH:="arm64"}
else
  echo "Unsupported TARGET_ARCH:" $TARGET_ARCH
  exit 2
fi

: ${KERNEL_PATH:="${BUILD_DIR}/arch/${TARGET_ARCH}/boot/${VMLINUX}"}

# Handle help command early (before kernel tree check)
if [[ "${COMMAND}" == "help" ]] || [[ "${COMMAND}" == "-h" ]] || [[ "${COMMAND}" == "--help" ]]; then
  show_help
  exit 0
fi

# Ensure we're in a kernel tree for all other commands
if [ ! -f "Kbuild" ] && [ ! -f "Makefile" ]; then
  echo "Error: This doesn't look like a Linux kernel source tree"
  exit 1
fi

# Create build directory if needed
mkdir -p "${BUILD_DIR}"

# Spinner function for long-running commands
function spinner() {
  local pid=$1

  if [[ "$SPINNER" -eq 1 ]]; then
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local i=0
    tput civis # Hide cursor
    while kill -0 $pid 2>/dev/null; do
      local i=$(((i + 1) % ${#spin}))
      printf "%s" "${spin:$i:1}" # Print one character
      echo -en "\033[1D" # Go back one character
      sleep .1
    done
    tput cnorm # Restore cursor
  fi

  wait $pid
  return $?
}

# Ensure we're in a kernel tree
if [ ! -f "Kbuild" ] && [ ! -f "Makefile" ]; then
  echo "Error: This doesn't look like a Linux kernel source tree"
  exit 1
fi

# Create build directory if needed
mkdir -p "${BUILD_DIR}"

case "${COMMAND}" in
  "help"|"-h"|"--help")
    show_help
    exit 0
    ;;

  "defconfig")
    # Only generate .config if it doesn't already exist
    if [ ! -f ${BUILD_DIR}/.config ]; then
      echo "Generating defconfig for ${TARGET_ARCH}..."
      eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} defconfig
      # Enable DWARF debug info by default
      scripts/config --file "${BUILD_DIR}/.config" --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
      eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} olddefconfig
      echo "Config generated at ${BUILD_DIR}/.config"
    else
      echo "Config already exists at ${BUILD_DIR}/.config"
    fi
    ;;

  "menuconfig")
    # Ensure we have a config first
    if [ ! -f ${BUILD_DIR}/.config ]; then
      $SCRIPT defconfig
    fi
    eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} menuconfig
    ;;

  "nconfig")
    # Ensure we have a config first
    if [ ! -f ${BUILD_DIR}/.config ]; then
      $SCRIPT defconfig
    fi
    eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} nconfig
    ;;

  "build")
    # Ensure we have a config first
    if [ ! -f ${BUILD_DIR}/.config ]; then
      $SCRIPT defconfig
    fi

    # Enable reproducible builds for ccache
    export KBUILD_BUILD_TIMESTAMP=""
    # Generate not only the kernel but also the clangd config
    CMD="${MAKE} O=\"${BUILD_DIR}\" ${SILENT_BUILD_FLAG} ARCH=${TARGET_ARCH} all compile_commands.json"
    echo ${CMD}
    eval ${CMD} &
    spinner $!

    echo "Build complete: ${KERNEL_PATH}"
    ;;

  "clean")
    eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} clean
    ;;

  "mrproper")
    eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} mrproper
    echo "Deep clean complete (config removed)"
    ;;

  "run")
    # Ensure kernel is built
    if [ ! -f ${KERNEL_PATH} ]; then
      echo "Kernel not found at ${KERNEL_PATH}"
      echo "Run '$0 build' first"
      exit 1
    fi

    # Check if virtme-ng is installed
    if ! command -v vng &> /dev/null; then
      echo "Error: virtme-ng not found"
      echo "Install with: pip install virtme-ng"
      exit 1
    fi

    shift
    echo "Running kernel with virtme-ng..."
    echo "Kernel: ${KERNEL_PATH}"
    echo "Build dir: ${BUILD_DIR}"
    echo ""
    vng --build-dir "${BUILD_DIR}" ${VIRTME_OPTS} "$@"
    ;;

  "run-shell")
    # Ensure kernel is built
    if [ ! -f ${KERNEL_PATH} ]; then
      echo "Kernel not found at ${KERNEL_PATH}"
      echo "Run '$0 build' first"
      exit 1
    fi

    # Check if virtme-ng is installed
    if ! command -v vng &> /dev/null; then
      echo "Error: virtme-ng not found"
      echo "Install with: pip install virtme-ng"
      exit 1
    fi

    shift
    echo "Running kernel with virtme-ng (interactive shell)..."
    echo "Kernel: ${KERNEL_PATH}"
    echo "Build dir: ${BUILD_DIR}"
    echo ""
    vng --build-dir "${BUILD_DIR}" ${VIRTME_OPTS} "$@" --shell
    ;;

  "help"|"-h"|"--help")
    # Already handled above
    ;;

  *)
    echo "Invalid command: ${COMMAND}"
    echo "Run '$0 help' to see available commands"
    exit 1
    ;;
esac
