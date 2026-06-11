# U-Boot Port: `evb_rk3576_qnm` cho Radxa ROCK 4D (RK3576)

## Tổng quan

Port das U-Boot mainline cho board Radxa ROCK 4D (SoC Rockchip RK3576).

### Thông tin cơ bản

| Mục | Thông tin |
|-----|-----------|
| SoC | Rockchip RK3576 (4× Cortex-A72 + 4× Cortex-A53) |
| Board | Radxa ROCK 4D v1.112 |
| UART | UART0 @ `0x2AD40000`, **115200 baud** |
| RAM | LPDDR4/LPDDR5 |
| Boot media | SPI Flash → UFS → SD → USB |
| das U-Boot | v2026.07-rc4 |
| Defconfig | `evb_rk3576_qnm_defconfig` |

### Boot output xác nhận

```
U-Boot 2026.07-rc4 (Jun 11 2026 - 11:31:57 +0200)

Model: Radxa ROCK 4D QNM
SoC:   RK3576
DRAM:  4 GiB
PMIC:  RK806 (on=0x40, off=0x00)
Core:  1052 devices, 32 uclasses, devicetree: separate
MMC:   mmc@2a310000: 0
Loading Environment from nowhere... OK
In:    serial@2ad40000
Out:   serial@2ad40000
Err:   serial@2ad40000
Net:   eth0: ethernet@2a220000
Hit any key to stop autoboot:  0
=>
```

---

## Cấu trúc thư mục

```
~/SSD/QuangNM/radxa/
├── u-boot/
│   ├── u-boot/                             ← das U-Boot dev tree (2026.07-rc4)
│   │   ├── configs/
│   │   │   └── evb_rk3576_qnm_defconfig    ← defconfig của board
│   │   ├── arch/arm/dts/
│   │   │   └── rk3576-rock-4d-qnm-u-boot.dtsi  ← U-Boot build overlay
│   │   └── dts/upstream/src/arm64/rockchip/
│   │       └── rk3576-rock-4d-qnm.dts      ← Board DTS
│   └── rkbin/                              ← Rockchip firmware binaries
│       └── bin/rk35/
│           ├── rk3576_bl31_v*.elf          ← TF-A (ARM Trusted Firmware)
│           └── rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin  ← DDR init (TPL)
```

---

## Sự khác biệt: Radxa Ref vs Das U-Boot

| | **Radxa Ref (2017.09)** | **Das U-Boot (2026.07)** |
|---|---|---|
| Base | U-Boot 2017.09 | U-Boot 2026.07-rc4 |
| Board dir | `board/rockchip/evb_rk3576/` | Không cần (boardless) |
| Build tool | `make.sh` + rktools (private) | standard `make` + binman |
| Image format | trust.img + uboot.img | FIT image (u-boot.itb) |
| DTS | `arch/arm/dts/rk3576-evb*.dts` | `dts/upstream/src/arm64/rockchip/` |
| Boot flow | BootROM → MiniLoader → Trust → U-Boot | BootROM → TPL → SPL → FIT |

### Tại sao không cần board directory?

Das U-Boot từ v2023+ dùng **boardless approach** cho Rockchip RK3576+:
- Không có `board/rockchip/evb_rk3576_qnm/`
- Board nhận dạng qua **Device Tree compatible** string
- `CONFIG_DEFAULT_DEVICE_TREE` trỏ thẳng vào upstream DTS
- `board_late_init()` đã có sẵn trong `arch/arm/mach-rockchip/board.c`

---

## Files đã tạo

### 1. `configs/evb_rk3576_qnm_defconfig`

Dựa trên `rock-4d-rk3576_defconfig`, diff so với gốc:

```diff
+CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3576-rock-4d-qnm"   # DTS riêng
+CONFIG_DEFAULT_FDT_FILE="rockchip/rk3576-rock-4d-qnm.dtb"

-CONFIG_BAUDRATE=1500000
+CONFIG_BAUDRATE=115200                                       # ← đổi baud

+CONFIG_SPL_GPIO=y
+CONFIG_SPL_DM_RESET=y
+CONFIG_SPL_UFS_SUPPORT=y
+CONFIG_CMD_UFS=y
+CONFIG_MMC_SDHCI=y
+CONFIG_MMC_SDHCI_SDMA=y
+CONFIG_MMC_SDHCI_ROCKCHIP=y
+CONFIG_SPI_FLASH_WINBOND=y
+CONFIG_SCSI=y
+CONFIG_UFS=y
+CONFIG_UFS_ROCKCHIP=y
+# CONFIG_OPTEE_LIB is not set
```

> **Lưu ý baud rate:** `CONFIG_BAUDRATE` trong defconfig là giá trị thực tế dùng khi boot.
> `stdout-path = "serial0:1500000n8"` trong DTS chỉ có tác dụng nếu `CONFIG_OF_SERIAL_BAUD=y`
> (không được bật). Vì vậy **không cần sửa DTS** để đổi baud — chỉ cần sửa defconfig.

### 2. `dts/upstream/src/arm64/rockchip/rk3576-rock-4d-qnm.dts`

Copy từ `rk3576-rock-4d.dts`, chỉ sửa:

