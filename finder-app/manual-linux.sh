#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]; then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p "${OUTDIR}" || { echo "Directory: ${OUTDIR} could not be created"; exit 1; }

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    # Clone only if the repository does not exist.
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    git clone "${KERNEL_REPO}" --depth 1 --single-branch --branch "${KERNEL_VERSION}" || { echo "Failed to clone kernel repository"; exit 1; }
fi
if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout "${KERNEL_VERSION}" || { echo "Failed to checkout kernel version"; exit 1; }

    make clean || { echo "Failed to clean kernel build"; exit 1; }
    # Clean the kernel build tree
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper || { echo "Failed to clean kernel build tree"; exit 1; }
    # Generate the config for our dev board
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig || { echo "Failed to generate kernel config"; exit 1; }
    # Build the kernel image
    make -j4 ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" all || { echo "Failed to build kernel image"; exit 1; }
    # Build the device tree
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" dtbs || { echo "Failed to build device tree"; exit 1; }
fi

echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/" || { echo "Failed to copy kernel image"; exit 1; }

echo "Creating the staging directory for the root filesystem"
cd "${OUTDIR}"
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf "${OUTDIR}/rootfs" || { echo "Failed to delete existing rootfs directory"; exit 1; }
fi

# Creating rootfs directory
mkdir -p "${OUTDIR}/rootfs" || { echo "Failed to create rootfs directory"; exit 1; }
cd "${OUTDIR}/rootfs"

# Creating needed directories under rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    git clone git://busybox.net/busybox.git || { echo "Failed to clone BusyBox repository"; exit 1; }
    cd busybox
    git checkout "${BUSYBOX_VERSION}" || { echo "Failed to checkout BusyBox version"; exit 1; }

    # Configure busybox
    make distclean || { echo "Failed to clean BusyBox build"; exit 1; }
    make defconfig || { echo "Failed to configure BusyBox"; exit 1; }
else
    cd busybox
fi

# Make and install busybox in our roofs directory
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" || { echo "Failed to build BusyBox"; exit 1; }
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" install || { echo "Failed to install BusyBox"; exit 1; }

echo "Library dependencies"
cd "${OUTDIR}/rootfs"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# Obtaining Sysroot path
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

# Add library dependencies to rootfs
cp "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib" || { echo "Failed to copy ld-linux library"; exit 1; }
cp "${SYSROOT}/lib64/libm.so.6" "${OUTDIR}/rootfs/lib64" || { echo "Failed to copy libm.so.6"; exit 1; }
cp "${SYSROOT}/lib64/libc.so.6" "${OUTDIR}/rootfs/lib64" || { echo "Failed to copy libc.so.6"; exit 1; }
cp "${SYSROOT}/lib64/libresolv.so.2" "${OUTDIR}/rootfs/lib64" || { echo "Failed to copy libresolv.so.2"; exit 1; }

# Make device nodes: minimal rootFS only needs null and console
sudo mknod -m 666 dev/null c 1 3 || { echo "Failed to create device node: null"; exit 1; }
sudo mknod -m 600 dev/console c 5 1 || { echo "Failed to create device node: console"; exit 1; }

# Clean and build the writer utility using cross compiling
cd "${FINDER_APP_DIR}"
make clean || { echo "Failed to clean writer utility"; exit 1; }
make CROSS_COMPILE="${CROSS_COMPILE}" || { echo "Failed to build writer utility"; exit 1; }

# Copy the finder related scripts and executables to the /home directory on the target rootfs
cp finder-test.sh finder.sh "${OUTDIR}/rootfs/home" || { echo "Failed to copy finder scripts"; exit 1; }
cp -rf conf/ "${OUTDIR}/rootfs/home" || { echo "Failed to copy conf directory"; exit 1; }

# Copying the writer app crosscompiled
cp writer "${OUTDIR}/rootfs/home" || { echo "Failed to copy writer application"; exit 1; }

# Copying autorun-qemu.sh into /home in the rootfs
cp autorun-qemu.sh "${OUTDIR}/rootfs/home" || { echo "Failed to copy autorun-qemu.sh"; exit 1; }

# Chown the root directory
cd "${OUTDIR}/rootfs"
sudo chown -R root:root * || { echo "Failed to change ownership of rootfs files"; exit 1; }

# Create initramfs.cpio.gz
find . | cpio -H newc -

