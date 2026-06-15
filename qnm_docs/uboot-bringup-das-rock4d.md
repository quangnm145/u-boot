# Hướng Dẫn Bringup U-Boot (Das U-Boot Mainline) cho Radxa Rock 4D

> **Nguồn tham khảo:**
> - Das U-Boot official: https://docs.u-boot-project.org/en/latest/board/rockchip/rockchip.html
> - Das U-Boot source (mainline): https://source.denx.de/u-boot/u-boot
> - Radxa ref U-Boot (vendor fork): `u-boot/uboot-ref/u-boot-radxa_android14_rkr6`

---

## Mục Lục

1. [Tổng Quan & Kết Luận Phân Tích](#1-tổng-quan--kết-luận-phân-tích)
2. [So Sánh Das U-Boot vs Radxa Ref](#2-so-sánh-das-u-boot-vs-radxa-ref)
3. [Cấu Trúc File Das U-Boot cho RK3576/Rock 4D](#3-cấu-trúc-file-das-u-boot-cho-rk3576rock-4d)
4. [Boot Flow & Image Model](#4-boot-flow--image-model)
5. [Chuẩn Bị Môi Trường](#5-chuẩn-bị-môi-trường)
6. [Clone Source & Dependencies](#6-clone-source--dependencies)
7. [Build U-Boot](#7-build-u-boot)
8. [Artifacts Đầu Ra](#8-artifacts-đầu-ra)
9. [Flash & Test](#9-flash--test)
10. [Giải Thích defconfig: Das vs Radxa](#10-giải-thích-defconfig-das-vs-radxa)
11. [Giải Thích DTS / U-Boot DTSI: Das vs Radxa](#11-giải-thích-dts--u-boot-dtsi-das-vs-radxa)
12. [Troubleshooting](#12-troubleshooting)
13. [Bước Tiếp Theo (Kernel + Rootfs)](#13-bước-tiếp-theo-kernel--rootfs)

---

## 1. Tổng Quan & Kết Luận Phân Tích

### Kết luận quan trọng

**Radxa ROCK 4D đã được hỗ trợ đầy đủ trong Das U-Boot mainline.**

Commit maintainer: *Jonas Karlman <jonas@kwiboo.se>*

| Trạng thái | Das U-Boot (mainline) |
|---|---|
| defconfig | `configs/rock-4d-rk3576_defconfig` ✅ |
| U-Boot DTSI | `arch/arm/dts/rk3576-rock-4d-u-boot.dtsi` ✅ |
| Upstream DTS | `dts/upstream/src/arm64/rockchip/rk3576-rock-4d.dts` ✅ |
| SoC mach | `arch/arm/mach-rockchip/rk3576/` ✅ |
| MAINTAINERS | `arch/arm/mach-rockchip/rk3576/MAINTAINERS` ✅ |

Không cần bất kỳ patch thêm nào để build U-Boot cho Rock 4D từ das U-Boot mainline.

---

## 2. So Sánh Das U-Boot vs Radxa Ref

| Aspect | Das U-Boot (mainline) | Radxa Ref (vendor fork) |
|---|---|---|
| **Phiên bản cơ sở** | 2024+ (mainline) | 2017.09-based |
| **Build system** | Standard `Makefile` + `binman` | `make.sh` + rktools vendor script |
| **Image format đầu ra** | `u-boot-rockchip.bin` (SD/eMMC) | `uboot.img` + `trust.img` + `idblock.img` |
| **Flash method** | `dd … seek=64` (trực tiếp vào SD/eMMC) | `upgrade_tool uf update.img` (Rockchip tool) |
| **DTS annotiation** | `bootph-pre-ram` / `bootph-some-ram` (modern) | `u-boot,dm-spl` / `u-boot,dm-pre-reloc` (cũ) |
| **Vị trí DTS** | `dts/upstream/src/arm64/rockchip/` | `arch/arm/dts/` |
| **Board directory** | Generic — không cần board C file riêng | `board/rockchip/evb_rk3576/evb_rk3576.c` |
| **Android** | Không | Có (AVB, `ROCKCHIP_FIT_IMAGE`, fastboot) |
| **Display (DRM)** | Không có trong U-Boot | Có (`DRM_ROCKCHIP_DW_HDMI_QP`, DSI2, DP) |
| **PMIC** | RK8XX (cơ bản) | RK8XX + USB-C PD + charger ICs |
| **Boot order** | `same-as-spl` → sdmmc → sdhci → ufshc | sdmmc → spi_nand → spi_nor → same-as-spl |
| **Baud rate UART** | `1500000` ✅ | `1500000` ✅ |
| **Debug UART base** | `0x2AD40000` (uart0) ✅ | `0x2ad40000` ✅ |

### Khi nào dùng cái nào?

- **Das U-Boot** → Yocto/buildroot, Linux thuần, community support, long-term maintainability
- **Radxa Ref** → Android 14, cần Android Boot Image, AVB (Verified Boot), OTA A/B

---

## 3. Cấu Trúc File Das U-Boot cho RK3576/Rock 4D

```
u-boot/
├── configs/
│   └── rock-4d-rk3576_defconfig          ← Main board defconfig
│
├── arch/arm/
│   ├── dts/
│   │   ├── rk3576-rock-4d-u-boot.dtsi    ← U-Boot board overlay (bootph annotations)
│   │   ├── rk3576-u-boot.dtsi            ← U-Boot SoC overlay (shared cho mọi RK3576 board)
│   │   └── rk3576-u-boot.dtsi            ← chứa boot-order, SFC, UART, SDHCI, UFS...
│   ├── include/asm/arch-rk3576/          ← Symlink tới arch-rockchip cho RK3576
│   ├── include/asm/arch-rockchip/
│   │   └── cru_rk3576.h                  ← CRU register map
│   └── mach-rockchip/rk3576/
│       ├── Kconfig                        ← Board Kconfig (TARGET_ROC_PC_RK3576, defaults RK3576)
│       ├── MAINTAINERS                    ← Maintainer info cho rock-4d
│       ├── rk3576.c                       ← SoC init (lowlevel, cpu_info...)
│       ├── clk_rk3576.c                   ← Clock init
│       └── syscon_rk3576.c               ← Syscon/GRF init
│
├── dts/upstream/src/arm64/rockchip/
│   ├── rk3576.dtsi                        ← SoC base DTS (tất cả peripheral defs)
│   ├── rk3576-pinctrl.dtsi               ← Pinctrl definitions
│   └── rk3576-rock-4d.dts                ← Full board DTS (Radxa Rock 4D)
│
├── drivers/
│   ├── clk/rockchip/clk_rk3576.c
│   ├── pinctrl/rockchip/pinctrl-rk3576.c
│   ├── ram/rockchip/sdram_rk3576.c
│   └── reset/rst-rk3576.c
│
├── include/configs/
│   └── rk3576_common.h                   ← Memory map, ENV defaults
│
└── [KHÔNG CÓ board/radxa/rock-4d/]       ← Board dùng generic approach
```

### Tại sao không có `board/radxa/rock-4d/`?

Das U-Boot sử dụng **generic board model** cho RK3576. Tất cả board-specific
logic nằm trong DTS + defconfig. Không cần file C riêng cho board (khác với
Radxa ref dùng `board/rockchip/evb_rk3576/evb_rk3576.c`).

---

## 4. Boot Flow & Image Model

### TEE (OP-TEE / BL32) — Tuỳ Chọn Hay Bắt Buộc?

| Binary | Variable | Bắt buộc? | File trong rkbin |
|---|---|---|---|
| DDR init | `ROCKCHIP_TPL` | **BẮT BUỘC** | `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin` |
| TF-A | `BL31` | **BẮT BUỘC** | `rk3576_bl31_v*.elf` (ELF) |
| OP-TEE | `TEE` | **KHÔNG DÙNG ĐƯỢC** với das U-Boot | `rk3576_bl32_v*.bin` (raw binary — xem bên dưới) |

**Tại sao KHÔNG set `TEE` với das U-Boot cho RK3576:**

Das U-Boot binman dùng `fit,operation = "split-elf"` để đọc file TEE,
nghĩa là **bắt buộc phải là file ELF**. Nhưng file `rk3576_bl32_v*.bin`
trong rkbin là **raw binary blob** — không phải ELF:

```
# Raw binary (KHÔNG dùng được với binman split-elf):
rkbin/bin/rk35/rk3576_bl32_v1.06.bin

# ELF (dùng được):
rkbin/bin/rk35/rk3576_bl31_v1.20.elf   ← BL31/TF-A có dạng ELF
# → KHÔNG có ELF tương ứng cho BL32/OP-TEE trong rkbin RK3576
```

File `bl32_v*.bin` **chỉ dùng được** với Radxa vendor build system
(`make.sh` → đóng gói vào `trust.img`). Không thể dùng với das U-Boot.

Kết quả nếu set `TEE=rk3576_bl32_v*.bin`:
```
binman: Node '.../images/@tee-SEQ': Failed to read ELF file:
Magic number does not match
make: *** [Makefile:1395: .binman_stamp] Error 1
```

**Giải pháp:** Không set biến `TEE`. Node `tee-os` trong binman có
flag `optional;` — binman bỏ qua hoàn toàn nếu `TEE` không được set.

**Nếu cần OP-TEE thực sự cho production:**
Phải build OP-TEE từ source để có file ELF:
```bash
git clone https://github.com/OP-TEE/optee_os.git
cd optee_os
make CROSS_COMPILE64=aarch64-linux-gnu- PLATFORM=rockchip-rk3576
# → tee.elf
export TEE=$(pwd)/out/arm-plat-rockchip/core/tee.elf
```
> OP-TEE mainline hỗ trợ RK3576 từ version 4.x+. Kiểm tra trước khi dùng.

---

### Das U-Boot: TPL/SPL + Binman

```
BootROM (on-chip)
    │
    ▼  tìm idbloader tại LBA 64 (sector 0x40)
TPL / ROCKCHIP_TPL
    │  (DDR init binary từ rkbin — rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin)
    ▼
SPL (u-boot-spl.bin)
    │  (load U-Boot proper + BL31 từ FIT image)
    ▼
BL31 (TF-A) ←── rk3576_bl31_v*.elf từ rkbin (ELF ✅)
    │         [BL32/OP-TEE — cần ELF từ optee_os build, KHÔNG dùng bl32.bin]
    │
    ▼
U-Boot proper (u-boot.bin)
    │
    ▼
Kernel (via extlinux / EFI / UEFI)
```

### Binman đóng gói `u-boot-rockchip.bin`

```
u-boot-rockchip.bin (ghi vào SD/eMMC tại seek=64):
┌─────────────────────────────────────────────────────────┐
│  Offset 0x0000: IDB (idbloader header)                  │
│  Offset 0x0000: TPL = ROCKCHIP_TPL (DDR init binary)   │
│  Offset 0x???? : SPL (u-boot-spl.bin)                  │
│  Offset 0x8000+: U-Boot proper + DTB + BL31 (FIT)      │
└─────────────────────────────────────────────────────────┘
```

Đây là **1 file duy nhất** — khác hoàn toàn với Radxa ref cần
`idblock.img` + `loader.bin` + `uboot.img` + `trust.img` riêng biệt.

### Boot device order (từ `rk3576-u-boot.dtsi`)

```
chosen {
    u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci, &ufshc;
};
```

SPL thử boot từ:
1. Same device SPL loaded from (SD card / eMMC / SPI)
2. SD card (`&sdmmc`)
3. eMMC (`&sdhci`)
4. UFS (`&ufshc`)

---

## 5. Chuẩn Bị Môi Trường

### 5.1 Host requirements

```bash
# Ubuntu 20.04 / 22.04
sudo apt-get update && sudo apt-get install -y \
    gcc-aarch64-linux-gnu \
    build-essential \
    bison flex libssl-dev \
    bc python3 python3-pyelftools \
    swig libpython3-dev \
    device-tree-compiler
```

### 5.2 Kiểm tra cross compiler

```bash
aarch64-linux-gnu-gcc --version
# aarch64-linux-gnu-gcc (Ubuntu 11.x...) 11.x.x
```

Nếu không có:
```bash
sudo apt-get install gcc-aarch64-linux-gnu
```

---

## 6. Clone Source & Dependencies

### 6.1 Clone das U-Boot

```bash
mkdir -p ~/work/rock4d-uboot && cd ~/work/rock4d-uboot

# Clone das U-Boot (mainline)
git clone --depth 1 https://source.denx.de/u-boot/u-boot.git
# Hoặc mirror GitHub:
# git clone --depth 1 https://github.com/u-boot/u-boot.git
```

### 6.2 Clone rkbin (BẮTBUỘC cho RK3576)

RK3576 **không** có open-source TF-A code. Phải dùng binary từ rkbin.

```bash
cd ~/work/rock4d-uboot
git clone --depth 1 https://github.com/rockchip-linux/rkbin
```

Kiểm tra file cần thiết:
```bash
ls rkbin/bin/rk35/rk3576_bl31_v*.elf
# → rkbin/bin/rk35/rk3576_bl31_v1.20.elf  (hoặc version mới hơn)

ls rkbin/bin/rk35/rk3576_ddr_lp4_*MHz_lp5_*MHz_v*.bin
# → rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin  (hoặc mới hơn)

# KHÔNG dùng rk3576_bl32_v*.bin với das U-Boot!
# bl32.bin là raw binary, binman cần ELF → sẽ lỗi "Magic number does not match"
```

> **Lưu ý:** Luôn dùng phiên bản **mới nhất** có trong rkbin.

### 6.3 Cấu trúc thư mục kết quả

```
~/work/rock4d-uboot/
├── u-boot/        ← Das U-Boot mainline
└── rkbin/         ← Rockchip binary blobs (BL31 ELF, DDR init binary)
```

---

## 7. Build U-Boot

### 7.1 Set biến môi trường

```bash
cd ~/work/rock4d-uboot

# Cross compiler
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# BL31: ARM Trusted Firmware (ELF từ rkbin) — BẮT BUỘC
export BL31=$(ls rkbin/bin/rk35/rk3576_bl31_v*.elf | sort | tail -1)

# ROCKCHIP_TPL: DDR initialization binary — BẮT BUỘC
export ROCKCHIP_TPL=$(ls rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin | sort | tail -1)

# KHÔNG set TEE với das U-Boot!
# rk3576_bl32_v*.bin là raw binary, binman cần ELF → lỗi "Magic number does not match"
# unset TEE  (đảm bảo biến không được set từ session trước)
unset TEE

echo "BL31:          $BL31"
echo "ROCKCHIP_TPL:  $ROCKCHIP_TPL"
```

Kết quả mong đợi:
```
BL31:          rkbin/bin/rk35/rk3576_bl31_v1.20.elf
ROCKCHIP_TPL:  rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin
```

### 7.2 Configure

```bash
cd ~/work/rock4d-uboot/u-boot

make rock-4d-rk3576_defconfig
```

Output mong đợi:
```
#
# configuration written to .config
#
```

### 7.3 (Tuỳ chọn) Xem / chỉnh config

```bash
make menuconfig
```

Các option quan trọng trong defconfig Rock 4D:
- `CONFIG_ROCKCHIP_RK3576=y` — SoC target
- `CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3576-rock-4d"` — DTS
- `CONFIG_BAUDRATE=1500000` — Debug UART baud rate
- `CONFIG_DEBUG_UART_BASE=0x2AD40000` — UART0 (ttyFIQ0)
- `CONFIG_ROCKCHIP_SPI_IMAGE=y` — Hỗ trợ SPI flash
- `CONFIG_SPL_UFS_SUPPORT=y` — Hỗ trợ boot từ UFS
- `CONFIG_PCIE_DW_ROCKCHIP=y` + `CONFIG_NVME_PCI=y` — NVMe
- `CONFIG_DWC_ETH_QOS=y` — Gigabit Ethernet

### 7.4 Build

```bash
make -j$(nproc) \
    BL31=$BL31 \
    ROCKCHIP_TPL=$ROCKCHIP_TPL \
    CROSS_COMPILE=aarch64-linux-gnu-
```

> **KHÔNG truyền `TEE=...`** với `rk3576_bl32_v*.bin`.
> Binman dùng `split-elf` operation cho tee-os — yêu cầu file ELF.
> `bl32.bin` là raw binary → lỗi `Magic number does not match`.

Thời gian build: ~2-5 phút tùy máy.

Output cuối cùng mong đợi:
```
...
BINMAN  u-boot-rockchip.bin
BINMAN  u-boot-rockchip-spi.bin
```

> **Nếu không thấy `u-boot-rockchip.bin`:** Kiểm tra `BL31` và `ROCKCHIP_TPL`
> đã được set đúng. Thiếu 1 trong 2 file này sẽ khiến binman fail.

### Warning "missing optional external blobs" — Bình thường, bỏ qua

Sau khi build thành công, binman in warning sau — đây là **hoàn toàn bình thường**:

```
Image 'simple-bin' is missing optional external blobs but is still functional: tee-os

/binman/simple-bin/fit/images/@tee-SEQ/tee-os (tee-os):
   See the documentation for your board. You may need to build Open Portable
   Trusted Execution Environment (OP-TEE) and build with TEE=/path/to/tee.bin
```

**Giải thích:** `tee-os` node được đánh dấu `optional;` trong binman config.
Warning này chỉ có nghĩa là OP-TEE không được nhúng vào FIT image — image
**vẫn hoạt động đầy đủ** cho mục đích bringup và Linux boot thông thường.
TrustZone secure world sẽ không chạy, nhưng không ảnh hưởng đến:
- SD/eMMC/NVMe boot
- Kernel boot
- Ethernet, USB, PCIe, GPIO...

Chỉ cần OP-TEE nếu dùng: fTPM, RPMB key storage, TEE-based DRM, hay Android Keymaster.

---

## 8. Artifacts Đầu Ra

Sau khi build thành công, các file quan trọng:

| File | Mô tả | Dùng để |
|---|---|---|
| `u-boot-rockchip.bin` | All-in-one SD/eMMC image | Flash vào SD card hoặc eMMC |
| `u-boot-rockchip-spi.bin` | All-in-one SPI flash image | Flash vào SPI NOR/NAND |
| `u-boot.dtb` | Device tree compiled | Debug DTS issues |
| `spl/u-boot-spl.bin` | SPL raw binary | Debug only |
| `u-boot.bin` | U-Boot proper binary | Debug only |
| `.config` | Build configuration | Reference |

### So sánh artifacts das vs Radxa ref

| Das U-Boot | Radxa Ref | Mô tả |
|---|---|---|
| `u-boot-rockchip.bin` | `idblock.img` + `loader.bin` | DDR init + SPL |
| `u-boot-rockchip.bin` | `uboot.img` | U-Boot proper |
| *(gộp vào 1 file)* | `trust.img` | TF-A + OP-TEE |

**Das U-Boot đơn giản hơn:** 1 file duy nhất thay vì 3-4 file riêng biệt.

---

## 9. Flash & Test

### 9.1 Flash vào SD Card

```bash
# Thay sdX bằng device thực (kiểm tra bằng lsblk trước)
sudo dd if=u-boot-rockchip.bin of=/dev/sdX seek=64 bs=512 status=progress conv=fsync
sync
```

Giải thích:
- `seek=64`: Bỏ qua 64 sectors (32 KB) đầu — đây là vùng MBR/GPT
- `bs=512`: Block size 512 bytes (1 sector)
- Offset thực tế: sector 64 = 0x8000 bytes = 32 KB

### 9.2 Flash vào eMMC (qua fastboot hoặc SD)

**Cách 1: Boot từ SD, sau đó write vào eMMC**

```bash
# Trên board (U-Boot prompt), sau khi boot từ SD:
# Load u-boot-rockchip.bin vào RAM
load mmc 1:1 ${kernel_addr_r} u-boot-rockchip.bin

# Write vào eMMC (mmc 0 = eMMC)
mmc dev 0
mmc write ${kernel_addr_r} 64 0x2000
```

**Cách 2: Flash qua USB OTG (Maskrom mode)**

```bash
# Board vào Maskrom → rkdeveloptool
sudo rkdeveloptool db /path/to/MiniLoaderAll.bin  # loader từ rkbin để enumerate USB

# Write u-boot-rockchip.bin vào sector 64
sudo rkdeveloptool wl 64 u-boot-rockchip.bin
sudo rkdeveloptool rd  # reboot
```

### 9.3 Flash vào SPI NOR Flash

```bash
# Load SPI image vào RAM:
load mmc 0:1 ${kernel_addr_r} u-boot-rockchip-spi.bin

# Write vào SPI flash:
sf probe
sf update ${kernel_addr_r} 0 ${filesize}
```

### 9.4 Kiểm tra qua UART

Kết nối UART debug: **1,500,000 baud, 8N1** (CP2102 / CH343)

```bash
sudo picocom -b 1500000 /dev/ttyUSB0
```

**Log boot mong đợi từ Das U-Boot:**

```
TPL: RK3576 ...
SPL: ...
U-Boot SPL 2024.xx-xxx (...)
Trying to boot from MMC1
...
U-Boot 2024.xx-xxx (...)

CPU:   Rockchip RK3576
Model: Radxa ROCK 4D
DRAM:  8 GiB (or 4/16 GiB tùy board)
...
Net:   eth0: ethernet@2a220000
Hit any key to stop autoboot:  2
```

### 9.5 Kiểm tra U-Boot prompt

```
=> version
U-Boot 2024.xx-... (build date)
aarch64-linux-gnu-gcc (Ubuntu 11.x) 11.x.x

=> bdinfo
boot_params = 0x0000000000000000
DRAM bank   = 0x0000000040000000
-> start    = 0x0000000040000000
-> size     = 0x0000000200000000
...

=> mmc list
dwmmc@2a310000: 1 (SD)
mmc@2a330000: 0 (eMMC)

=> net list
eth-0 : ethernet@2a220000 active
```

---

## 10. Giải Thích defconfig: Das vs Radxa

### Das U-Boot `rock-4d-rk3576_defconfig` — những điểm khác biệt quan trọng

```makefile
# === SoC & Board ===
CONFIG_ROCKCHIP_RK3576=y              # RK3576 SoC
CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3576-rock-4d"  # DTS từ upstream

# === UART Debug ===
CONFIG_BAUDRATE=1500000               # 1.5 Mbps (đặc trưng Rockchip)
CONFIG_DEBUG_UART_BASE=0x2AD40000    # UART0 (= ttyFIQ0 trong kernel)
CONFIG_DEBUG_UART_CLOCK=24000000     # OSC 24 MHz

# === SPL / Boot ===
CONFIG_SPL_MAX_SIZE=0x40000          # 256KB SPL max
CONFIG_SPL_SPI_LOAD=y               # SPL có thể load từ SPI
CONFIG_SYS_SPI_U_BOOT_OFFS=0x60000 # U-Boot proper tại offset 0x60000 trong SPI
CONFIG_SPL_UFS_SUPPORT=y            # Boot từ UFS

# === SPI Flash (cho SPI boot) ===
CONFIG_SF_DEFAULT_BUS=5              # SFC0 = SPI bus 5
CONFIG_ROCKCHIP_SPI_IMAGE=y         # Tạo u-boot-rockchip-spi.bin
CONFIG_ROCKCHIP_SFC=y               # Rockchip Serial Flash Controller
CONFIG_SPI_FLASH_MACRONIX=y        # Macronix SPI NOR (thường thấy trên Rock 4D)
CONFIG_SPI_FLASH_SFDP_SUPPORT=y    # Auto-detect SPI flash via SFDP

# === Storage ===
CONFIG_MMC_DW=y                     # eMMC/SD via Designware
CONFIG_MMC_DW_ROCKCHIP=y
CONFIG_UFS=y                        # UFS (Universal Flash Storage)
CONFIG_UFS_ROCKCHIP=y

# === Network ===
CONFIG_DWC_ETH_QOS=y                # Synopsys GMAC (Ethernet)
CONFIG_DWC_ETH_QOS_ROCKCHIP=y
CONFIG_PHY_REALTEK=y                # Realtek PHY (RTL8211E trên Rock 4D)

# === PCIe / NVMe ===
CONFIG_PCI=y
CONFIG_PCIE_DW_ROCKCHIP=y
CONFIG_NVME_PCI=y                   # NVMe boot via PCIe

# === USB ===
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_GENERIC=y

# === PHY ===
CONFIG_PHY_ROCKCHIP_INNO_USB2=y    # USB 2.0 PHY
CONFIG_PHY_ROCKCHIP_NANENG_COMBOPHY=y  # PCIe/USB3 combo PHY
CONFIG_PHY_ROCKCHIP_USBDP=y        # USB-DP combo (USB-C)

# === PMIC ===
CONFIG_PMIC_RK8XX=y                 # RK806/RK860 PMIC (trên Rock 4D)
CONFIG_REGULATOR_RK8XX=y

# === KHÔNG CÓ trong das U-Boot (khác Radxa ref) ===
# CONFIG_ANDROID_BOOTLOADER - không cần
# CONFIG_ANDROID_AVB - không cần
# CONFIG_DRM_ROCKCHIP - không có display trong bootloader
# CONFIG_ROCKCHIP_FIT_IMAGE - không dùng Rockchip vendor FIT
```

### Radxa ref `rk3576_rock4d_defconfig` — những điểm khác biệt

```makefile
# === Radxa-specific thêm vào ===
CONFIG_TARGET_EVB_RK3576=y           # Reuse EVB board (không có board riêng)
CONFIG_ROCKCHIP_FIT_IMAGE=y          # Rockchip vendor FIT format
CONFIG_ANDROID_BOOTLOADER=y          # Android boot
CONFIG_ANDROID_AVB=y                 # Android Verified Boot
CONFIG_ROCKCHIP_VENDOR_PARTITION=y   # Rockchip vendor partition
CONFIG_USING_KERNEL_DTB_V2=y         # Dùng kernel DTB

# Display stack đầy đủ:
CONFIG_DRM_ROCKCHIP=y
CONFIG_DRM_ROCKCHIP_DW_HDMI_QP=y
CONFIG_DRM_ROCKCHIP_DW_MIPI_DSI2=y
CONFIG_DRM_ROCKCHIP_DW_DP=y

# Charge animation (Android)
CONFIG_CHARGE_ANIMATION=y
CONFIG_DM_CHARGE_DISPLAY=y

# USB-C PD
CONFIG_DM_POWER_DELIVERY=y
CONFIG_TYPEC_TCPM=y

# Charger ICs
CONFIG_CHARGER_BQ25700=y
CONFIG_CHARGER_BQ25890=y
```

---

## 11. Giải Thích DTS / U-Boot DTSI: Das vs Radxa

### Das U-Boot: 3 lớp DTS

```
dts/upstream/src/arm64/rockchip/rk3576-rock-4d.dts   ← Board DTS đầy đủ
    ↑ includes
    rk3576.dtsi                                        ← SoC base
    
arch/arm/dts/rk3576-rock-4d-u-boot.dtsi               ← U-Boot board overlay
    ↑ includes
    rk3576-u-boot.dtsi                                 ← U-Boot SoC overlay
```

**`arch/arm/dts/rk3576-rock-4d-u-boot.dtsi`** (minimal):
```dts
#include "rk3576-u-boot.dtsi"    // include SoC overlay

&sfc0 {                           // SPI Flash Controller 0
    flash@0 {
        bootph-pre-ram;          // cần trong SPL phase (trước reloc RAM)
        bootph-some-ram;         // cần sau khi RAM sẵn
    };
};
```

**`arch/arm/dts/rk3576-u-boot.dtsi`** (SoC-level, dùng cho tất cả RK3576):
```dts
chosen {
    u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci, &ufshc;
};

// bootph-all = cần ở mọi phase (pre-sram, spl, u-boot)
// bootph-pre-ram = cần trong TPL/SPL trước khi RAM init xong
// bootph-some-ram = cần khi đã có RAM
```

### Radxa ref: 2 lớp DTS

```
arch/arm/dts/rk3576-rock-4d.dts              ← Minimal (chỉ override model)
    ↑ includes
    rk3576.dtsi
    rk3576-u-boot-rock-4d.dtsi               ← Full U-Boot config

arch/arm/dts/rk3576-u-boot-rock-4d.dtsi      ← Board-specific, dùng u-boot,dm-spl style
```

**Khác biệt chính:**
| Das U-Boot | Radxa Ref |
|---|---|
| `bootph-pre-ram` | `u-boot,dm-spl` |
| `bootph-some-ram` | `u-boot,dm-pre-reloc` |
| `bootph-all` | `u-boot,dm-spl` + `u-boot,dm-pre-reloc` |
| Boot order qua `u-boot,spl-boot-order` | Boot order qua aliases + `u-boot,dm-spl` |

**Radxa ref cần `pcie0` và `vcc3v3_pcie` trong SPL** (cho NVMe boot):
```dts
// rk3576-u-boot-rock-4d.dtsi (Radxa ref)
&pcie0 {
    u-boot,dm-spl;
    reset-gpios = <&gpio2 RK_PB4 GPIO_ACTIVE_HIGH>;
    vpcie3v3-supply = <&vcc3v3_pcie>;
    status = "okay";
};
```

Das U-Boot cũng hỗ trợ PCIe/NVMe nhưng thông qua Kconfig `CONFIG_NVME_PCI`
và PCIe driver — không cần khai báo thêm trong DTSI.

---

## 12. Troubleshooting

### Build errors

**Lỗi: `BL31` not found**
```
make[2]: *** No rule to make target '../rkbin/bin/rk35/rk3576_bl31_v1.04.elf'
```
→ Kiểm tra lại `$BL31` path. rkbin phải được clone ở `../rkbin` so với `u-boot/`.

**Lỗi: `ROCKCHIP_TPL` missing**
```
binman: Missing file for entry 'rockchip-tpl'
```
→ Kiểm tra `$ROCKCHIP_TPL` path. Dùng `ls rkbin/bin/rk35/rk3576_ddr*` để tìm file đúng.

**Lỗi: `python3-pyelftools` not installed**
```
scripts/dtc/pylibfdt/setup.py: error: ...
```
→ `sudo apt-get install python3-pyelftools`

### Boot issues

**Không thấy output UART**
- Kiểm tra baud rate: phải là **1,500,000** (không phải 115200)
- Kiểm tra cáp USB-to-UART hỗ trợ baud cao (CP2102 ✓, CH343 ✓, CH340 ✗ không hỗ trợ 1.5M)
- Kiểm tra TX/RX đã nối đúng chưa (TX board → RX adapter)

**Board không boot, UART hiện TPL rồi im**
- Kiểm tra `$ROCKCHIP_TPL` có đúng model DDR không (LP4/LP5 tùy board)
- Kiểm tra `u-boot-rockchip.bin` đã được flash đúng offset (seek=64)

**SPL hang tại `Trying to boot from...`**
- Kiểm tra SD card/eMMC có partition đúng không
- U-Boot proper cần ext4 hoặc FAT partition với `extlinux/extlinux.conf` hoặc UEFI payload

**`dwmmc@2a310000: 1 (SD)` missing**
- SD card chưa được insert trước khi boot
- Không ảnh hưởng nếu boot từ eMMC

### Kiểm tra nhanh image trước khi flash

```bash
# Kiểm tra size hợp lý (thường 500KB - 1.5MB)
ls -lh u-boot-rockchip.bin

# Kiểm tra magic bytes (phải bắt đầu bằng IDB header)
xxd u-boot-rockchip.bin | head -4
# 0000000: 4453 4652 4b04 4b52 3035 3736 0000 0000  DSFRKxKR0576....
# (DSFR = Rockchip IDB magic)
```

---

## 13. Bước Tiếp Theo (Kernel + Rootfs)

Sau khi U-Boot boot thành công, cần kernel và rootfs:

### 13.1 extlinux boot (khuyến nghị cho Yocto/buildroot)

Tạo file `extlinux/extlinux.conf` trên partition boot (FAT hoặc ext4):

```
label rockchip
    kernel /Image
    fdt /rockchip/rk3576-rock-4d.dtb
    append console=ttyFIQ0,1500000n8 rootwait root=/dev/mmcblk0p2 rw
```

### 13.2 Kernel DTS quan trọng

Kernel DTS cần dùng đúng file:
```
arch/arm64/boot/dts/rockchip/rk3576-rock-4d.dtb
```

(từ `radxa/kernel` branch `linux-6.1-stan-rkr4.1-buildroot`)

### 13.3 Checklist hoàn chỉnh

```
[ ] U-Boot build thành công (có u-boot-rockchip.bin)
[ ] Flash vào SD/eMMC tại seek=64
[ ] UART 1500000 baud hiển thị TPL output
[ ] UART hiển thị SPL output
[ ] UART hiển thị U-Boot proper prompt
[ ] `mmc list` thấy SD + eMMC
[ ] `net list` thấy ethernet (sau khi có extlinux + kernel)
[ ] `pci enum` thấy PCIe devices (nếu có NVMe)
[ ] Boot vào kernel thành công
[ ] Login console hoạt động
```

---

## Tham Khảo Nhanh (Quick Reference)

```bash
# === Chuẩn bị (1 lần) ===
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export BL31=$(ls ~/work/rock4d-uboot/rkbin/bin/rk35/rk3576_bl31_v*.elf | sort | tail -1)
export ROCKCHIP_TPL=$(ls ~/work/rock4d-uboot/rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin | sort | tail -1)
# KHÔNG set TEE — bl32.bin là raw binary, binman cần ELF
unset TEE

# === Build ===
cd ~/work/rock4d-uboot/u-boot
make rock-4d-rk3576_defconfig
make -j$(nproc) BL31=$BL31 ROCKCHIP_TPL=$ROCKCHIP_TPL CROSS_COMPILE=aarch64-linux-gnu-

# === Flash SD card ===
sudo dd if=u-boot-rockchip.bin of=/dev/sdX seek=64 bs=512 status=progress conv=fsync

# === Flash SPI ===
sf probe && sf update ${kernel_addr_r} 0 ${filesize}

# === UART connect ===
sudo picocom -b 1500000 /dev/ttyUSB0
```
