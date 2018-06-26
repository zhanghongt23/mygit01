#!/bin/bash
#
# Description	: Android Build Script.
# Authors		: jianjun jiang - jerryjianjun@gmail.com
# Version		: 2.00
# Notes			: None
#

#
# JAVA PATH
#
export PATH=/usr/lib/jvm/java-7-oracle/bin:$PATH

#
# Some Directories
#
BS_DIR_TOP=$(cd `dirname $0` ; pwd)
BS_DIR_RELEASE=${BS_DIR_TOP}/out/release
BS_DIR_TARGET=${BS_DIR_TOP}/out/target/product/x6818/
BS_DIR_UBOOT=${BS_DIR_TOP}/uboot
BS_DIR_KERNEL=${BS_DIR_TOP}/kernel
BS_DIR_BUILDROOT=${BS_DIR_TOP}/buildroot

#
# Cross Toolchain Path
#
BS_CROSS_TOOLCHAIN_BOOTLOADER=${BS_DIR_TOP}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-
BS_CROSS_TOOLCHAIN_KERNEL=${BS_DIR_TOP}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-

#
# Target Config
#
BS_CONFIG_BOOTLOADER_UBOOT=x6818_config
BS_CONFIG_KERNEL=x6818_defconfig
BS_CONFIG_FILESYSTEM=PRODUCT-x6818-userdebug
BS_CONFIT_BUILDROOT=x6818_defconfig

setup_environment()
{
	LANG=C
	cd ${BS_DIR_TOP};
	mkdir -p out/host/linux-x86/bin || return 1;
	mkdir -p ${BS_DIR_TARGET}/boot;

	[ -f "${BS_DIR_TOP}/out/host/linux-x86/bin/mkuserimg.sh" ] ||{ echo "tar generate boot.img tools"; tar xvf tools/generate_boot.tar.gz -C ${BS_DIR_TOP}/out/host/linux-x86/bin;}
	[ -f "${BS_DIR_TARGET}/boot/root.img.gz" ] ||{ echo "tar boot.tar.gz"; tar xvf tools/boot.tar.gz -C ${BS_DIR_TARGET};}

	PATH=${BS_DIR_TOP}/out/host/linux-x86/bin:$PATH;

	mkdir -p ${BS_DIR_RELEASE} || return 1
}

build_bootloader_uboot()
{
	# Compiler uboot
	cd ${BS_DIR_UBOOT} || return 1
	make distclean CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_BOOTLOADER} || return 1
	cp ${BS_DIR_UBOOT}/board/s5p6818/x6818/x6818-lcd.mk ${BS_DIR_UBOOT}/board/s5p6818/x6818/fastboot_lcd.o
	cp ${BS_DIR_UBOOT}/arch/arm/cpu/slsiap/devices/x6818-pmic.mk ${BS_DIR_UBOOT}/arch/arm/cpu/slsiap/devices/axp228_mfd.o
	cp net/x6818-eth.mk net/eth.o
	make ${BS_CONFIG_BOOTLOADER_UBOOT} CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_BOOTLOADER} || return 1
	make -j${threads} CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_BOOTLOADER} || return 1

	# Copy bootloader to release directory
	cp -v ${BS_DIR_UBOOT}/ubootpak.bin ${BS_DIR_RELEASE}
	cp -v ${BS_DIR_UBOOT}/readme.txt ${BS_DIR_RELEASE}
	cp -v ${BS_DIR_UBOOT}/env.txt ${BS_DIR_RELEASE}
	cp -v ${BS_DIR_UBOOT}/x6818-sdmmc.sh ${BS_DIR_RELEASE}

	echo "^_^ uboot path: ${BS_DIR_RELEASE}/ubootpak.bin"
	return 0
}

build_kernel()
{
	export PATH=${BS_DIR_UBOOT}/tools:$PATH 
	# Compiler kernel
	cd ${BS_DIR_KERNEL} || return 1
	make ${BS_CONFIG_KERNEL} ARCH=arm CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_KERNEL} || return 1
	make -j${threads} ARCH=arm CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_KERNEL} || return 1
	make -j${threads} ARCH=arm CROSS_COMPILE=${BS_CROSS_TOOLCHAIN_KERNEL} uImage || return 1

	# Copy uImage to release directory
	#cp -v ${BS_DIR_KERNEL}/arch/arm/boot/uImage ${BS_DIR_RELEASE}

	#echo "^_^ kernel path: ${BS_DIR_RELEASE}/uImage"

	# generate boot.img
	cd ${BS_DIR_TOP} || return 1
	echo 'boot.img ->' ${BS_DIR_RELEASE}
	# Make boot.img with ext4 format, 64MB
	cp -v ${BS_DIR_KERNEL}/arch/arm/boot/uImage ${BS_DIR_TARGET}/boot
	mkuserimg.sh -s ${BS_DIR_TARGET}/boot ${BS_DIR_TARGET}/boot.img ext4 boot 67108864

	cp -av ${BS_DIR_TARGET}/boot.img ${BS_DIR_RELEASE} || return 1;
	return 0
}

