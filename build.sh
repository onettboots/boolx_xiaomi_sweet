#!/bin/bash
#
# Compile script for kernel
#
KERNEL_DIR="${PWD}"

# Bash Color
yellow='\033[01;33m'
green='\033[01;32m'
red='\033[01;31m'
blink_red='\033[05;31m'
restore='\033[0m'

# Help
HELP=$(cat <<EOF
--------------------------------
       Boolx Kernel Build
================================
  --clean  : Clean build
  --ksu    : Build KSU Next Only
  --susfs  : Build KSU and SUSFS
--------------------------------
EOF
)

# Variables
SECONDS=0 # builtin bash timer
DEVICE=sweet
TOOLCHAINS=$HOME/toolchains/boolx-clang
SAVEHERE=$HOME/toolchains
KER_VER=$(grep -oP '(?<=VERSION = )\d+|(?<=PATCHLEVEL = )\d+|(?<=SUBLEVEL = )\d+' Makefile | paste -sd '.')
CFG=arch/arm64/configs/sweet_defconfig
kernel="out/arch/arm64/boot/Image.gz"
dtbo="out/arch/arm64/boot/dtbo.img"
dtb="out/arch/arm64/boot/dtb.img"

export ARCH=arm64
export KBUILD_BUILD_USER=onett
export KBUILD_BUILD_HOST=boots
export PATH="$HOME/toolchains/boolx-clang/bin/:$PATH"
export CC=$HOME/toolchains/boolx-clang/clang
export LC_ALL=C
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache)
#export CCACHE_DIR="$HOME/toolchains/ccache" #localbuild
ccache -M 10G

clear
echo -e "${green}"
echo "$HELP"
echo -e "${restore}"

echo -e "${green}"
echo "----------------------"
echo "Checking Toolchains:"
echo "----------------------"
echo -e "${restore}"
sleep 1
if [ -d $TOOLCHAINS ]; then
   echo -e "${red}"
   echo "Bool-x clang is ready..!!"
   echo -e "${restore}"
else
   echo -e "${green}"
   echo "Toolchains Architecture Host:"
   echo "1. ARCH64"
   echo "2. X86"
   while read -p "Choose your architecture (1 / 2)? " cchoice
do
case "$cchoice" in
        1 )
                echo
                echo "Downloading Boolx-clang for Aarch64 host."
                git clone https://gitlab.com/onettboots/boolx-clang.git -b Clang-15.0 $TOOLCHAINS
                break
                ;;
        2 )
                echo
                echo "Downloading Boolx-clang 21.0.0 for X86 host."
                wget https://github.com/onettboots/boolx-clang-build/releases/download/Boolx-21/boolx-clang21.tar.gz -P $SAVEHERE
                cd $SAVEHERE
                echo "Extracting Boolx Clang 21.0.0 to $HOME/toolchains/:"
                tar -xf boolx-clang21.tar.gz
                break
                ;;
        * )
                echo
                echo "Invalid try again!"
                echo
                ;;
esac
done
   echo
fi
sleep 1
clear
echo -e "${green}"
echo "$HELP"
echo -e "${restore}"

echo -e "${green}"
echo "-----------------------"
echo " USAGE :"
echo "-----------------------"
echo -e "${restore}"
if [[ $1 = "--clean" ]]; then
    rm -rf out
    echo -e "${red}""- Clean build""${restore}"
else
    echo -e "${red}""- Dirty build""${restore}"
fi
sleep 1
enable_ksu=n
enable_susfs=n

for arg in "$@"; do
    case "$arg" in
        --ksu) enable_ksu=y;;
        --susfs) enable_susfs=y;;
    esac
done

if grep -q "^CONFIG_KSU=" "$CFG"; then
    sed -i "s/^CONFIG_KSU=.*/CONFIG_KSU=$enable_ksu/" "$CFG"
else
    echo "CONFIG_KSU=$enable_ksu" >> "$CFG"
fi
echo -e "${red}- KSU $( [ $enable_ksu = y ] && echo Enabled || echo Disabled )${restore}"

sleep 1
if grep -q "^CONFIG_KSU_SUSFS=" "$CFG"; then
    sed -i "s/^CONFIG_KSU_SUSFS=.*/CONFIG_KSU_SUSFS=$enable_susfs/" "$CFG"
else
    echo "CONFIG_KSU_SUSFS=$enable_susfs" >> "$CFG"
fi
echo -e "${red}- SUSFS $( [ $enable_susfs = y ] && echo Enabled || echo Disabled )${restore}"

echo -e "${green}"
echo "-----------------------"
echo " Starting Build !"
echo "-----------------------"
echo -e "${restore}"
make -s O=out ARCH=arm64 ${DEVICE}_defconfig

