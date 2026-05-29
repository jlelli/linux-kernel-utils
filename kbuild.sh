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
  vng-config      - Add virtme-ng required config options (use before build)
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
  KERNEL_APPEND   - Additional kernel cmdline parameters (default: empty)
  VIRTME_ROOT     - Path to chroot for cross-arch (default: auto-created)
  VIRTME_OPTS     - Extra options to pass to virtme-ng (default: empty)

Examples:
  # Basic usage (for virtme-ng testing)
  $0 defconfig
  $0 vng-config       # Add virtme-ng config options
  $0 build
  $0 run

  # Interactive shell in VM
  $0 run-shell

  # Run command in VM
  $0 run dmesg

  # Build for ARM64
  TARGET_ARCH=arm64 $0 build

  # Use custom build directory
  BUILD_DIR=build-rt $0 build

  # Run with custom virtme-ng options
  VIRTME_OPTS="--memory 4G --cpus 4" $0 run

  # Pass kernel command line parameters
  KERNEL_APPEND="loglevel=7 debug" $0 run

  # Permanent customization via local.sh
  Edit: $(dirname "$0")/local.sh
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
: ${KERNEL_APPEND:=""}
: ${VIRTME_ROOT:=""}
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
      echo ""
      echo "NOTE: To test with virtme-ng, run: $0 vng-config"
    else
      echo "Config already exists at ${BUILD_DIR}/.config"
    fi
    ;;

  "vng-config")
    # Check if virtme-ng is installed
    if ! command -v vng &> /dev/null; then
      echo "Error: virtme-ng not found"
      echo "Install with: pip install virtme-ng"
      exit 1
    fi

    echo "Adding virtme-ng required config options..."
    cd "${KERNEL_DIR}"

    # Build vng --kconfig command with architecture if needed
    VNG_KCONFIG_CMD="vng --kconfig O=\"${BUILD_DIR}\""

    # Add architecture for ARM64
    if [ "${TARGET_ARCH}" = "arm64" ]; then
      VNG_KCONFIG_CMD="${VNG_KCONFIG_CMD} --arch arm64"
    fi

    echo "Running ${VNG_KCONFIG_CMD}..."
    eval ${VNG_KCONFIG_CMD}

    echo ""
    echo "Config created at ${BUILD_DIR}/.config"
    echo "Next steps:"
    echo "  1. Run '$0 build' to build the kernel"
    echo "  2. Run '$0 run' or '$0 run-shell' to test with virtme-ng"
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
    echo ""

    # Build virtme-ng command with optional kernel parameters
    VNG_CMD="vng --run ${KERNEL_PATH}"

    # Add architecture if not native (requires --root for cross-arch)
    HOST_ARCH=$(uname -m)
    if [ "${TARGET_ARCH}" = "arm64" ] && [ "${HOST_ARCH}" != "aarch64" ]; then
      VNG_CMD="${VNG_CMD} --arch arm64"
      if [ -n "${VIRTME_ROOT}" ]; then
        VNG_CMD="${VNG_CMD} --root ${VIRTME_ROOT}"
      else
        # Auto-create chroot in ~/.cache/virtme-ng/
        DEFAULT_ROOT="${HOME}/.cache/virtme-ng/arm64-chroot"
        mkdir -p "${DEFAULT_ROOT}"
        VNG_CMD="${VNG_CMD} --root ${DEFAULT_ROOT} --root-release noble"
      fi
    elif [ "${TARGET_ARCH}" = "x86_64" ] && [ "${HOST_ARCH}" != "x86_64" ]; then
      VNG_CMD="${VNG_CMD} --arch amd64"
      if [ -n "${VIRTME_ROOT}" ]; then
        VNG_CMD="${VNG_CMD} --root ${VIRTME_ROOT}"
      else
        # Auto-create chroot in ~/.cache/virtme-ng/
        DEFAULT_ROOT="${HOME}/.cache/virtme-ng/amd64-chroot"
        mkdir -p "${DEFAULT_ROOT}"
        VNG_CMD="${VNG_CMD} --root ${DEFAULT_ROOT} --root-release noble"
      fi
    fi

    if [ -n "${KERNEL_APPEND}" ]; then
      VNG_CMD="${VNG_CMD} --append \"${KERNEL_APPEND}\""
    fi
    VNG_CMD="${VNG_CMD} ${VIRTME_OPTS}"

    # virtme-ng needs to be run from kernel source directory
    cd "${KERNEL_DIR}"
    if [ "$#" -gt 0 ]; then
      eval ${VNG_CMD} --exec \"$*\"
    else
      eval ${VNG_CMD}
    fi
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
    echo ""

    # Build virtme-ng command with optional kernel parameters
    VNG_CMD="vng --run ${KERNEL_PATH}"

    # Add architecture if not native (requires --root for cross-arch)
    HOST_ARCH=$(uname -m)
    if [ "${TARGET_ARCH}" = "arm64" ] && [ "${HOST_ARCH}" != "aarch64" ]; then
      VNG_CMD="${VNG_CMD} --arch arm64"
      if [ -n "${VIRTME_ROOT}" ]; then
        VNG_CMD="${VNG_CMD} --root ${VIRTME_ROOT}"
      else
        # Auto-create chroot in ~/.cache/virtme-ng/
        DEFAULT_ROOT="${HOME}/.cache/virtme-ng/arm64-chroot"
        mkdir -p "${DEFAULT_ROOT}"
        VNG_CMD="${VNG_CMD} --root ${DEFAULT_ROOT} --root-release noble"
      fi
    elif [ "${TARGET_ARCH}" = "x86_64" ] && [ "${HOST_ARCH}" != "x86_64" ]; then
      VNG_CMD="${VNG_CMD} --arch amd64"
      if [ -n "${VIRTME_ROOT}" ]; then
        VNG_CMD="${VNG_CMD} --root ${VIRTME_ROOT}"
      else
        # Auto-create chroot in ~/.cache/virtme-ng/
        DEFAULT_ROOT="${HOME}/.cache/virtme-ng/amd64-chroot"
        mkdir -p "${DEFAULT_ROOT}"
        VNG_CMD="${VNG_CMD} --root ${DEFAULT_ROOT} --root-release noble"
      fi
    fi

    if [ -n "${KERNEL_APPEND}" ]; then
      VNG_CMD="${VNG_CMD} --append \"${KERNEL_APPEND}\""
    fi
    VNG_CMD="${VNG_CMD} ${VIRTME_OPTS}"

    # virtme-ng needs to be run from kernel source directory
    # Without --exec, vng defaults to interactive mode
    cd "${KERNEL_DIR}"
    eval ${VNG_CMD} "$@"
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
