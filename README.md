# Linux Kernel Build Utils

Minimalistic kernel build utilities for configuring and building Linux kernels in a separate build directory.

## Credits

This project is based on [linux-kernel-vscode](https://github.com/FlorentRevest/linux-kernel-vscode) by [Florent Revest](https://github.com/FlorentRevest), stripped down to core build functionality only.

The original project provides a comprehensive VSCode-based kernel development environment with VM testing, debugging, and much more. This simplified version extracts just the build-related tasks for users who want a minimal setup without VSCode integration.

**Original features removed:**
- VSCode integration, extensions, and tasks
- QEMU VM management and testing
- GDB debugging integration
- BPF selftests compilation and execution
- Syzkaller fuzzing setup
- Systemtap tracing
- Patchwork integration

## Features

- Configure kernel with `defconfig`, `menuconfig`, or `nconfig`
- Build kernel in separate `build/` directory
- LLVM/Clang build by default with ccache support
- Generates `compile_commands.json` for LSP/clangd
- Cross-compilation support (x86_64, arm64)
- Local configuration via `local.sh`

## Prerequisites

```bash
sudo apt install ccache clang clangd llvm lld libssl-dev libelf-dev \
                 bison flex yacc bc
```

## Usage

From any Linux kernel source tree:

```bash
# Create alias for convenience
alias kb=/path/to/linux-kernel-utils/kbuild.sh

# Generate default config (if not present)
kb defconfig

# Interactive configuration
kb menuconfig

# Build kernel
kb build

# Clean build artifacts
kb clean

# Deep clean (removes .config too)
kb mrproper
```

## Configuration

All builds use the `build/` directory by default. Customize behavior by editing `local.sh`:

```bash
# Example: Build for arm64
TARGET_ARCH=arm64

# Example: Use custom build directory
BUILD_DIR="${KERNEL_DIR}/build-rt"

# Example: Use GCC instead of LLVM
MAKE="make -j$(nproc) CC='ccache gcc'"
```

## Environment Variables

Override defaults via environment or `local.sh`:

- `KERNEL_DIR` - Kernel source directory (default: current directory)
- `BUILD_DIR` - Build output directory (default: `${KERNEL_DIR}/build`)
- `TARGET_ARCH` - Target architecture (default: `x86_64`, also: `arm64`)
- `MAKE` - Make command with flags (default: uses LLVM/Clang with ccache)
- `SILENT_BUILD_FLAG` - Make verbosity (default: `-s` for silent)
- `SPINNER` - Show build spinner (default: `1`)

## Multiple Configs

Use different build directories for different configs:

```bash
# Regular config
BUILD_DIR=build kb build

# RT config
BUILD_DIR=build-rt kb defconfig
BUILD_DIR=build-rt kb menuconfig
BUILD_DIR=build-rt kb build

# Debug config
BUILD_DIR=build-debug kb build
```

## Output

Built kernel image: `build/arch/${TARGET_ARCH}/boot/{bzImage|Image}`  
Compile commands: `build/compile_commands.json`  
Config file: `build/.config`