```diff
-model = "Radxa ROCK 4D";
-compatible = "radxa,rock-4d", "rockchip,rk3576";
+model = "Radxa ROCK 4D QNM";
+compatible = "radxa,rock-4d-qnm", "radxa,rock-4d", "rockchip,rk3576";
```

Phần còn lại (GPIO, PMIC, PCIe, USB, Ethernet, SPI NOR) giữ nguyên vì phần cứng giống ROCK 4D.

> `stdout-path` giữ nguyên `serial0:1500000n8` — baud rate thực tế do `CONFIG_BAUDRATE` quyết định.

### 3. `arch/arm/dts/rk3576-rock-4d-qnm-u-boot.dtsi`

**Bắt buộc phải có** — das U-Boot tìm file này khi compile DTS.

```c
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)

#include "rk3576-rock-4d-u-boot.dtsi"
```

Reuse toàn bộ `bootph-*` annotations (SFC Flash, SDMMC, SDHCI, eMMC) từ ROCK 4D gốc.

---

## Cơ chế Boot

### Disk layout khi flash `seek=64`

```
SD card (512 bytes/sector):
┌──────────────────────────────────────────────────────────────┐
│ Sector 0..63     MBR/GPT partition table (không đụng đến)    │
├──────────────────────────────────────────────────────────────┤
│ Sector 64..483   idbloader.img (210 KB)                      │
│   ├── RKNS header (512 B)    ← BootROM tìm magic "RKNS"     │
│   ├── TPL: rk3576_ddr_*.bin  (74 KB)  ← DDR init blob       │
│   └── SPL: u-boot-spl.bin    (130 KB) ← U-Boot SPL          │
├──────────────────────────────────────────────────────────────┤
│ Sector 484..16383  Zero padding (7.9 MB gap)                 │
├──────────────────────────────────────────────────────────────┤
│ Sector 16384+    u-boot.itb (1.2 MB)  ← FIT image           │
│   ├── [atf-1]  BL31 segment @ 0x3FE70000  (16 KB)           │
│   ├── [atf-2]  BL31 segment @ 0x40060000  (120 KB)          │
│   ├── [atf-3]  BL31 segment @ 0x400F0000  (20 KB)           │
│   ├── [u-boot] U-Boot proper @ 0x40800000 (~900 KB)          │
│   └── [fdt-1]  DTB rk3576-rock-4d-qnm.dtb (183 KB)          │
└──────────────────────────────────────────────────────────────┘
```

> Gap 7.9MB là zero padding — binman tự chèn. Đây là lý do `u-boot-rockchip.bin` nặng 9.4MB
> dù content thực chỉ ~1.4MB. SPL hardcode đọc FIT tại **sector 16384** (8MB từ đầu disk).

### Boot flow chi tiết

```
1. BootROM (in SoC ROM)
   └─ Tìm "RKNS" magic tại sector 64
   └─ Load TPL vào SRAM nội (không cần DDR)
   └─ Jump to TPL

2. TPL = rk3576_ddr_lp4_*_v1.09.bin (74 KB, blob Rockchip)
   └─ Khởi tạo DRAM controller (LPDDR4/5 training)
   └─ Output 1,500,000 baud (hardcoded)
   └─ Load SPL từ ngay sau TPL trong idbloader.img
   └─ Jump to SPL

3. SPL = u-boot-spl.bin (130 KB)
   └─ Khởi tạo clocks, pinmux tối thiểu
   └─ Đọc FIT image từ sector 16384
   └─ Load và parse từng image node theo load address:
       ├─ atf-1,2,3 → load BL31 segments vào địa chỉ tương ứng
       └─ u-boot    → load vào 0x40800000
   └─ Jump to BL31 entry (0x40060000)

4. BL31 = TF-A rk3576_bl31_v1.20.elf (156 KB tổng, 3 segments)
   └─ Setup EL3 secure world
   └─ Cấu hình PSCI (power management)
   └─ Jump to U-Boot proper (BL33) tại 0x40800000

5. U-Boot proper @ 0x40800000
   └─ Load DTB từ FIT → parse hardware config
   └─ Init UART @ 115200 (từ CONFIG_BAUDRATE)
   └─ In banner: "Model: Radxa ROCK 4D QNM"
   └─ Boot sequence: SPI → SD → USB
```

### Tại sao BL31 có 3 FIT nodes?

BL31 ELF có 3 `PT_LOAD` segments với địa chỉ khác nhau. binman dùng `split-elf` để tách thành
3 FIT nodes riêng, mỗi node có `load` address riêng:

| Node | Địa chỉ | Kích thước | Nội dung |
|------|---------|-----------|---------|
| atf-1 | `0x3FE70000` | 16 KB | Exception vectors |
| atf-2 | `0x40060000` | 120 KB | Main TF-A code (entry point) |
| atf-3 | `0x400F0000` | 20 KB | RO data / secure config |

---

## Hướng dẫn Build

### Yêu cầu

```bash
sudo apt install gcc-aarch64-linux-gnu make bc python3 bison flex \
                 libssl-dev swig libgnutls28-dev device-tree-compiler
```