build_system()
{
	cd ${BS_DIR_TOP} || return 1
	source build/envsetup.sh || return 1
	make -j${threads} ${BS_CONFIG_FILESYSTEM} || return 1

	# Make boot.img
	# Create boot directory
	mkdir -p ${BS_DIR_TARGET}/boot || return 1

	# Copy some images to boot directory
	if [ -f ${BS_DIR_RELEASE}/uImage ]; then
		cp -v ${BS_DIR_RELEASE}/uImage ${BS_DIR_TARGET}/boot
	fi
	if [ -f ${BS_DIR_TARGET}/ramdisk.img ]; then
		cp -v ${BS_DIR_TARGET}/ramdisk.img ${BS_DIR_TARGET}/boot/root.img.gz
	fi
	if [ -f ${BS_DIR_TARGET}/ramdisk-recovery.img ]; then
		cp -v ${BS_DIR_TARGET}/ramdisk-recovery.img ${BS_DIR_TARGET}/boot
	fi

	# Make boot.img with ext4 format, 64MB
	mkuserimg.sh -s ${BS_DIR_TARGET}/boot ${BS_DIR_TARGET}/boot.img ext4 boot 67108864

	# Copy to release directory
	cp -av ${BS_DIR_TARGET}/boot.img ${BS_DIR_RELEASE} || return 1;
	cp -av ${BS_DIR_TARGET}/system.img ${BS_DIR_RELEASE} || return 1;
	cp -av ${BS_DIR_TARGET}/cache.img ${BS_DIR_RELEASE} || return 1;
	cp -av ${BS_DIR_TARGET}/recovery.img ${BS_DIR_RELEASE} || return 1;
	cp -av ${BS_DIR_TARGET}/userdata.img ${BS_DIR_RELEASE} || return 1;

	return 0
}

build_buildroot()
{
	# Compiler buildroot
	cd ${BS_DIR_BUILDROOT} || return 1
	make ${BS_CONFIT_BUILDROOT} || return 1
	make || return 1

	# Copy image to release directory
	cp -v ${BS_DIR_BUILDROOT}/output/images/rootfs.ext4 ${BS_DIR_RELEASE}/qt-rootfs.img
	cp -v ${BS_DIR_BUILDROOT}/qt-documents.txt ${BS_DIR_RELEASE}
}

threads=1
uboot=no
kernel=no
system=no
buildroot=no

if [ -z $1 ]; then
	uboot=yes
	kernel=yes
	system=yes
	buildroot=yes
fi

while [ "$1" ]; do
    case "$1" in
	-j=*)
		x=$1
		threads=${x#-j=}
		;;
	-u|--uboot)
		uboot=yes
	    ;;
	-k|--kernel)
	    kernel=yes
	    ;;
	-s|--system)
		system=yes
	    ;;
	-b|--buildroot)
	    buildroot=yes
	    ;;
	-a|--all)
		uboot=yes
		kernel=yes
		system=yes
		buildroot=yes
	    ;;
	-h|--help)
	    cat >&2 <<EOF
Usage: build.sh [OPTION]
Build script for compile the source of telechips project.

  -j=n                 using n threads when building source project (example: -j=16)
  -u, --uboot          build bootloader uboot from source
  -k, --kernel         build kernel from source
  -s, --system         build android file system from source
  -b, --buildroot      build buildroot file system for QT platform
  -a, --all            build all, include anything
  -h, --help           display this help and exit
EOF
	    exit 0
	    ;;
	*)
	    echo "build.sh: Unrecognised option $1" >&2
	    exit 1
	    ;;
    esac
    shift
done

setup_environment || exit 1

if [ "${uboot}" = yes ]; then
	build_bootloader_uboot || exit 1
fi

if [ "${kernel}" = yes ]; then
	build_kernel || exit 1
fi

if [ "${system}" = yes ]; then
	build_system || exit 1
fi

if [ "${buildroot}" = yes ]; then
	build_buildroot || exit 1
fi

exit 0
