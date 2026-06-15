# Lộ Trình Bringup Board Radxa Rock 4D

> **Tài liệu tham khảo chính thức:** https://docs.radxa.com/en/rock4/rock4d  
> **Ngày cập nhật:** 2026-06-10

---

## Mục Lục

1. [Tổng quan phần cứng](#1-tổng-quan-phần-cứng)
2. [Chuẩn bị môi trường](#2-chuẩn-bị-môi-trường)
3. [Sơ đồ phân cấp phần mềm](#3-sơ-đồ-phân-cấp-phần-mềm)
4. [Bước 1 – Cài đặt Yocto SDK](#4-bước-1--cài-đặt-yocto-sdk)
5. [Bước 2 – Cấu hình build cho Rock 4D](#5-bước-2--cấu-hình-build-cho-rock-4d)
6. [Bước 3 – Build U-Boot (Bootloader)](#6-bước-3--build-u-boot-bootloader)
7. [Bước 4 – Build Kernel Linux](#7-bước-4--build-kernel-linux)
8. [Bước 5 – Build root filesystem & image](#8-bước-5--build-root-filesystem--image)
9. [Bước 6 – Flash image lên board](#9-bước-6--flash-image-lên-board)
10. [Bước 7 – Kiểm tra và debug sau boot](#10-bước-7--kiểm-tra-và-debug-sau-boot)
11. [Bước 8 – Bringup từng subsystem](#11-bước-8--bringup-từng-subsystem)
12. [Tài liệu tham khảo](#12-tài-liệu-tham-khảo)

---

## 1. Tổng Quan Phần Cứng

### SoC: Rockchip RK3576

| Thành phần | Chi tiết |
|---|---|
| **SoC** | Rockchip RK3576 |
| **CPU** | ARM Cortex-A72/A53 (ARMv8-A, 64-bit) |
| **GPU** | Mali-G52 Bifrost (g13p0) |
| **NPU** | Rockchip NPU |
| **ISP** | RKAIQ ISP version 3.9 |
| **WiFi/Bluetooth** | AIC8800D80 (USB interface) |
| **Serial Console** | ttyFIQ0 @ 1,500,000 baud |
| **Display** | Wayland / X11 |

### Machine Name (Yocto)

```
MACHINE = "rockchip-rk3576-rock-4d"
```

### Device Tree

```
rockchip/rk3576-rock-4d.dtb
```

### Các image tham khảo có sẵn

| Image | Mô tả |
|---|---|
| `Rock4d-Androod14-rkr6-sd-20250527-gpt.img` | Android 14 (RKR6), dùng cho SD card |
| `radxa-rk3576_bookworm_kde_r6.output_512.img` | Debian Bookworm + KDE Plasma |

---

## 2. Chuẩn Bị Môi Trường

### 2.1 Yêu cầu hệ thống Host

| Yêu cầu | Tối thiểu |
|---|---|
| **OS** | Ubuntu 20.04 / 22.04 LTS (64-bit) |
| **RAM** | 8 GB (khuyến nghị 16 GB) |
| **Disk** | 100 GB trống |
| **CPU** | 4 cores (khuyến nghị 8+) |

### 2.2 Cài đặt các gói phụ thuộc

```bash
sudo apt-get update && sudo apt-get install -y \
    gawk wget git-core diffstat unzip texinfo gcc-multilib \
    build-essential chrpath socat cpio python3 python3-pip \
    python3-pexpect xz-utils debianutils iputils-ping \
    python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev \
    pylint xterm zstd liblz4-tool file python3-subunit \
    locales libelf-dev
```

### 2.3 Cài đặt `repo` tool (nếu dùng Android/AOSP)

```bash
mkdir -p ~/.bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+x ~/.bin/repo
export PATH="${HOME}/.bin:${PATH}"
```

### 2.4 Công cụ flash

- **upgrade_tool** (rkdeveloptool): http://opensource.rock-chips.com/wiki_Upgradetool
- **rkdeveloptool** (open-source version): https://github.com/rockchip-linux/rkdeveloptool

---

## 3. Sơ Đồ Phân Cấp Phần Mềm

```
┌─────────────────────────────────────────────┐
│               User Application              │
├─────────────────────────────────────────────┤
│        Root Filesystem (Yocto Image)        │
│   (core-image-minimal / demo image)         │
├─────────────────────────────────────────────┤
│         Linux Kernel 6.1                    │
│   (radxa/kernel: linux-6.1-stan-rkr4.1)     │
├─────────────────────────────────────────────┤
│   ATF (ARM Trusted Firmware)  │  OP-TEE     │
├─────────────────────────────────────────────┤
│         U-Boot 2017.09 (SPL mode)           │
│   (radxa/u-boot: next-dev-buildroot)        │
├─────────────────────────────────────────────┤
│        DDR Init / SPL / Miniloader          │
│            (rkbin binaries)                 │
├─────────────────────────────────────────────┤
│        BootROM (on-chip, read-only)         │
└─────────────────────────────────────────────┘
```

### Thứ tự khởi động (Boot Sequence)

```
BootROM → SPL/Miniloader → ATF+OP-TEE → U-Boot → Kernel → Init → Userspace
```

---

## 4. Bước 1 – Cài Đặt Yocto SDK

### 4.1 Clone toàn bộ SDK

```bash
mkdir -p ~/yocto-rockchip && cd ~/yocto-rockchip

# Clone Poky (Yocto base)
git clone git://git.yoctoproject.org/poky -b scarthgap

# Clone OpenEmbedded layers
git clone git://git.openembedded.org/meta-openembedded.git -b scarthgap

# Clone Rockchip BSP layer
git clone https://github.com/radxa/meta-rockchip.git -b scarthgap

# Clone meta-clang (cần cho một số recipes)
git clone https://github.com/kraj/meta-clang.git -b scarthgap

# Clone meta-browser (Chromium / Firefox)
git clone https://github.com/OSSystems/meta-browser.git -b scarthgap
```

### 4.2 Cấu trúc thư mục SDK (workspace hiện tại)

```
yocto-rockchip-sdk/
├── bitbake/
├── meta-poky/
├── oe-init-build-env
├── scripts/
├── meta-browser/
│   ├── meta-chromium/
│   └── meta-firefox/
├── meta-clang/
├── meta-rockchip/          ← BSP layer chính cho Rock 4D
│   ├── conf/machine/
│   │   ├── rockchip-rk3576-rock-4d.conf   ← machine config
│   │   └── include/rk3576.inc
│   ├── recipes-bsp/
│   ├── recipes-kernel/
│   └── wic/
└── build/
    └── conf/
        ├── bblayers.conf
        ├── local.conf
        └── rockchip-rk3576-rock-4d.conf
```

### 4.3 Khởi tạo build environment

```bash
cd yocto-rockchip-sdk
source oe-init-build-env build
```

---

## 5. Bước 2 – Cấu Hình Build Cho Rock 4D

### 5.1 Cập nhật `bblayers.conf`

File: `build/conf/bblayers.conf`

```makefile
POKY_BBLAYERS_CONF_VERSION = "2"
BBPATH = "${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \
  ${TOPDIR}/../meta-openembedded/meta-oe \
  ${TOPDIR}/../meta-openembedded/meta-python \
  ${TOPDIR}/../meta-openembedded/meta-networking \
  ${TOPDIR}/../meta-openembedded/meta-multimedia \
  ${TOPDIR}/../meta-browser/meta-chromium \
  ${TOPDIR}/../meta-lts-mixins \
  ${TOPDIR}/../meta-clang \
  ${TOPDIR}/../meta-rockchip \
  ${TOPDIR}/../poky/meta \
  ${TOPDIR}/../poky/meta-poky \
  ${TOPDIR}/../poky/meta-yocto-bsp \
"
```

### 5.2 Cập nhật `local.conf`

Cách đơn giản nhất là dùng file cấu hình có sẵn:

```bash
# Tạo local.conf chỉ với 2 dòng
cat > build/conf/local.conf << 'EOF'
include include/common.conf
include include/demo.conf

MACHINE = "rockchip-rk3576-rock-4d"
EOF
```

Hoặc copy từ file template sẵn có:

```bash
cp build/conf/rockchip-rk3576-rock-4d.conf build/conf/local.conf
```

### 5.3 Nội dung machine config (`rockchip-rk3576-rock-4d.conf`)

```makefile
require conf/machine/include/rk3576.inc

KERNEL_DEVICETREE = "rockchip/rk3576-rock-4d.dtb"

UBOOT_MACHINE = "rk3576_defconfig"
RK_UBOOT_SPL = "1"

# WiFi/BT firmware
RK_WIFIBT_RRECOMMENDS = " \
    rkwifibt-firmware-aic8800d80-usb \
"
```

### 5.4 Thông số kỹ thuật từ `rk3576.inc`

```makefile
PREFERRED_VERSION_linux-rockchip := "6.1%"
LINUXLIBCVERSION := "6.1-custom%"
MALI_GPU := "bifrost-g52"
MALI_VERSION := "g13p0"
RK_ISP_VERSION := "3.9"
```

---

## 6. Bước 3 – Build U-Boot (Bootloader)

### 6.1 Thông tin source

| Thông số | Giá trị |
|---|---|
| **Repository** | https://github.com/radxa/u-boot.git |
| **Branch** | `next-dev-buildroot` |
| **Version** | 2017.09 |
| **defconfig** | `rk3576_defconfig` |
| **SPL mode** | Bật (`RK_UBOOT_SPL = "1"`) |
| **rkbin repo** | https://github.com/radxa/rkbin.git (`develop-v2024.10`) |

### 6.2 Build qua Yocto

```bash
bitbake u-boot-rockchip
```

### 6.3 Build thủ công (standalone)

```bash
# Clone U-Boot
git clone https://github.com/radxa/u-boot.git -b next-dev-buildroot
git clone https://github.com/radxa/rkbin.git -b develop-v2024.10

cd u-boot

# Chuẩn bị cross-compiler
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Build với SPL
make rk3576_defconfig
./make.sh --spl-new
```

### 6.4 Output artifacts

Sau khi build xong, các file sau sẽ được tạo ra:

| File | Mô tả |
|---|---|
| `idblock.img` | ID block image (DDR init) |
| `loader.bin` | Loader binary (Miniloader) |
| `uboot.img` | U-Boot image đã đóng gói |
| `trust.img` | ATF + OP-TEE trust image |

---

## 7. Bước 4 – Build Kernel Linux

### 7.1 Thông tin source

| Thông số | Giá trị |
|---|---|
| **Repository** | https://github.com/radxa/kernel.git |
| **Branch** | `linux-6.1-stan-rkr4.1-buildroot` |
| **Version** | 6.1.x |
| **defconfig** | `rockchip_linux_defconfig` |
| **Device Tree** | `rockchip/rk3576-rock-4d.dtb` |

### 7.2 Build qua Yocto

```bash
bitbake linux-rockchip
```

### 7.3 Build thủ công (standalone)

```bash
# Clone kernel
git clone https://github.com/radxa/kernel.git -b linux-6.1-stan-rkr4.1-buildroot
cd kernel

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Apply defconfig
make rockchip_linux_defconfig

# Tùy chỉnh config (nếu cần)
make menuconfig

# Build kernel + modules + DTB
make -j$(nproc) Image modules dtbs

# Cụ thể compile DTB cho Rock 4D
make rockchip/rk3576-rock-4d.dtb
```

### 7.4 Các module kernel quan trọng

| Module | Chức năng |
|---|---|
| `aic8800_fdrv` | WiFi AIC8800D80 |
| `aic8800_btlpm` | Bluetooth AIC8800D80 |
| `rk_isp_*` | Camera/ISP (RKAIQ 3.9) |
| `mali_kbase` | GPU Mali-G52 |
| `rockchip_*` | Các driver Rockchip BSP |

---

## 8. Bước 5 – Build Root Filesystem & Image

### 8.1 Build image tối thiểu

```bash
bitbake core-image-minimal
```

### 8.2 Build image đầy đủ (demo với Wayland + multimedia)

```bash
# Thêm INHERIT vào local.conf
echo 'INHERIT:append = " rockchip-image"' >> build/conf/local.conf

bitbake core-image-base
```

### 8.3 Các package được include theo `demo.conf`

```makefile
# Display (Wayland mặc định)
weston weston-init weston-examples

# WiFi/BT
iw wpa-supplicant bluez5

# Multimedia (GStreamer stack)
gstreamer1.0
gstreamer1.0-plugins-base
gstreamer1.0-plugins-bad
gstreamer1.0-plugins-good
gstreamer1.0-rockchip
v4l-utils
rockchip-rkaiq-server
rockchip-rkaiq-iqfiles

# Audio
alsa-utils
rockchip-alsa-config
pulseaudio-server

# Browsers
chromium (meta-chromium)
```

### 8.4 Output

```
build/tmp/deploy/images/rockchip-rk3576-rock-4d/
├── core-image-minimal-rockchip-rk3576-rock-4d.wic    ← SD card image
├── core-image-minimal-rockchip-rk3576-rock-4d.wic.gz
├── update.img                                          ← Rockchip firmware image
├── idblock.img
├── loader.bin
├── uboot.img
├── Image                                               ← Kernel image
└── rockchip-rk3576-rock-4d.dtb
```

---

## 9. Bước 6 – Flash Image Lên Board

### 9.1 Chuẩn bị board vào chế độ Maskrom/Rockusb

**Cách 1: Nút Maskrom**
1. Ngắt nguồn board
2. Giữ nút **Maskrom** (hoặc **Recovery**)
3. Cắm cáp USB-C vào cổng OTG/USB2
4. Cấp nguồn trong khi vẫn giữ nút
5. Thả nút sau 2-3 giây

**Cách 2: Short Maskrom pad** (nếu không có nút)
1. Short pad Maskrom trên PCB bằng nhíp/dây
2. Cấp nguồn
3. Bỏ short sau khi có kết nối USB

### 9.2 Kiểm tra kết nối

```bash
# Kiểm tra bằng lsusb
lsusb | grep -i rockchip
# Kết quả mong đợi:
# Bus 00X Device 0XX: ID 2207:350b Fuzhou Rockchip Electronics Co., Ltd. RK3576 in Maskrom mode
# hoặc:
# Bus 00X Device 0XX: ID 2207:0006 Fuzhou Rockchip Electronics Co., Ltd. rk3xxx

sudo rkdeveloptool ld
# Kết quả: DevNo=1 Vid=0x2207,Pid=0x350b,LocationID=...
```

### 9.3 Flash bằng `upgrade_tool`

```bash
# Flash loader trước (nếu ở chế độ Maskrom)
sudo upgrade_tool db path/to/loader.bin

# Flash toàn bộ firmware image
sudo upgrade_tool uf path/to/update.img

# Hoặc flash từng partition
sudo upgrade_tool di -b path/to/uboot.img
sudo upgrade_tool di -k path/to/Image
sudo upgrade_tool di -dtb path/to/rk3576-rock-4d.dtb
```

### 9.4 Flash SD card (WIC image)

```bash
# Flash trực tiếp vào SD card (thay sdX bằng device thực)
sudo dd if=core-image-minimal-rockchip-rk3576-rock-4d.wic \
    of=/dev/sdX bs=4M status=progress conv=fsync

# Hoặc dùng bmaptool (nhanh hơn)
sudo bmaptool copy core-image-minimal-rockchip-rk3576-rock-4d.wic.gz /dev/sdX
```

### 9.5 Flash bằng `rkdeveloptool` (open-source)

```bash
# Vào chế độ loader trước
sudo rkdeveloptool db loader.bin

# Flash WIC image
sudo rkdeveloptool wl 0 update.img

# Reboot
sudo rkdeveloptool rd
```

---

## 10. Bước 7 – Kiểm Tra và Debug Sau Boot

### 10.1 Kết nối UART Debug

| Thông số | Giá trị |
|---|---|
| **Cổng** | ttyFIQ0 (debug UART) |
| **Baud rate** | **1,500,000** (1.5 Mbps) |
| **Data bits** | 8 |
| **Parity** | None |
| **Stop bits** | 1 |

```bash
# Kết nối với minicom
sudo minicom -D /dev/ttyUSB0 -b 1500000

# Hoặc picocom
sudo picocom -b 1500000 /dev/ttyUSB0

# Hoặc screen
sudo screen /dev/ttyUSB0 1500000
```

> **Lưu ý quan trọng:** Baud rate là **1,500,000** (không phải 115200 thông thường).  
> Sử dụng USB-to-UART adapter hỗ trợ baud rate cao (CP2102, FTDI, CH343).

### 10.2 Các log boot cần kiểm tra

```
# U-Boot SPL
SPL: RK3576 ...
U-Boot 2017.09-...

# Kernel boot
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x412fd0b1]
[    0.000000] Linux version 6.1.x ...

# Device Tree
[    0.000000] Machine model: Radxa ROCK 4D
[    0.000000] OF: fdt: DTB is at ...

# Wifi init
[    x.xxxxxx] aic8800_fdrv: ...
```

### 10.3 Kiểm tra sau khi login

```bash
# Thông tin SoC
cat /proc/cpuinfo | head -20
cat /sys/devices/soc0/soc_id

# GPU
ls /dev/mali*
cat /sys/devices/platform/fb000000.gpu/driver/module/version  # Mali version

# WiFi
ip link show
iw dev wlan0 info

# Display (Wayland)
loginctl
weston --version
```

---

## 11. Bước 8 – Bringup Từng Subsystem

### 11.1 Display (Wayland/Weston)

**Kiểm tra KMS/DRM:**
```bash
ls /dev/dri/
modetest -M rockchip -c
```

**Khởi động Weston:**
```bash
weston --tty=1 --backend=drm-backend.so
```

**Cấu hình trong Yocto** (`display.conf`):
```makefile
DISPLAY_PLATFORM ?= "wayland"
DISTRO_FEATURES:append = " wayland egl"
IMAGE_INSTALL:append = " weston weston-init weston-examples"
```

---

### 11.2 GPU (Mali-G52 Bifrost)

**Kiểm tra:**
```bash
# Xem driver status
cat /sys/kernel/debug/mali0/gpu_id
ls /dev/mali0

# Chạy glmark2 benchmark
glmark2-es2-wayland
```

**Cấu hình Mali trong Yocto** (`mali.inc`):
```makefile
MALI_GPU := "bifrost-g52"
MALI_VERSION := "g13p0"
```

---

### 11.3 WiFi (AIC8800D80 USB)

**Firmware location:** `/lib/firmware/aic8800D80/`

**Kiểm tra:**
```bash
# Xem interface
ip link show wlan0

# Scan WiFi
iw dev wlan0 scan | grep SSID

# Kết nối bằng wpa_supplicant
wpa_passphrase "SSID" "password" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhclient wlan0
```

**Thêm firmware vào Yocto (`rockchip-rk3576-rock-4d.conf`):**
```makefile
RK_WIFIBT_RRECOMMENDS = " \
    rkwifibt-firmware-aic8800d80-usb \
"
```

---

### 11.4 Bluetooth (AIC8800D80)

```bash
# Khởi động bluetoothd
systemctl start bluetooth

# Scan thiết bị
bluetoothctl
> power on
> scan on
> pair <MAC>
> connect <MAC>
```

---

### 11.5 Camera/ISP (RKAIQ v3.9)

**Kiểm tra V4L2:**
```bash
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --all
```

**Khởi động RKAIQ server:**
```bash
rkaiq_3A_server &
```

**Capture test:**
```bash
v4l2-ctl -d /dev/video0 \
    --set-fmt-video=width=1920,height=1080,pixelformat=NV12 \
    --stream-mmap --stream-count=10 --stream-to=capture.raw
```

**Package trong Yocto** (`multimedia.conf`):
```makefile
IMAGE_INSTALL:append = " rockchip-rkaiq-server rockchip-rkaiq-iqfiles"
```

---

### 11.6 Multimedia (GStreamer + Rockchip HW decode)

**Test video decode hardware acceleration:**
```bash
# H.264 decode
gst-launch-1.0 filesrc location=test.mp4 ! \
    qtdemux ! h264parse ! mppvideodec ! \
    videoconvert ! autovideosink

# H.265/HEVC decode
gst-launch-1.0 filesrc location=test.mkv ! \
    matroskademux ! h265parse ! mppvideodec ! \
    videoconvert ! autovideosink
```

**Package cần thiết** (`multimedia.conf`):
```makefile
IMAGE_INSTALL:append = " \
    gstreamer1.0 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-good \
    gstreamer1.0-rockchip \
    v4l-utils \
"
```

---

### 11.7 Audio (ALSA + PulseAudio)

**Kiểm tra:**
```bash
# Xem các sound card
aplay -l
arecord -l

# Test audio output
aplay -D hw:0,0 /usr/share/sounds/alsa/Front_Left.wav

# PulseAudio
pulseaudio --start
paplay /usr/share/sounds/alsa/Front_Left.wav
```

---

### 11.8 NPU

**Kiểm tra:**
```bash
# NPU device
ls /dev/rknpu

# Xem NPU info
cat /sys/kernel/debug/rknpu/version
```

---

## 12. Tài Liệu Tham Khảo

| Tài liệu | Link |
|---|---|
| Radxa Rock 4D Official Docs | https://docs.radxa.com/en/rock4/rock4d |
| Rockchip Wiki | http://opensource.rock-chips.com/wiki_Main_Page |
| Rockchip Upgradetool | http://opensource.rock-chips.com/wiki_Upgradetool |
| Rockchip Rockusb mode | http://opensource.rock-chips.com/wiki_Rockusb |
| Radxa U-Boot repo | https://github.com/radxa/u-boot (branch: next-dev-buildroot) |
| Radxa Kernel repo | https://github.com/radxa/kernel (branch: linux-6.1-stan-rkr4.1-buildroot) |
| Radxa rkbin repo | https://github.com/radxa/rkbin (branch: develop-v2024.10) |
| rkdeveloptool | https://github.com/rockchip-linux/rkdeveloptool |
| meta-rockchip | https://github.com/radxa/meta-rockchip |
| Yocto Project | https://www.yoctoproject.org/docs/ |

---

## Phụ Lục: Checklist Bringup

```
[ ] 1. Môi trường Yocto build hoạt động (bitbake chạy được)
[ ] 2. Layers đã thêm vào bblayers.conf
[ ] 3. MACHINE = "rockchip-rk3576-rock-4d" trong local.conf
[ ] 4. U-Boot build thành công → idblock.img, loader.bin, uboot.img
[ ] 5. Kernel build thành công → Image, rk3576-rock-4d.dtb
[ ] 6. rootfs image build thành công → .wic hoặc update.img
[ ] 7. Board vào Maskrom mode (lsusb nhận thiết bị)
[ ] 8. Flash loader.bin thành công
[ ] 9. Flash image thành công
[ ] 10. Boot thành công đến U-Boot prompt (UART 1500000 baud)
[ ] 11. Kernel boot thành công, mount rootfs
[ ] 12. Login console hoạt động
[ ] 13. Display (Wayland/Weston) hiển thị được
[ ] 14. GPU Mali-G52 nhận diện (/dev/mali0)
[ ] 15. WiFi AIC8800D80 kết nối được
[ ] 16. Bluetooth hoạt động
[ ] 17. Audio in/out hoạt động
[ ] 18. Camera/ISP capture được ảnh
[ ] 19. HW video decode (MPP) hoạt động
[ ] 20. NPU nhận diện (/dev/rknpu)
```
