# QNM_BBB U-Boot Build And SD Boot Guide

Tai lieu nay mo ta cach build U-Boot cho board QNM_BBB, copy U-Boot vao the SD, va boot bang SD bang cach nhan giu nut SW2.

## 1. Yeu cau

- Linux host
- ARM cross toolchain cho Cortex-A8 / AM335x
- The SD da duoc gan vao may build

Vi du prefix toolchain dang dung trong repo nay:

```bash
export CROSS_COMPILE=/home/<user>/x-tools/arm-cortex_a8-linux-gnueabi/bin/arm-cortex_a8-linux-gnueabi-
```

## 2. Build U-Boot

Tu root cua repo:

```bash
make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} qnm_bbb_defconfig
make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc)
```

File output quan trong:

- `MLO`
- `u-boot.img`
- `u-boot.bin`
- `u-boot-dtb.img`
- `arch/arm/dts/am335x-qnm-bbb.dtb`

Neu chi muon boot vao U-Boot prompt tu SD thi 2 file bat buoc la:

- `MLO`
- `u-boot.img`

## 3. Chuan bi the SD

Kich ban don gian nhat la tao 1 phan vung FAT32 de chua `MLO` va `u-boot.img`.

Canh bao: thay `/dev/sdX` bang dung ten thiet bi cua the SD. Lenh ben duoi se xoa du lieu tren the SD.

```bash
sudo umount /dev/sdX1 2>/dev/null || true
sudo parted -s /dev/sdX mklabel msdos
sudo parted -s /dev/sdX mkpart primary fat32 4MiB 256MiB
sudo parted -s /dev/sdX set 1 boot on
sudo mkfs.vfat -F 32 /dev/sdX1
```

## 4. Copy U-Boot vao the SD

```bash
sudo mkdir -p /mnt/qnm-sd
sudo mount /dev/sdX1 /mnt/qnm-sd
sudo cp MLO u-boot.img /mnt/qnm-sd/
sync
sudo umount /mnt/qnm-sd
```

Ghi chu:

- `MLO` phai nam o phan vung FAT cua the SD.
- `u-boot.img` cung nam cung cho voi `MLO`.
- Neu muon boot Linux tu cung the SD, copy them kernel, dtb va file boot script / extlinux config vao phan vung boot hoac rootfs tuy cach ban to chuc he thong.

Vi du neu muon de them DTB cua board:

```bash
sudo mount /dev/sdX1 /mnt/qnm-sd
sudo cp arch/arm/dts/am335x-qnm-bbb.dtb /mnt/qnm-sd/
sync
sudo umount /mnt/qnm-sd
```

## 5. Boot bang SD tren board

Tren board QNM_BBB clone tu BeagleBone Black, de ep boot bang SD:

1. Tat nguon board.
2. Cam the SD da chep `MLO` va `u-boot.img`.
3. Nhan va giu nut `SW2`.
4. Trong khi van giu `SW2`, cap nguon hoac reset board.
5. Tiep tuc giu `SW2` trong vai giay dau tien de ROM uu tien boot tu SD.
6. Tha `SW2` sau khi thay log SPL / U-Boot xuat hien tren UART.

Neu boot thanh cong, ban se thay log tu SPL va sau do vao U-Boot prompt.

## 6. Kiem tra nguon boot trong U-Boot

Ban co the dung lenh da them san trong board port nay:

```bash
bootsrc
```

Lenh nay se hien:

- board dang boot tu `sd` hay `emmc`
- ROM dang thay `MMC1` hay `MMC2`
- mapping giua ROM boot source va U-Boot mmc index

Ban cung co the xem env:

```bashs
printenv boot_source boot_mmcdev board_name board_rev
```

## 7. Neu khong boot duoc tu SD

Kiem tra lai cac diem sau:

- Da giu `SW2` dung cach trong luc cap nguon.
- File `MLO` va `u-boot.img` nam o phan vung FAT32 dau tien.
- The SD duoc format dung va board doc duoc the.
- UART console dang noi vao dung cong serial.
- Ban dang dung file moi build ra tu target `qnm_bbb_defconfig`.

## 8. Lenh build nhanh

```bash
export CROSS_COMPILE=/home/<user>/x-tools/arm-cortex_a8-linux-gnueabi/bin/arm-cortex_a8-linux-gnueabi-
make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} qnm_bbb_defconfig
make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc)
```