filezip=$(ls $KERNEL_DIR/*.zip 2>/dev/null | wc -l)

if (( filezip == 1 )); then
  total_lines=43
elif (( filezip > 1 )); then
  total_lines=64
else
  total_lines=7000
fi

#if [ -f "out/vmlinux.o" ] || [ ! -f "out/.config.old" ]; then
#        total_lines=43
#elif [ -f "out/vmlinux.o" ] || [ -f "" ]; then
#        total_lines=3710
#else
#        total_lines=7000
#fi
echo -e "${yellow}"
#total_lines=43
count=0
bar_length=50
make -j$(nproc) \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee logs.txt | while IFS= read -r line; do

    ((count++))
    percent=$(( count * 100 / total_lines ))
    (( percent > 100 )) && percent=100

    filled=$(( percent * bar_length / 100 ))
    empty=$(( bar_length - filled ))

    #echo "$line"

    printf "\rBuilding: [%-${bar_length}s] %3d%%" \
        "$(printf '#%.0s' $(seq 1 $filled))$(printf '.%.0s' $(seq 1 $empty))" \
        "$percent"

done
echo -e "${restore}"
echo -e "${green}"
if [ ! -f "$kernel" ] || [ ! -f "$dtbo" ] || [ ! -f "$dtb" ]; then
        echo -e "\nCompilation failed! see logs.txt and fix it"
        exit 1
fi
echo -e "\nKernel compiled successfully! Zipping up...\n"
echo -e "${restore}"

echo -e "${red}"
if [ -d "$AK3_DIR" ]; then
        cp -r $AK3_DIR AnyKernel3
else
        if ! git clone -q https://github.com/onettboots/boolx_anykernel -b sweet AnyKernel3; then
                echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
                exit 1
        fi
fi

cp $kernel AnyKernel3
cp $dtbo AnyKernel3
cp $dtb AnyKernel3
cd AnyKernel3

function make_zip {
                cd $KERNEL_DIR/AnyKernel3
                ksu=$(cd $KERNEL_DIR && grep -q '^CONFIG_KSU=y' $CFG && echo "y" || echo "n")
                susfs=$(cd $KERNEL_DIR && grep -q '^CONFIG_KSU_SUSFS=y' $CFG && echo "y" || echo "n")

                if [[ $ksu == "y" && $susfs == "y" ]]; then
                  ZIPNAME="Boolx-${DEVICE}-$(date '+%Y%m%d-%H%M')-KSUNEXT-SUSFS.zip"
                  zip -r9 "../$ZIPNAME" * -x .git
                  KSU_VER=$(cat $KERNEL_DIR/drivers/kernelsu/kernel/dksu 2>/dev/null)
                  SUSFS_VER=$(grep -oP '(?<=#define SUSFS_VERSION ")[^"]*' $KERNEL_DIR/include/linux/susfs.h 2>/dev/null)
                elif [[ $ksu == "y" && $susfs == "n" ]]; then
                  ZIPNAME="Boolx-${DEVICE}-$(date '+%Y%m%d-%H%M')-KSUNEXT.zip"
                  zip -r9 "../$ZIPNAME" * -x .git
                  KSU_VER=$(cat $KERNEL_DIR/drivers/kernelsu/kernel/dksu 2>/dev/null)
                  SUSFS_VER=Disabled
                elif [[ $ksu == "n" && $susfs == "n" ]]; then
                  ZIPNAME="Boolx-${DEVICE}-$(date '+%Y%m%d-%H%M').zip"
                  zip -r9 "../$ZIPNAME" * -x .git
                  KSU_VER=Disabled
                  SUSFS_VER=Disabled
                else
                  ZIPNAME="Boolx-${DEVICE}-$(date '+%Y%m%d-%H%M').zip"
                  zip -r9 "../$ZIPNAME" * -x .git
                  KSU_VER=Disabled
                  SUSFS_VER=Disabled
                fi
                cd $KERNEL_DIR
                rm -rf AnyKernel3
}

make_zip
echo -e "${restore}"
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo -e "${blink_red}"
echo "  FILE: $ZIPNAME"
echo -e "${restore}"

function upload() {
        source $KERNEL_DIR/.dump
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$ZIPNAME" "$USER@$HOST:$REMOTE_DIR"
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
		sed -i '9i\* Type: AOSP' $upl
		sed -i '10i\* Changes: https://github.com/onettboots/boolx_xiaomi_sweet/commits/ksunext' $upl
            	sed -i '11i\* Clang: Boolx Clang 21.0.0"' $upl
            	bash $upl
}

if [[ -f "$KERNEL_DIR/.dump" ]]; then
    upload
elif [[ -f "$KERNEL_DIR/upl.sh" ]]; then
    upload_tg
else
    echo ""
fi

rm -rf $kernel $dtb $dtbo
cd $KERNEL_DIR
git restore $CFG
