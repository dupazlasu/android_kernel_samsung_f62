#!/bin/bash

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit -1
}

unset_flags()
{
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -k, --ksu [Y/n]          Include KernelSU
    -p, --permissive [y/N]   Force SELinux status to permissive
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        --permissive|-p)
            PERMISSIVE_OPTION="$2"
            shift 2
            ;;
        *)\
            unset_flags
            exit 1
            ;;
    esac
done

echo "Preparing the build environment..."

pushd $(dirname "$0") > /dev/null
CORES=`cat /proc/cpuinfo | grep -c processor`

# Define toolchain variables
CLANG_DIR=$PWD/toolchain/neutron_18
PATH=$CLANG_DIR/bin:$PATH

# Check if toolchain exists
if [ ! -f "$CLANG_DIR/bin/clang-18" ]; then
    echo "-----------------------------------------------"
    echo "Toolchain not found! Downloading..."
    echo "-----------------------------------------------"
    rm -rf $CLANG_DIR
    mkdir -p $CLANG_DIR
    pushd toolchain/neutron_18 > /dev/null
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S=05012024
    echo "-----------------------------------------------"
    echo "Patching toolchain..."
    echo "-----------------------------------------------"
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") --patch=glibc
    echo "-----------------------------------------------"
    echo "Cleaning up..."
    popd > /dev/null
fi

MAKE_ARGS="
LLVM=1 \
LLVM_IAS=1 \
ARCH=arm64 \
O=out
"

if [[ "$KSU_OPTION" != "n" ]]; then
    KSU=ksu.config
fi

if [[ "$PERMISSIVE_OPTION" == "y" ]]; then
    PERMISSIVE=permissive.config
fi

rm -rf build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# Build kernel image
echo "-----------------------------------------------"
echo "Defconfig: "$KERNEL_DEFCONFIG""
if [ -z "$KSU" ]; then
    echo "KSU: No"
else
    echo "KSU: Yes"
fi

if [ -z "$PERMISSIVE" ]; then
    echo "PERMISSIVE: No"
else
    echo "PERMISSIVE: Yes"
fi

echo "-----------------------------------------------"
echo "Building kernel using "$KERNEL_DEFCONFIG""
echo "Generating configuration file..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES neoochii_defconfig common.config $KSU $PERMISSIVE || abort

echo "Building kernel..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES || abort

# Define constant variables
KERNEL_PATH=build/out/$MODEL/Image
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0xf0000000
TAGS_OFFSET=0x00000100
BASE=0x10000000
CMDLINE='loop.max_part=7'
HASHTYPE=sha1
HEADER_VERSION=2
OS_PATCH_LEVEL=2025-01
OS_VERSION=14.0.0
PAGESIZE=2048
RAMDISK=build/out/$MODEL/ramdisk.cpio.gz
OUTPUT_FILE=build/out/$MODEL/boot.img
BOARD=SRPTK19A007KU

## Build auxiliary boot.img files
# Copy kernel to build
cp out/arch/arm64/boot/Image build/out/$MODEL

# Build dtbo
echo "Building Device Tree Blob Output Image for "M62"..."
echo "-----------------------------------------------"
./toolchain/mkdtimg cfg_create build/out/dtbo.img build/dtconfigs/m62.cfg -d out/arch/arm64/boot/dts/samsung
echo "-----------------------------------------------"

# Build ramdisk
echo "Building RAMDisk..."
echo "-----------------------------------------------"
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
popd > /dev/null
echo "-----------------------------------------------"

# Create boot image
echo "Creating boot image..."
echo "-----------------------------------------------"
./toolchain/mkbootimg --base $BASE --board $BOARD --cmdline "$CMDLINE" --hashtype $HASHTYPE \
--header_version $HEADER_VERSION --kernel $KERNEL_PATH --kernel_offset $KERNEL_OFFSET \
--os_patch_level $OS_PATCH_LEVEL --os_version $OS_VERSION --pagesize $PAGESIZE \
--ramdisk $RAMDISK --ramdisk_offset $RAMDISK_OFFSET --second_offset $SECOND_OFFSET \
--tags_offset $TAGS_OFFSET -o $OUTPUT_FILE || abort

# Build zip
echo "Building zip..."
echo "-----------------------------------------------"
cp build/out/boot.img build/out/zip/files/boot.img
cp build/out/dtbo.img build/out/zip/files/dtbo.img
cp build/update-binary build/out/zip/META-INF/com/google/android/update-binary
cp build/updater-script build/out/zip/META-INF/com/google/android/updater-script

    version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/neoochii_defconfig | cut -d '"' -f 2)

version=${version:1}

pushd build/out/$MODEL/zip > /dev/null
DATE=`date +"%d-%m-%Y_%H-%M-%S"`    

if [[ "$KSU_OPTION" == "y" ]]; then
    NAME="$version"_"M62"_UNOFFICIAL_KSU_"$DATE".zip
else
    NAME="$version"_"M62"_UNOFFICIAL_"$DATE".zip
fi
zip -r ../"$NAME" .
popd > /dev/null
popd > /dev/null

echo "Build finished successfully!"