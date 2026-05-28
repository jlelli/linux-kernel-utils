# This file is sourced in the middle of kbuild.sh, after environment variables
# are setup and before commands are run. You can use it to override defaults
# for your specific needs. For example:

## Cross-compile for arm64
# TARGET_ARCH=arm64

## Use a different build directory
# BUILD_DIR="${KERNEL_DIR}/build-custom"

## Use different make flags
# MAKE="make -j16 LLVM=1"

## Enable some kernel CONFIG by default as part of the .config generation
# if [ $COMMAND = "defconfig" ]; then
#   trap "scripts/config --file ${BUILD_DIR}/.config -e BPF_SYSCALL" EXIT
# fi

## Run make olddefconfig before a build (a bit slow)
# if [ $COMMAND = "build" ]; then
#   eval ${MAKE} O="${BUILD_DIR}" ARCH=${TARGET_ARCH} olddefconfig
# fi

## Make the build verbose
# SILENT_BUILD_FLAG=""

## Disable the build spinner
# SPINNER=0

## Use GCC instead of LLVM
# MAKE="make -j`nproc` CC='ccache gcc'"