### Build

```bash
cd ~/SSD/QuangNM/radxa/u-boot/u-boot

export CROSS_COMPILE=aarch64-linux-gnu-
export BL31=../rkbin/bin/rk35/rk3576_bl31_v1.20.elf
export ROCKCHIP_TPL=../rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin

make evb_rk3576_qnm_defconfig
make olddefconfig
make -j$(nproc)
```

> Build sẽ in cảnh báo `missing optional external blobs: tee-os` — bình thường, OP-TEE đang tắt.

### Output artifacts

```
u-boot/u-boot/
├── u-boot-rockchip.bin   ← All-in-one image (~9.2MB): TPL+SPL+FIT
├── idbloader.img         ← TPL+SPL only (~210KB)
└── u-boot.itb            ← FIT image: BL31+U-Boot+DTB (~1.2MB)
```

---

## Hướng dẫn Flash

### Flash vào SD card

```bash
# Xác định device (thay /dev/sdX)
lsblk

sudo dd if=u-boot-rockchip.bin of=/dev/sdX seek=64 bs=512 status=progress conv=fsync
```

### Flash riêng từng phần (advanced)

```bash
# TPL+SPL vào sector 64
sudo dd if=idbloader.img of=/dev/sdX seek=64 bs=512 conv=fsync

# FIT image vào sector 16384
sudo dd if=u-boot.itb of=/dev/sdX seek=16384 bs=512 conv=fsync
```

---

## Kết nối UART

| Thông số | Giá trị |
|----------|---------|
| UART | UART0 @ `0x2AD40000` |
| **Baud rate console** | **115200** (SPL + U-Boot proper) |
| Baud rate DDR init | 1,500,000 (TPL blob, không thể thay đổi) |
| Format | 8N1 |

```bash
picocom -b 115200 /dev/ttyUSB0
```

---

## Troubleshooting

### Garbage trên UART khi bắt đầu boot

**Bình thường.** Boot có 2 giai đoạn baud rate:

```
[1,500,000 baud]  BootROM → TPL (rk3576_ddr_*.bin)  ← blob Rockchip, cố định
[  115,200 baud]                    SPL → U-Boot → shell
```

Sau ~1-2 giây garbage, output chuyển sang 115200 đọc được bình thường.

| Muốn xem | Baud terminal |
|---------|--------------|
| Chỉ U-Boot shell | 115200 (bỏ qua garbage đầu) |
| Toàn bộ boot log | 1,500,000 |

### Board không boot từ SD (im lặng hoàn toàn)

Kiểm tra:
1. Flash đúng lệnh: `seek=64 bs=512` — sai offset = không boot
2. SD card bị SPI Flash override: nếu SPI có bootloader cũ, BootROM ưu tiên SPI → bỏ qua SD
   - Giải pháp: erase SPI Flash hoặc vào MaskROM mode

### Build in cảnh báo `tee-os missing`

```
Image 'simple-bin' is missing optional external blobs but is still functional: tee-os
```

Bình thường khi `CONFIG_OPTEE_LIB` tắt. Image vẫn hoạt động.

### Nếu muốn bật lại OP-TEE

Das U-Boot binman dùng `fit,operation = "split-elf"` → cần ELF format, không dùng được
`rk3576_bl32_v*.bin` trực tiếp (raw binary). Cần wrap bằng ELF header trước:

```bash
# Convert bl32.bin → tee.elf
BL32=../rkbin/bin/rk35/rk3576_bl32_v1.06.bin
python3 - "$BL32" tee.elf 0x08400000 << 'PYEOF'
import struct, sys
bl32, out, load = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
data = open(bl32,'rb').read()
EH,PH,OFF = 64,56,120
e  = b'\x7fELF\x02\x01\x01'+b'\x00'*9
e += struct.pack('<HHI',2,0xb7,1)+struct.pack('<QQQ',load,EH,0)
e += struct.pack('<IHHHHH',0,EH,PH,1,64,0)+struct.pack('<H',0)
p  = struct.pack('<II',1,5)+struct.pack('<QQ',OFF,load)+struct.pack('<Q',load)
p += struct.pack('<QQQ',len(data),len(data),0x10000)
open(out,'wb').write(e+p+data)
PYEOF

# Build với TEE
make -j$(nproc) BL31=$BL31 ROCKCHIP_TPL=$ROCKCHIP_TPL TEE=tee.elf
```

---

## Tham khảo

| Tài liệu | Đường dẫn |
|----------|-----------|
| Official build guide | https://docs.u-boot-project.org/en/latest/board/rockchip/rockchip.html |
| Radxa ref U-Boot | `../uboot-ref/u-boot-radxa_android14_rkr6/` |
| rkbin INI | `../rkbin/RKBOOT/RK3576MINIALL.ini` |
| RK3576 SoC U-Boot DTSI | `arch/arm/dts/rk3576-u-boot.dtsi` |
| Upstream ROCK 4D DTS | `dts/upstream/src/arm64/rockchip/rk3576-rock-4d.dts` |
| ROCK 4D U-Boot overlay | `arch/arm/dts/rk3576-rock-4d-u-boot.dtsi` |
