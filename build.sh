#!/bin/bash
#
# Compile script for kernel
#
KERNEL_DIR="${PWD}"

SECONDS=0 # builtin bash timer

# Allowed codenames
ALLOWED_CODENAMES=("sweet" "courbet" "tucana" "toco" "phoenix" "davinci")

# Prompt user for device codename
# read -p "Enter device codename: " DEVICE
DEVICE=sweet

# Check if the entered codename is in the allowed list
if [[ ! " ${ALLOWED_CODENAMES[@]} " =~ " ${DEVICE} " ]]; then
    echo "Error: Invalid codename. Allowed codenames are: ${ALLOWED_CODENAMES[*]}"
    exit 1
fi

ZIPNAME="Boolx-${DEVICE}-$(date '+%Y%m%d-%H%M')-Nethunter.zip"

export ARCH=arm64
export KBUILD_BUILD_USER=aryan
export KBUILD_BUILD_HOST=celeste
export PATH="$HOME/toolchains/boolx-clang/bin/:$PATH"
export CC=$HOME/toolchains/boolx-clang/bin/clang
export LC_ALL=C
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache)
#export CCACHE_DIR="$HOME/toolchains/ccache" # its for local build #
ccache -M 10G

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out
	echo "Cleaned output folder"
fi

echo -e "\nStarting compilation for $DEVICE...\n"
make O=out ARCH=arm64 ${DEVICE}_defconfig
make -s -j$(nproc) \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-

kernel="out/arch/arm64/boot/Image.gz"
dtbo="out/arch/arm64/boot/dtbo.img"
dtb="out/arch/arm64/boot/dtb.img"

if [ ! -f "$kernel" ] || [ ! -f "$dtbo" ] || [ ! -f "$dtb" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

echo -e "\nKernel compiled successfully! Zipping up...\n"

if [ -d "$AK3_DIR" ]; then
	cp -r $AK3_DIR AnyKernel3
else
	if ! git clone -q https://github.com/basamaryan/AnyKernel3 -b master AnyKernel3; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
fi

# Modify anykernel.sh to replace device names
sed -i "s/device\.name1=.*/device.name1=${DEVICE}/" AnyKernel3/anykernel.sh
sed -i "s/device\.name2=.*/device.name2=${DEVICE}in/" AnyKernel3/anykernel.sh

cp $kernel AnyKernel3
cp $dtbo AnyKernel3
cp $dtb AnyKernel3
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git
cd ..
rm -rf AnyKernel3
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	HASH="$(echo $head | cut -c1-8)"
fi

KER_VER=$(grep -oP '(?<=VERSION = )\d+|(?<=PATCHLEVEL = )\d+|(?<=SUBLEVEL = )\d+' Makefile | paste -sd '.')
KSU_VER=$(cat drivers/kernelsu/kernel/dksu 2>/dev/null || echo "Disabled")
SUSFS_VER=$(grep -oP '(?<=#define SUSFS_VERSION ")[^"]*' include/linux/susfs.h 2>/dev/null || echo "Disabled")

function upload() {
        source $KERNEL_DIR/.dump
        sshpass -p "$PASSWORD" scp "$ZIPNAME" "$USER@$HOST:$REMOTE_DIR"
}

function upload_tg()
{
		cd $KERNEL_DIR
		upl=$KERNEL_DIR/upl.sh
		chmod +x $upl
		sed -i "4i\FILE_PATH=$KERNEL_DIR/$ZIPNAME" $upl
		BUILDDATE=`date +"%Y-%m-%d"`
		sed -i '5i\CAPTION="* Build Date: '$BUILDDATE'' $upl
		sed -i '6i\* Kernel Version: '$KER_VER'' $upl
		sed -i '7i\* KSU+NEXT: '$KSU_VER'' $upl
		sed -i '8i\* SUSFS: '$SUSFS_VER'' $upl
		sed -i '9i\* Type: AOSP, Nethunter' $upl
		#sed -i '10i\* Changes: https://github.com/onettboots/bool-x_xiaomi_raphael/commits/14-DSPcr' $upl
            	sed -i '10i\* Clang: Boolx Clang 19.0.0"' $upl
            	bash $upl
}

if [ -f $KERNEL_DIR/.dump ]; then
	upload
else
	exit 1
fi

if [ -f $KERNEL_DIR/upl.sh ]; then
        upload_tg
else
        exit 1
fi
