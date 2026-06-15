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

### Tổng quan chuỗi boot

```
Power On
    │
    ▼
┌──────────┐    ┌─────────────────────┐    ┌──────────────┐    ┌───────┐    ┌────────────┐
│ BootROM  │───▶│ TPL (DDR blob)      │───▶│     SPL      │───▶│ BL31  │───▶│  U-Boot    │
│ (SoC ROM)│    │ rk3576_ddr_lp4_*.bin│    │ u-boot-spl   │    │ TF-A  │    │  proper    │
└──────────┘    └─────────────────────┘    └──────────────┘    └───────┘    └────────────┘
   SRAM nội          SRAM nội                   DRAM              EL3          EL2/EL1
   (no DRAM)         (no DRAM)                (đã init)        (secure)      (non-secure)
```

---

### Disk layout khi flash `seek=64`

```
SD card / eMMC (512 bytes/sector):
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

```
SPI NOR flash:
├── Offset 0x0000      MBR
├── Offset 0x8000      idbloader.img (TPL + SPL)   ← CONFIG_ROCKCHIP_SPI_IMAGE
└── Offset 0x60000     u-boot.itb (FIT)             ← CONFIG_SYS_SPI_U_BOOT_OFFS
```

> Gap 7.9MB là zero padding — binman tự chèn. Đây là lý do `u-boot-rockchip.bin` nặng ~9.4MB
> dù content thực chỉ ~1.4MB. SPL hardcode đọc FIT tại **sector 16384** (= 8MB từ đầu disk).

---

### Bước 1: BootROM

BootROM là code **gắn sẵn trong silicon** của RK3576, không thể sửa đổi.

**Nhiệm vụ:**
- Quét các thiết bị boot theo thứ tự ưu tiên: **SPI NOR → eMMC → SD → USB**
- Tìm magic signature **`RKNS`** (RocKchip Normal Start):
  - SD/eMMC: tại **sector 64** (byte offset 32768)
  - SPI NOR: tại **offset 0x8000** (32KB)
- Load **TPL** vào Internal SRAM (~192KB trên RK3576)
- Jump to TPL

> Tại thời điểm này **không có DRAM** — chỉ có Internal SRAM của SoC.  
> Nếu SPI NOR có bootloader, BootROM sẽ ưu tiên SPI và bỏ qua SD card.

---

### Bước 2: TPL — Tertiary Program Loader (DDR blob)

Trên Rockchip, TPL **không phải** `u-boot-tpl.bin` thông thường. Thay vào đó là
**DDR initialization blob** độc quyền của Rockchip, được trỏ qua biến `ROCKCHIP_TPL`:

```
rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin (~74KB)
```

**Nhiệm vụ:**
- Chạy hoàn toàn trong SRAM nội (không cần DRAM)
- Thực hiện **DRAM training**: timing calibration, ZQ calibration, write leveling,
  read DQS gate training cho LPDDR4/LPDDR5
- Output boot log tại **1,500,000 baud** (hardcoded trong blob, không thể thay đổi)
- Sau khi DRAM khởi tạo xong, load SPL từ phần tiếp theo của `idbloader.img`
- Jump to SPL

> Rockchip dùng blob độc quyền vì DDR init quá phức tạp và vendor-specific,
> cần được verify kỹ bởi Rockchip trước khi release.

---

### Bước 3: SPL — Secondary Program Loader

SPL là `u-boot-spl.bin` được build từ U-Boot source, kích thước giới hạn:

```
CONFIG_SPL_MAX_SIZE=0x40000   # 256KB max
```

**SPL chạy với DRAM đã sẵn sàng** (TPL đã init DRAM).

#### Execution flow trong SPL

```
SPL entry  (arch/arm/cpu/armv8/start.S)
  │
  ▼
board_init_f()   ← Chạy trong SRAM / DRAM ban đầu, BSS chưa có
  ├── arch_cpu_init()           ← CPU early setup (clocks, PLL)
  ├── preloader_console_init()  ← UART @ 115200 (CONFIG_BAUDRATE)
  ├── rockchip_stimer_init()    ← System timer
  └── dram_init()               ← Đọc DRAM info từ TPL handoff
  │
  ▼  (relocate stack/heap sang DRAM nếu CONFIG_SPL_STACK_R=y)
  │
  ▼
board_init_r()   ← Full C environment, DRAM sẵn sàng
  ├── spl_init()                ← SPL framework init
  ├── board_boot_order()        ← Xác định thứ tự thiết bị boot
  │     └── từ DTS: u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci
  ├── boot_from_devices()       ← Thử load FIT từ từng thiết bị
  │     ├── Đọc FIT từ sector 16384 (SD/eMMC) hoặc SPI offset 0x60000
  │     ├── Parse FIT image header
  │     ├── Load [atf-1,2,3] → BL31 segments vào địa chỉ tương ứng
  │     └── Load [u-boot]    → 0x40800000
  └── jump_to_image_no_args()   ← Jump to BL31 entry @ 0x40060000
```

#### Driver Model trong SPL: `bootph-*` annotations

SPL dùng Driver Model (DM) giống U-Boot proper nhưng **chỉ probe các device được đánh dấu**
trong DTS để giữ kích thước nhỏ. Annotations trong `arch/arm/dts/rk3576-u-boot.dtsi`:

| Annotation | Phase áp dụng | Ý nghĩa |
|---|---|---|
| `bootph-all` | TPL + SPL + U-Boot | Luôn cần, compile vào mọi stage |
| `bootph-pre-ram` | SPL (trước DRAM init hoàn tất) | Cần trước khi có đầy đủ DRAM |
| `bootph-some-ram` | SPL (sau DRAM init) | Cần khi đã có DRAM |

Ví dụ từ `arch/arm/dts/rk3576-u-boot.dtsi`:

```c
&cru {
    bootph-all;           // Clock driver: cần ở mọi stage
};

&sdhci {
    bootph-pre-ram;       // eMMC: cần để SPL đọc FIT
    bootph-some-ram;
};

chosen {
    // SPL boot order: thiết bị hiện tại → sdmmc (SD) → sdhci (eMMC)
    u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci;
};
```

#### SPL load FIT image

```
CONFIG_SPL_SPI_LOAD=y
CONFIG_SYS_SPI_U_BOOT_OFFS=0x60000    # SPI NOR: offset 384KB
# SD/eMMC: hardcode sector 16384 (8MB từ đầu)
```

SPL đọc `u-boot.itb` (FIT), parse từng `images` node và load theo `load` address:

```
u-boot.itb (FIT image):
├── [atf-1]  load → 0x3FE70000  (BL31 exception vectors,  16KB)
├── [atf-2]  load → 0x40060000  (BL31 main code,         120KB) ← entry point
├── [atf-3]  load → 0x400F0000  (BL31 RO data,            20KB)
├── [u-boot] load → 0x40800000  (U-Boot proper,          ~900KB)
└── [fdt-1]  DTB  rk3576-rock-4d-qnm.dtb
```

Sau khi load xong, SPL jump to **BL31 entry** tại `0x40060000`.

---

### Bước 4: BL31 — ARM Trusted Firmware (TF-A)

BL31 chạy ở **EL3 (Exception Level 3)** — mức đặc quyền cao nhất của ARM:

- Setup **TrustZone** (secure/non-secure world partition)
- Cấu hình **PSCI** (Power State Coordination Interface): CPU hotplug, suspend, reset
- Cài đặt **SMC handler** (Secure Monitor Call) — cổng giao tiếp EL1/EL2 → EL3
- Jump to U-Boot proper (BL33) tại `0x40800000` ở EL2

#### Tại sao BL31 có 3 FIT nodes?

BL31 ELF có **3 `PT_LOAD` segments** ở địa chỉ không liên tiếp. binman dùng `split-elf`
để tách thành 3 FIT nodes riêng biệt, mỗi node có `load` address độc lập:

| Node | Địa chỉ | Kích thước | Nội dung |
|------|---------|-----------|---------|
| atf-1 | `0x3FE70000` | 16 KB | Exception vectors |
| atf-2 | `0x40060000` | 120 KB | Main TF-A code (entry point) |
| atf-3 | `0x400F0000` | 20 KB | RO data / secure config |

SPL load từng node vào đúng địa chỉ trong DRAM trước khi jump.

---

### Bước 5: U-Boot Proper

- Chạy ở EL2, nhận control từ BL31
- Khởi tạo toàn bộ hardware (MMC, USB, PCIe, Ethernet, UFS...)
- Load DTB từ FIT, parse hardware config
- Init UART @ **115200** (từ `CONFIG_BAUDRATE=115200` trong defconfig)
- In banner: `Model: Radxa ROCK 4D QNM`
- Thực hiện boot sequence: **SPI Flash → UFS → SD → USB**

---

### Boot flow tóm tắt

```
1. BootROM (SoC ROM, không thể sửa)
   └─ Tìm "RKNS" magic tại sector 64 (SD/eMMC) hoặc offset 0x8000 (SPI)
   └─ Load TPL → SRAM nội
   └─ Jump to TPL

2. TPL = rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin (74 KB, Rockchip blob)
   └─ Chạy trong SRAM, không cần DRAM
   └─ LPDDR4/LPDDR5 training & initialization
   └─ Output @ 1,500,000 baud (hardcoded)
   └─ Load SPL (từ idbloader.img)
   └─ Jump to SPL

3. SPL = u-boot-spl.bin (130 KB, built từ U-Boot source)
   └─ Chạy trong DRAM (đã init bởi TPL)
   └─ board_init_f(): arch_cpu_init, console @ 115200, dram_init
   └─ board_init_r(): spl_init, board_boot_order
   └─ Đọc FIT từ sector 16384 (SD/eMMC) hoặc SPI offset 0x60000
   └─ Load BL31 (3 segments) + U-Boot proper vào DRAM
   └─ Jump → BL31 @ 0x40060000

4. BL31 = TF-A rk3576_bl31_v*.elf (3 segments, ~156 KB tổng)
   └─ Chạy ở EL3 (secure world)
   └─ Setup TrustZone, PSCI, SMC handler
   └─ Jump → U-Boot @ 0x40800000 (EL2)

5. U-Boot proper @ 0x40800000
   └─ Init UART @ 115200, load DTB từ FIT
   └─ In: "Model: Radxa ROCK 4D QNM"
   └─ Boot sequence: SPI → UFS → SD → USB → kernel
```

---

## FIT Image: Cơ chế và Phân tích

Tham khảo:
- [U-Boot FIT docs](https://docs.u-boot-project.org/en/latest/usage/fit/index.html)
- [deepwiki — Legacy and FIT Image Format](https://deepwiki.com/openbmc/u-boot/2.1-legacy-and-fit-image-format)
- [deepwiki — Boot Image Handling](https://deepwiki.com/openbmc/u-boot/2-boot-image-handling)

---

### FIT là gì?

**FIT (Flattened Image Tree)** là format đóng gói image của U-Boot, dùng cấu trúc **FDT
(Flattened Device Tree / DTB)** để mô tả nội dung. FIT thay thế format **Legacy (uImage)**
trong các thiết kế hiện đại vì linh hoạt hơn nhiều.

#### So sánh Legacy vs FIT

| | **Legacy (uImage)** | **FIT** |
|---|---|---|
| Cấu trúc | Header cố định 64 bytes + data | FDT-based (như DTB) |
| Số image | 1 (hoặc multi-file thô) | Nhiều image nodes tùy ý |
| Configurations | Không | Có (nhiều board từ 1 file) |
| Verification | CRC32 header + data | SHA256/SHA512 per-image, RSA signature |
| Secure boot | Không | Có (Verified Boot) |
| Metadata | Cố định (header fields) | Tùy ý (properties trong DTS) |
| External data | Không | Có (`data-offset` / `data-position`) |
| Tạo bằng | `mkimage -A -O -T -C -a -e ...` | `mkimage -f image.its` |
| Dùng cho | Simple images, backward compat | Modern boards, ATF, multi-config |

---

### Cấu trúc FIT

FIT được mô tả qua file **ITS (Image Tree Source)** — syntax giống DTS — sau đó compile
bằng `mkimage -f` thành **ITB (Image Tree Blob)** binary.

```
ITS file (text)                    ITB file (binary = FDT blob + data blobs)
──────────────                     ──────────────────────────────────────────
/dts-v1/;                          FDT header (magic 0xD00DFEED)
/ {                                  ├── root node
  description = "...";                │   ├── timestamp
  #address-cells = <1>;               │   ├── description
                                      │
  images {                            ├── /images node
    <name> {                          │   ├── <image-node>
      type = "...";                   │   │   ├── type / arch / os
      arch = "arm64";                 │   │   ├── compression
      os   = "...";                   │   │   ├── load / entry
      compression = "none";          │   │   ├── data-offset  (offset vào external data)
      load = <addr>;                  │   │   ├── data-size
      entry = <addr>;                 │   │   └── hash { algo = "sha256"; value = ...; }
      data = /incbin/("file.bin");    │   └── ...
      hash { algo = "sha256"; };      │
    };                                ├── /configurations node
  };                                  │   ├── default = "config-1"
                                      │   └── config-1 {
  configurations {                    │         firmware = "atf-1";
    default = "config-1";             │         loadables = "u-boot", "atf-2", ...;
    config-1 {                        │         fdt = "fdt-1";
      firmware = "...";               │         compatible = "...";
      loadables = "...", "...";       │       }
      fdt = "...";                    │
    };                                └── [external data blobs appended after FDT]
  };
};
```

#### Các node quan trọng trong `/images`

| Property | Ý nghĩa |
|---|---|
| `type` | Loại image: `firmware`, `standalone`, `kernel`, `flat_dt`, `ramdisk`, `tee` |
| `os` | OS type: `u-boot`, `arm-trusted-firmware`, `linux`, `tee` |
| `arch` | Architecture: `arm64`, `arm` |
| `compression` | `none`, `gzip`, `lzma`, `lz4` |
| `load` | Địa chỉ DRAM để load data vào |
| `entry` | Entry point (chỉ node chính/firmware mới có) |
| `data` | Inline binary data (nhúng trong FDT) |
| `data-offset` | Offset của data nằm **ngoài FDT** (external data, tiết kiệm copy) |
| `data-size` | Kích thước external data |
| `hash` | Subnode chứa `algo` và `value` để verify integrity |

#### Node `/configurations`

Cho phép 1 FIT phục vụ nhiều board/config:

| Property | Ý nghĩa |
|---|---|
| `firmware` | Image node được load đầu tiên; entry point của nó là nơi SPL nhảy vào |
| `loadables` | Danh sách image nodes được load thêm (theo thứ tự) |
| `fdt` | DTB image node để pass cho U-Boot/kernel |
| `compatible` | Board compatible string để SPL tự chọn đúng config |
| `kernel` | (Falcon mode) kernel image node |

---

### External Data trong FIT

Mặc định binman dùng **external data**: binary blobs nằm **sau FDT header** trong ITB,
không nhúng vào trong FDT. Điều này quan trọng cho SPL vì:

```
u-boot.itb layout (binary file):
┌─────────────────────────────────────────────────────────┐
│ FDT header (0xD00DFEED)                          ~2.5KB │  ← fdtdump hiển thị phần này
│   /images/u-boot   { data-offset=0x0000; size=0xD6928 } │
│   /images/atf-1    { data-offset=0xD6A00; size=0x4000 } │
│   /images/atf-2    { data-offset=0xDAA00; size=0x1DF10 }│
│   /images/atf-3    { data-offset=0xF8A00; size=0x5000 } │
│   /images/fdt-1    { data-offset=0xFDA00; size=0x2DC90 }│
│   /configurations/config-1 {                            │
│       firmware = "atf-1";                               │
│       loadables = "u-boot", "atf-2", "atf-3";           │
│       fdt = "fdt-1";                                    │
│   }                                                     │
├─────────────────────────────────────────────────────────┤
│ [external data blob 1] u-boot-nodtb.bin       @ offset 0│  ← 0xD6928 bytes
│ [padding to 512-byte alignment]                         │
│ [external data blob 2] atf-1 (ELF segment 1)  @ 0xD6A00│  ← 0x4000 bytes
│ [external data blob 3] atf-2 (ELF segment 2)  @ 0xDAA00│  ← 0x1DF10 bytes
│ [external data blob 4] atf-3 (ELF segment 3)  @ 0xF8A00│  ← 0x5000 bytes
│ [external data blob 5] rk3576-rock-4d-qnm.dtb @ 0xFDA00│  ← 0x2DC90 bytes
└─────────────────────────────────────────────────────────┘
Total: ~1.28 MB
```

> Khi SPL gọi `spl_load_simple_fit()`, nó đọc phần FDT header trước (kích thước nhỏ ~2.5KB),
> parse metadata, rồi đọc từng external data blob trực tiếp vào đúng load address trong DRAM
> mà **không cần** load toàn bộ ITB vào RAM trước. Đây là lý do `data-offset` thay vì `data`.

---

### Binman tạo FIT như thế nào?

U-Boot dùng **binman** để tự động tạo `u-boot.itb` từ template DTS trong source. Đây là
luồng build:

```
Build time:
  arch/arm/dts/rockchip-u-boot.dtsi     ← template FIT binman
      ├─ @atf-SEQ { fit,operation = "split-elf"; atf-bl31 {} }
      │       ↓
      │   binman tự tách BL31 ELF thành N PT_LOAD segments → atf-1, atf-2, atf-3
      ├─ u-boot { type = "standalone"; os = "u-boot"; load = CONFIG_TEXT_BASE }
      ├─ @tee-SEQ { fit,operation = "split-elf"; tee-os {} }  ← optional (không có trên RK3576)
      ├─ @fdt-SEQ { type = "flat_dt"; }
      └─ @config-SEQ { firmware = "atf-1"; fit,loadables; fit,compatible; }

  Input blobs:
      BL31=../rkbin/bin/rk35/rk3576_bl31_v1.20.elf     ← ARM ELF, 3 PT_LOAD segs
      ROCKCHIP_TPL=../rkbin/bin/rk35/rk3576_ddr_*.bin  ← vào idbloader, không vào FIT
      u-boot-nodtb.bin                                  ← U-Boot proper (stripped)
      rk3576-rock-4d-qnm.dtb                            ← Board DTB

  Output:
      u-boot.itb (FIT ITB)
          ├── /images/u-boot        type=standalone  os=u-boot
          ├── /images/atf-1         type=firmware    os=arm-trusted-firmware  entry=0x40060000
          ├── /images/atf-2         type=firmware    os=arm-trusted-firmware  (no entry)
          ├── /images/atf-3         type=firmware    os=arm-trusted-firmware  (no entry)
          └── /images/fdt-1         type=flat_dt
          /configurations/config-1
              firmware  = "atf-1"
              loadables = "u-boot", "atf-2", "atf-3"
              fdt       = "fdt-1"
```

#### Tại sao BL31 tách thành 3 nodes?

BL31 ELF (`rk3576_bl31_v1.20.elf`) có **3 PT_LOAD segments** ở địa chỉ không liên tiếp.
Binman dùng `fit,operation = "split-elf"` để tách mỗi segment thành 1 FIT node riêng:

```
rk3576_bl31_v1.20.elf (ARM64 ELF):
  Segment 1 (PT_LOAD): VMA=0x3FE70000  size=0x4000   ← Exception vectors
  Segment 2 (PT_LOAD): VMA=0x40060000  size=0x1DF10  ← Main TF-A code; e_entry=0x40060000
  Segment 3 (PT_LOAD): VMA=0x400F0000  size=0x5000   ← RO data

Binman output:
  atf-1: load=0x3FE70000  entry=0x40060000  data=segment1  (có entry → SPL nhảy vào đây)
  atf-2: load=0x40060000  (no entry)        data=segment2
  atf-3: load=0x400F0000  (no entry)        data=segment3
```

> SPL sẽ load tất cả 3 segments vào đúng địa chỉ DRAM, sau đó jump đến `entry=0x40060000`
> của atf-1 (entry point của BL31).

---

### SPL load FIT như thế nào?

**File:** `common/spl/spl_fit.c`

#### Bước 1: Đọc FIT header

```c
// spl_load_simple_fit() — common/spl/spl_fit.c:797
int spl_load_simple_fit(struct spl_image_info *spl_image,
                        struct spl_load_info *info, ulong offset, void *fit)
{
    // Đọc phần FDT header của ITB (nhỏ, ~2.5KB)
    spl_simple_fit_read(&ctx, info, offset, fit);
    //   → ctx.fit = pointer đến FDT header trong memory
    //   → ctx.ext_data_offset = kích thước phần FDT (offset bắt đầu external data)
    //   → ctx.images_node = FDT offset của /images node
    //   → ctx.conf_node   = FDT offset của configuration đã chọn

    spl_simple_fit_parse(&ctx);
    //   → tìm config phù hợp (dựa trên board compatible string hoặc default)
```

#### Bước 2: Tìm firmware image (entry point)

```c
    // Thứ tự tìm kiếm:
    // 1. "firmware" property trong configuration node (ưu tiên cao nhất)
    node = spl_fit_get_image_node(&ctx, FIT_FIRMWARE_PROP, 0);
    //   → config-1.firmware = "atf-1" → tìm /images/atf-1

    // 2. Nếu không có "firmware" → thử "kernel" (Falcon mode)
    if (node < 0 && IS_ENABLED(CONFIG_SPL_OS_BOOT))
        node = spl_fit_get_image_node(&ctx, FIT_KERNEL_PROP, 0);

    // 3. Nếu không có cả hai → dùng "loadables[0]"
    if (node < 0)
        node = spl_fit_get_image_node(&ctx, "loadables", 0);
        index = 1;  // bắt đầu loadables từ index 1 (đã load index 0)
```

#### Bước 3: Load firmware node

```c
    // Load atf-1 → đọc segment từ disk, ghi vào load=0x3FE70000
    load_simple_fit(info, offset, &ctx, node, spl_image);
    //   → fit_image_get_load()       → load_addr = 0x3FE70000
    //   → fit_image_get_data_offset() → tính vị trí trên disk = FIT offset + ext_data_offset
    //   → info->read()               → DMA/PIO đọc từ SD/SPI vào DRAM
    //   → fit_image_get_entry()      → entry_point = 0x40060000
    //   → fit_image_get_os()         → os = IH_OS_ARM_TRUSTED_FIRMWARE

    // Lấy os type → spl_image.os = IH_OS_ARM_TRUSTED_FIRMWARE
    spl_fit_image_get_os(ctx.fit, node, &spl_image->os);
```

#### Bước 4: Load FDT (DTB)

```c
    // Nếu os cần FDT (u-boot, linux, tee):
    if (os_takes_devicetree(spl_image->os)) {
        spl_fit_append_fdt(spl_image, info, offset, &ctx);
        //   → tìm /images/fdt-1 (từ config.fdt = "fdt-1")
        //   → đọc DTB vào DRAM (thường ngay sau U-Boot proper)
        //   → spl_image->fdt_addr = địa chỉ DTB trong DRAM
    }
    // Trên RK3576: os=ATF không cần FDT ở bước này
    // fdt_addr được dùng làm platform param khi gọi BL31
```

#### Bước 5: Load các loadables còn lại

```c
    // Lặp qua tất cả loadables (từ index bắt đầu):
    // config-1.loadables = "u-boot", "atf-2", "atf-3"
    for (index = 0; ; index++) {
        node = spl_fit_get_image_node(&ctx, "loadables", index);
        // → lần lượt: "u-boot" (index=0), "atf-2" (index=1), "atf-3" (index=2)

        load_simple_fit(info, offset, &ctx, node, &image_info);
        // u-boot → đọc vào 0x40800000
        // atf-2  → đọc vào 0x40060000
        // atf-3  → đọc vào 0x400F0000

        // Nếu loadable này cần FDT (u-boot):
        if (os_takes_devicetree(os_type))
            spl_fit_append_fdt(&image_info, ...);
            // → load fdt-1 (DTB) vào DRAM, spl_image->fdt_addr = addr
    }
```

#### Kết quả sau khi `spl_load_simple_fit()` hoàn thành

```
DRAM layout sau khi SPL load FIT:
┌────────────────┬───────────────────┬─────────────────────────────────────────┐
│ Địa chỉ        │ Image             │ Nội dung                                │
├────────────────┼───────────────────┼─────────────────────────────────────────┤
│ 0x3FE70000     │ atf-1 (16KB)      │ BL31 exception vectors                  │
│ 0x40060000     │ atf-2 (120KB)     │ BL31 main code ← BL31 entry point       │
│ 0x400F0000     │ atf-3 (20KB)      │ BL31 RO data                            │
│ 0x40800000     │ u-boot (~900KB)   │ U-Boot proper binary                    │
│ 0x40B30000     │ fdt-1 (~183KB)    │ rk3576-rock-4d-qnm.dtb                  │
└────────────────┴───────────────────┴─────────────────────────────────────────┘

spl_image.entry_point = 0x40060000   ← từ atf-1.entry
spl_image.os          = IH_OS_ARM_TRUSTED_FIRMWARE
spl_image.fdt_addr    = 0x40B30000   ← DTB address (sẽ pass cho BL31 → U-Boot)
```

---

### U-Boot proper dùng FIT để boot kernel

Khi U-Boot proper chạy, nó boot kernel qua `bootm` command, cũng dùng FIT:

```
bootcmd (ví dụ điển hình):
  load mmc 0:1 0x43000000 /boot/fitImage
  bootm 0x43000000

bootm 0x43000000:
  1. BOOTM_STATE_START   → detect format (FIT magic = 0xD00DFEED)
  2. BOOTM_STATE_FINDOS  → chọn configuration (default hoặc #config-1)
                           tìm kernel node (type="kernel", os="linux")
  3. BOOTM_STATE_LOADOS  → load kernel vào kernel_entry address
                           decompress nếu compression != "none"
  4. BOOTM_STATE_RAMDISK → load initrd node (nếu có)
  5. BOOTM_STATE_FDT     → load fdt node, fix up DTB (memory map, cmdline)
  6. BOOTM_STATE_OS_PREP → arch-specific prep (disable MMU, flush caches)
  7. BOOTM_STATE_OS_GO   → jump to kernel entry point

# Chọn config cụ thể:
  bootm 0x43000000#rockchip_defconfig
```

#### Ví dụ FIT cho kernel (ITS)

```dts
/dts-v1/;
/ {
    description = "Linux kernel with DTB";
    #address-cells = <1>;

    images {
        kernel {
            description = "Linux 6.x kernel";
            data = /incbin/("Image");      // ARM64 kernel
            type = "kernel";
            arch = "arm64";
            os = "linux";
            compression = "none";
            load = <0x40200000>;
            entry = <0x40200000>;
            hash { algo = "sha256"; };
        };

        fdt-1 {
            description = "RK3576 ROCK 4D DTB";
            data = /incbin/("rk3576-rock-4d-qnm.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash { algo = "sha256"; };
        };

        ramdisk {
            description = "initramfs";
            data = /incbin/("initramfs.cpio.gz");
            type = "ramdisk";
            arch = "arm64";
            os = "linux";
            compression = "gzip";
            hash { algo = "sha256"; };
        };
    };

    configurations {
        default = "config-1";
        config-1 {
            description = "ROCK 4D QNM";
            kernel = "kernel";
            fdt = "fdt-1";
            ramdisk = "ramdisk";
            hash { algo = "sha256"; };
        };
    };
};
```

---

### Tóm tắt FIT trong context RK3576

```
Build time (host):
  mkimage/binman
      BL31 ELF (3 segments) → atf-1, atf-2, atf-3 nodes (split-elf)
      u-boot-nodtb.bin      → u-boot node (standalone)
      rk3576-rock-4d-qnm.dtb → fdt-1 node (flat_dt)
      config-1: firmware="atf-1", loadables="u-boot,atf-2,atf-3", fdt="fdt-1"
  → u-boot.itb

Runtime SPL (spl_load_simple_fit):
  1. Đọc FDT header → parse images + config
  2. config-1.firmware = "atf-1" → load atf-1 @ 0x3FE70000; entry=0x40060000
  3. loadables[0] = "u-boot" → load @ 0x40800000; fdt_addr = fdt-1 @ 0x40B30000
  4. loadables[1] = "atf-2"  → load @ 0x40060000
  5. loadables[2] = "atf-3"  → load @ 0x400F0000
  spl_image.os = IH_OS_ARM_TRUSTED_FIRMWARE → spl_invoke_atf()

Runtime U-Boot (bootm):
  bootcmd: load kernel FIT → bootm → FINDOS → LOADOS → FDT fixup → jump to kernel
```

---

## Trusted Firmware (TF-A) và TEE

Tham khảo:
- [deepwiki — Trusted Firmware Integration](https://deepwiki.com/openbmc/u-boot/6.2-trusted-firmware-integration)
- [OP-TEE Core Architecture](https://optee.readthedocs.io/en/latest/architecture/core.html)
- Source: `common/spl/spl_atf.c`, `include/atf_common.h`

---

### ARM Exception Levels (EL)

ARMv8-A định nghĩa 4 **Exception Levels** (mức đặc quyền), chạy song song theo 2 world:

```
        ┌──────────────────────────────────────────────────────────────┐
        │                    ARMv8-A Privilege Model                   │
        ├────────────┬──────────────────────────┬──────────────────────┤
        │            │   Secure World           │   Non-Secure World   │
        │            │   (SCR_EL3.NS = 0)       │   (SCR_EL3.NS = 1)   │
        ├────────────┼──────────────────────────┼──────────────────────┤
        │  EL3       │  BL31 (TF-A Runtime)     │   — (EL3 là secure)  │
        │  (Highest) │  Secure Monitor          │                      │
        ├────────────┼──────────────────────────┼──────────────────────┤
        │  EL2       │  — (thường không dùng)   │   Hypervisor         │
        │            │                          │   (KVM, Xen)         │
        ├────────────┼──────────────────────────┼──────────────────────┤
        │  EL1       │  BL32 / TEE OS (OP-TEE)  │   OS Kernel (Linux)  │
        │            │  S-EL1                   │                      │
        ├────────────┼──────────────────────────┼──────────────────────┤
        │  EL0       │  Trusted Apps (TAs)      │   User Apps          │
        │  (Lowest)  │  S-EL0                   │   (Android, etc.)    │
        └────────────┴──────────────────────────┴──────────────────────┘
```

| Component | EL | World | Mô tả |
|---|---|---|---|
| BootROM/BL1 | EL3 | Secure | First code chạy sau reset |
| BL31 (TF-A Runtime) | EL3 | Secure | Chạy **thường trực** suốt lifetime, xử lý SMC |
| BL32 / OP-TEE | S-EL1 | Secure | TEE OS, chạy khi có Trusted App request |
| U-Boot (BL33) | EL2 | Non-Secure | Bootloader, load kernel |
| Linux kernel | EL1 | Non-Secure | OS kernel |
| User apps | EL0 | Non-Secure | Android/Linux userspace |
| Trusted Apps (TAs) | S-EL0 | Secure | Các ứng dụng chạy trong OP-TEE |

> **Quan trọng:** BL31 không "kết thúc" sau khi jump sang U-Boot. Nó **vẫn nằm trong DRAM
> và tiếp tục chạy** ở EL3, xử lý SMC calls từ Linux/U-Boot khi cần. Đây là "EL3 Runtime".

---

### TF-A Boot Stages (BL stages)

ARM Trusted Firmware chia boot thành các **Boot Loader stages**:

```
BL1  ← BootROM hoặc first-stage loader
  │  Reset handler, load BL2
  ▼
BL2  ← Trusted Boot Firmware (thường không có trên Rockchip embedded flow)
  │  Authenticate + load BL31, BL32, BL33
  ▼
BL31 ← EL3 Runtime Firmware (TF-A)       ← chạy THƯỜNG TRỰC ở EL3
  │  Setup PSCI, GIC, TrustZone
  │  eret → BL32 (nếu có TEE) hoặc trực tiếp BL33
  ▼
BL32 ← Secure-EL1 Payload (OP-TEE)       ← tùy chọn, chỉ khi có TEE
  │  Init OP-TEE OS
  │  eret → BL31 → BL33
  ▼
BL33 ← Non-Secure Bootloader (U-Boot)    ← EL2, Non-Secure World
  │  Load kernel FIT
  ▼
OS  ← Linux kernel                        ← EL1, Non-Secure World
```

**Trên RK3576 (không có BL2):**

```
BootROM (BL1 role)
  → DDR blob (không phải BL stage chuẩn, là Rockchip-specific)
  → SPL (đóng vai BL2: load BL31 + U-Boot vào DRAM)
  → BL31 (TF-A, qua spl_invoke_atf)
  → U-Boot (BL33)
  → Linux
```

---

### SMC (Secure Monitor Call) và PSCI

#### SMC là gì?

**SMC (Secure Monitor Call)** là cơ chế để code ở EL1/EL2 giao tiếp với Secure Monitor
(EL3/BL31). Đây là "syscall" của TrustZone.

```
Normal World (EL1/EL2)          Secure Monitor (EL3 / BL31)
────────────────────────         ──────────────────────────────
smc #0x84000001                 ←── SMC exception trap → BL31
  x0 = Function ID               BL31 dispatch theo Function ID:
  x1..x7 = args                    - PSCI functions (CPU on/off/suspend)
                                   - SMC64 (platform-specific)
                                   - SMCCC standard calls
                              ─── eret → trở về EL1/EL2 với kết quả x0
```

#### PSCI (Power State Coordination Interface)

PSCI là tập hợp SMC calls chuẩn của ARM để quản lý power state:

| PSCI Function | SMC ID | Mô tả |
|---|---|---|
| `PSCI_CPU_ON` | `0x84000003` | Bật thêm CPU core (SMP) |
| `PSCI_CPU_OFF` | `0x84000002` | Tắt CPU core hiện tại |
| `PSCI_CPU_SUSPEND` | `0x84000001` | Suspend CPU (sleep) |
| `PSCI_SYSTEM_OFF` | `0x84000008` | Tắt máy |
| `PSCI_SYSTEM_RESET` | `0x84000009` | Reboot |
| `PSCI_FEATURES` | `0x8400000A` | Query PSCI feature support |

**U-Boot dùng PSCI để:**
```c
// Ví dụ: reset hệ thống từ U-Boot
psci_sys_reset();
// → SMC #0x84000009 → BL31 handles → shutdown/reset hardware
```

**Linux kernel dùng PSCI để:**
```
// Khi boot multi-core SMP:
PSCI_CPU_ON(cpu_id, entry_point, context_id)
→ BL31: set entry point, power on CPU, CPU starts at entry_point in EL1
```

---

### TEE — Trusted Execution Environment

**TEE** là môi trường thực thi có bảo vệ phần cứng (TrustZone). Mọi code và data trong
TEE đều không thể bị đọc/ghi bởi Normal World (Linux, Android).

```
┌──────────────────────┐    ┌──────────────────────┐
│   NORMAL WORLD       │    │   SECURE WORLD        │
│   (Linux / Android)  │    │   (TEE)               │
│                      │    │                       │
│   Client Application │    │   Trusted Application │
│   (CA)               │◄──►│   (TA)                │
│     ↓ TEE Client API │    │     ↑ TEE Internal API│
│   TEE driver         │    │   OP-TEE OS (S-EL1)   │
│   (Linux kernel)     │    │     ↑                 │
│         ↓ SMC        │    │   BL31 (EL3)          │
│   ──────────────     │    │   ──────────────       │
│   EL1 / EL0          │    │   S-EL1 / S-EL0       │
└──────────────────────┘    └──────────────────────┘
         Hardware: ARM TrustZone (SCR_EL3.NS bit)
```

#### OP-TEE OS

**OP-TEE** là implementation phổ biến nhất của TEE, được dùng trên hầu hết ARM boards:

| Component | Mô tả |
|---|---|
| `optee_os` | TEE OS chạy ở S-EL1 |
| `optee_client` | Library cho Normal World app (CA) |
| `tee-supplicant` | Daemon Linux phục vụ RPC từ OP-TEE |
| `Trusted Applications` | `.ta` files, load vào S-EL0 khi cần |

#### Luồng SMC khi CA gọi TA

```
Normal World                    Secure Monitor (EL3)    Secure World (S-EL1)
────────────                    ──────────────          ────────────────────
CA: TEEC_OpenSession()
  → libteec.so
    → /dev/tee0
      → TEE driver (EL1)
        → SMC (TEE_FUNC_INVOKE)
          ──────────────────────► BL31 exception
                                  Save NS context
                                  Restore S context
                                  ◄── eret to S-EL1 ──► OP-TEE OS
                                                        Assign trusted thread
                                                        Find/load TA
                                                        Execute TA function
                                                        SMC (return)
                                  Save S context ◄──────
                                  Restore NS context
                                  ──────────────────────► eret to EL1
      ← return result
CA: TEEC_InvokeCommand()
```

#### Use cases điển hình của TEE

| Use case | Ví dụ |
|---|---|
| **Secure key storage** | Android Keystore, private keys không bao giờ ra Normal World |
| **DRM decryption** | Widevine L1: decrypt video trong TEE, output thẳng ra display |
| **Biometric auth** | Fingerprint/Face ID: template lưu trong TEE |
| **Secure payment** | Mobile payment tokens (GPay, SamsungPay) |
| **Attestation** | Chứng minh device không bị root (SafetyNet) |
| **Disk encryption** | FDE/FBE keys lưu trong TEE |

---

### BL31 trên RK3576: Vai trò runtime

Sau khi SPL jump vào BL31 (`spl_invoke_atf()`), BL31 **không kết thúc** mà tiếp tục:

```
SPL → spl_invoke_atf()
  │
  ▼
BL31 (rk3576_bl31_v*.elf) @ 0x40060000    EL3 (thường trực)
  │
  ├─ [Init] GIC (Generic Interrupt Controller)
  │         → route FIQ/IRQ giữa Secure/Non-Secure world
  │
  ├─ [Init] TrustZone DRAM protection
  │         → TZASC (TrustZone Address Space Controller)
  │         → Phân vùng DRAM: Secure region vs Non-Secure region
  │         → BL31/OP-TEE region không thể đọc từ Linux
  │
  ├─ [Init] PSCI handlers
  │         → psci_cpu_on(), psci_cpu_suspend(), system_reset()
  │
  ├─ [Init] Exception vectors EL3 (VBAR_EL3)
  │         → Trap tất cả SMC instructions
  │
  └─ [Jump] eret → U-Boot @ 0x40800000 (EL2, Non-Secure)
  │
  │       ... U-Boot chạy, load kernel ...
  │
  ├─ [Runtime] Linux kernel SMC calls:
  │         → PSCI_CPU_ON để boot secondary cores (A53 cluster)
  │         → PSCI_SYSTEM_RESET khi reboot
  │         → Platform SMC (RK3576 specific: suspend/resume)
  │
  └─ [Runtime] OP-TEE SMC calls (nếu có):
              → Forward SMC từ Linux TEE driver → OP-TEE OS
```

---

### `spl_invoke_atf()` — Chi tiết code

**File:** `common/spl/spl_atf.c`

```c
void __noreturn spl_invoke_atf(struct spl_image_info *spl_image)
{
    ulong bl32_entry = 0;
    ulong bl33_entry = CONFIG_TEXT_BASE;    // = 0x40800000 (U-Boot)
    void *blob = spl_image->fdt_addr;      // DTB address

    // 1. Tìm OP-TEE entry trong /fit-images (nếu có BL32)
    //    Tìm node có os = "tee" (IH_OS_TEE)
    node = spl_fit_images_find(blob, IH_OS_TEE);
    if (node >= 0)
        bl32_entry = spl_fit_images_get_entry(blob, node);
    // RK3576 không có TEE → bl32_entry = 0

    // 2. Tìm U-Boot entry trong /fit-images
    node = spl_fit_images_find(blob, IH_OS_U_BOOT);
    if (node >= 0)
        bl33_entry = spl_fit_images_get_entry(blob, node);
    // → bl33_entry = 0x40800000

    // 3. Gọi bl31_entry() — KHÔNG RETURN
    bl31_entry(spl_image->entry_point,  // BL31 @ 0x40060000
               bl32_entry,              // BL32 (OP-TEE) = 0 hoặc addr
               bl33_entry,              // BL33 (U-Boot) @ 0x40800000
               platform_param);         // DTB address cho BL31
}

static void __noreturn bl31_entry(ulong bl31_entry, ulong bl32_entry,
                                  ulong bl33_entry, ulong fdt_addr)
{
    // 4. Tạo bl31_params structure
    //    bl2_to_bl31_params_mem:
    //      bl32_ep_info.pc   = bl32_entry (OP-TEE, = 0 nếu không có)
    //      bl32_ep_info.spsr = SPSR_64(EL1, SP_ELX, DAIF_MASK)  ← Secure EL1
    //      bl33_ep_info.pc   = bl33_entry (= 0x40800000)
    //      bl33_ep_info.spsr = SPSR_64(EL2, SP_ELX, DAIF_MASK)  ← Non-Secure EL2
    bl31_params = bl2_plat_get_bl31_params(bl32_entry, bl33_entry, fdt_addr);
    //
    // bl33_ep_info.spsr = SPSR_64(MODE_EL2, MODE_SP_ELX, DISABLE_ALL):
    //   → BL31 sẽ eret sang EL2, non-secure, tức là U-Boot chạy ở EL2

    // 5. Disable D-cache trước khi chuyển sang EL3
    dcache_disable();

    // 6. Jump to BL31 entry point với tham số
    //    x0 = bl31_params pointer (struct bl2_to_bl31_params_mem *)
    //    x1 = fdt_addr (platform parameter)
    atf_entry(bl31_params, (void *)fdt_addr);
    // → CPU mode chuyển thành EL3 Secure
    // → BL31 đọc bl31_params → biết địa chỉ BL32 + BL33
    // → BL31 eret → BL33 (U-Boot) @ EL2 Non-Secure
}
```

#### Cấu trúc `bl31_params` (ATF v1 API)

```c
// include/atf_common.h
struct bl2_to_bl31_params_mem {
    struct bl31_params  bl31_params;       // Header
    struct atf_image_info bl31_image_info; // BL31 image info
    struct atf_image_info bl32_image_info; // BL32 (OP-TEE) image info
    struct atf_image_info bl33_image_info; // BL33 (U-Boot) image info
    struct entry_point_info bl33_ep_info;  // U-Boot entry: pc=0x40800000, EL2, NS
    struct entry_point_info bl32_ep_info;  // OP-TEE entry: pc=0 (không có)
    struct entry_point_info bl31_ep_info;  // (không dùng trong v1)
};

struct entry_point_info {
    struct param_header h;  // type, version, size, attr (SECURE=0 / NON_SECURE=1)
    uintptr_t pc;           // Entry point address
    uint32_t spsr;          // SPSR: EL, SP, DAIF bits
    struct aapcs64_params args;  // x0..x7 khi jump
};
```

#### Giải thích `SPSR_64` macro

```c
// SPSR_64(el, sp, daif):
// bl32 (OP-TEE): SPSR_64(MODE_EL1, MODE_SP_ELX, DISABLE_ALL)
//   → eret tới S-EL1 (Secure EL1), SP_ELX, DAIF masked
//   → OP-TEE OS khởi động tại S-EL1
//
// bl33 (U-Boot): SPSR_64(MODE_EL2, MODE_SP_ELX, DISABLE_ALL)
//   → eret tới EL2 Non-Secure, SP_ELX, DAIF masked
//   → U-Boot chạy tại EL2 (Hypervisor level) trong Non-Secure world
```

---

### OP-TEE trên RK3576: Trạng thái hiện tại

Config hiện tại (`evb_rk3576_qnm_defconfig`):

```kconfig
# CONFIG_OPTEE_LIB is not set    ← OP-TEE tắt
```

Điều này có nghĩa:

| | **Có OP-TEE** | **Không có OP-TEE (hiện tại)** |
|---|---|---|
| `bl32_entry` | Địa chỉ OP-TEE trong DRAM | `0` (NULL) |
| FIT có node `tee-os` | Có | Không |
| BL31 sau init | eret → OP-TEE (S-EL1) → U-Boot | eret trực tiếp → U-Boot (EL2) |
| Secure key store | Có (Android Keystore TEE) | Không |
| Widevine L1 | Có | Không (chỉ L3) |
| Build output | Không có cảnh báo | `missing optional external blobs: tee-os` |

> Build warning "`Image is missing optional external blobs but is still functional: tee-os`"
> là **bình thường** khi `CONFIG_OPTEE_LIB` tắt. Image vẫn hoạt động đầy đủ.

#### Để bật OP-TEE (nếu cần trong tương lai)

```bash
# 1. Cần OP-TEE binary cho RK3576
TEE=../rkbin/bin/rk35/rk3576_bl32_v*.bin  # hoặc ELF format

# 2. Bật trong defconfig:
# CONFIG_OPTEE_LIB=y
# CONFIG_OPTEE_IMAGE=y

# 3. Build:
make -j$(nproc) BL31=$BL31 ROCKCHIP_TPL=$ROCKCHIP_TPL TEE=$TEE

# 4. FIT sẽ có thêm node tee-1 với os = "tee"
# 5. spl_invoke_atf() sẽ set bl32_entry = OP-TEE entry point
# 6. BL31 sẽ khởi động OP-TEE trước khi jump sang U-Boot
```

---

### Memory map với và không có OP-TEE

```
DRAM layout (RK3576, 4GB LPDDR):

Với OP-TEE:                          Không có OP-TEE (hiện tại):
──────────────────────────           ──────────────────────────
0x3FE70000  BL31 vectors  16KB       0x3FE70000  BL31 vectors  16KB
0x40060000  BL31 main    120KB       0x40060000  BL31 main    120KB
0x400F0000  BL31 RO       20KB       0x400F0000  BL31 RO       20KB
0x08400000  OP-TEE        ~8MB       (không có OP-TEE region)
0x40800000  U-Boot       ~900KB      0x40800000  U-Boot       ~900KB
0x40B30000  DTB           183KB      0x40B30000  DTB           183KB
            ↑ TZASC bảo vệ                        (không có TZASC partition)
            BL31 + OP-TEE region
            Linux không đọc được
```

---

### Tóm tắt: TF-A, TEE và U-Boot

```
                    ┌─────────────────────────────────────────┐
                    │              ARM TrustZone               │
     Secure World   │                                         │  Non-Secure World
     ───────────────┼─────────────────────────────────────────┼──────────────────
     EL3 │  BL31    │  Secure Monitor, PSCI, SMC dispatcher  │  (EL3 is secure)
         │  (TF-A)  │  Runs PERMANENTLY in RAM after boot    │
     ────┼──────────┼─────────────────────────────────────────┼──────────────────
     S-EL1│ OP-TEE │  TEE OS (optional)                      │  Linux kernel EL1
          │ (BL32)  │  Trusted Applications @ S-EL0          │  User apps EL0
     ─────┴─────────┼─────────────────────────────────────────┼──────────────────
                    │   Communication via SMC instruction     │
                    │   (EL1→EL3: smc #funcid)               │
                    └─────────────────────────────────────────┘

Boot sequence của SPL → BL31:
  common/spl/spl_atf.c : spl_invoke_atf()
    → bl2_plat_get_bl31_params()   // tạo struct với bl32=0, bl33=0x40800000
    → dcache_disable()
    → atf_entry(bl31_params, fdt_addr)
         → BL31 init EL3
         → OP-TEE (nếu có): eret → S-EL1 → init → eret → EL3 → ...
         → BL31 eret → U-Boot @ EL2 Non-Secure

Runtime (Linux chạy):
  Linux → smc PSCI_CPU_ON → BL31 → power on CPU core → eret → EL1 (Linux)
  Linux → smc PSCI_SYSTEM_RESET → BL31 → reset hardware
  Linux TEE driver → smc → BL31 → forward → OP-TEE → TA execution → return
```

---

## Trace Code: Boot Flow theo Source

---

### Phần 1 — TPL/SPL trong U-Boot: Cơ chế tổng quát

Tham khảo: [deepwiki openbmc/u-boot — SPL and TPL](https://deepwiki.com/openbmc/u-boot/2.3-spl-and-tpl)

#### Mục đích TPL và SPL

SPL và TPL là các phiên bản rút gọn của U-Boot, được build từ cùng source nhưng với các
`CONFIG_*_BUILD` flag khác nhau, dùng cho môi trường constrained trước khi U-Boot proper chạy:

| Stage | Build flag | Chạy ở | Nhiệm vụ chính |
|---|---|---|---|
| **TPL** | `CONFIG_TPL_BUILD` | SRAM nội | Minimal HW init (clocks, GPIO); **load SPL** |
| **SPL** | `CONFIG_SPL_BUILD` | SRAM/DRAM | DRAM init; setup stack/malloc; **load U-Boot** |
| **U-Boot** | *(không set)* | DRAM | Full drivers; boot OS |

#### Sequence khởi tạo (khi `CONFIG_TPL=y`)

```
ROM Code / Reset
  │
  ▼
TPL  (tpl/u-boot-tpl.bin)
  │  board_init_f()  ← minimal HW init, chạy trong SRAM
  │  board_init_r()  ← load SPL, jump to SPL
  ▼
SPL  (spl/u-boot-spl.bin)
  │  board_init_f()
  │    ├─ spl_early_init()        ← [spl.c:479] init malloc, DM, DTB
  │    └─ dram_init() BỎ QUA      ← #if !defined(CONFIG_TPL)
  │  [stack relocation to DRAM]
  │  board_init_r()               ← [spl.c:624]
  │    ├─ spl_init()              ← [spl.c:495]
  │    ├─ boot_from_devices()     ← load U-Boot image
  │    └─ jump_to_image()
  ▼
U-Boot proper
  │  board_init_f() → relocation → board_init_r()
  └─ run_main_loop() → autoboot / shell
```

#### Sequence khởi tạo (khi **không có** `CONFIG_TPL`)

```
ROM Code / Reset
  │
  ▼
SPL  (spl/u-boot-spl.bin)
  │  board_init_f()
  │    ├─ spl_early_init()        ← [spl.c:479] init malloc, DM, DTB
  │    └─ dram_init() CHẠY        ← !defined(CONFIG_TPL) → vào nhánh này
  │  [stack relocation to DRAM]
  │  board_init_r()               ← [spl.c:624]
  │    ├─ spl_init()              ← [spl.c:495]
  │    ├─ boot_from_devices()     ← load U-Boot image
  │    └─ jump_to_image()
  ▼
U-Boot proper
```

#### Các hàm cốt lõi trong `common/spl/spl.c`

**`spl_early_init()` — spl.c:479**

```c
int spl_early_init(void)
{
    ret = spl_common_init(true);    // setup_malloc=true → init malloc pool sớm
    gd->flags |= GD_FLG_SPL_EARLY_INIT;
}

static int spl_common_init(bool setup_malloc)
{
    // (a) malloc pool sớm trong SRAM (pre-relocation)
    gd->malloc_base  = CFG_MALLOC_F_ADDR;
    gd->malloc_limit = CONFIG_VAL(SYS_MALLOC_F_LEN);

    // (b) bootstage + logging
    bootstage_init(xpl_is_first_phase());
    log_init();

    // (c) Parse DTB được binman nhúng vào SPL binary
    fdtdec_setup();

    // (d) Init Driver Model — chỉ probe device có bootph-* annotation
    dm_init_and_scan(!CONFIG_IS_ENABLED(OF_PLATDATA));
    dm_autoprobe();
}
```

**`spl_init()` — spl.c:495**

```c
int spl_init(void)
{
    // Chỉ chạy spl_common_init nếu spl_early_init() chưa được gọi trước đó
    if (!(gd->flags & GD_FLG_SPL_EARLY_INIT))
        spl_common_init(setup_malloc);

    gd->flags |= GD_FLG_SPL_INIT;
}
```

**`board_init_r()` SPL — spl.c:624**

```c
void board_init_r(gd_t *dummy1, ulong dummy2)
{
    spl_set_bd();
    mem_malloc_init(...);           // full malloc pool trong DRAM
    spl_init();                     // no-op nếu spl_early_init đã chạy
    bloblist_init();
    setup_spl_handoff();            // chuẩn bị DRAM info để pass cho U-Boot
    dram_init_banksize();
    board_boot_order(spl_boot_list);
    boot_from_devices(&spl_image, spl_boot_list, ...);
    // → chọn jumper dựa trên spl_image.os:
    //   IH_OS_U_BOOT              → jump_to_image()
    //   IH_OS_ARM_TRUSTED_FIRMWARE → spl_invoke_atf()   ← RK3576 dùng nhánh này
    //   IH_OS_TEE                 → jump_to_image_optee()
    //   IH_OS_LINUX               → jump_to_image_linux()  (Falcon mode)
    write_spl_handoff();
    spl_board_prepare_for_boot();
    jumper(&spl_image);             // KHÔNG RETURN
}
```

#### Stack/heap relocation

```
board_init_f() kết thúc
  │
  ▼ (assembly)
spl_relocate_stack_gd()             // common/spl/spl.c
  → Tính địa chỉ stack mới trong DRAM (CONFIG_SPL_STACK_R_ADDR)
  → Copy global_data (gd) sang DRAM
  → Trả về stack pointer mới
  │
  ▼ (assembly set sp = new_sp, gd = new_gd)
board_init_r()                      // DRAM stack sẵn sàng
```

#### `bootph-*` annotations — Device Model trong SPL/TPL

SPL/TPL dùng Device Model nhưng chỉ probe các device **được đánh dấu** trong DTS để giữ
binary nhỏ. Annotations trong DTS overlay (`rk3576-u-boot.dtsi`):

| Annotation | Phase áp dụng | Ý nghĩa |
|---|---|---|
| `bootph-all` | TPL + SPL + U-Boot | Luôn compile vào mọi stage |
| `bootph-pre-ram` | SPL (trước DRAM init) | Cần trước khi DRAM đầy đủ |
| `bootph-some-ram` | SPL (sau DRAM init) | Cần khi có DRAM |

#### Device hand-off giữa các stage

```
SPL
  └─ setup_spl_handoff()            // tạo entry BLOBLISTT_U_BOOT_SPL_HANDOFF
  └─ handoff_save_dram(ho)          // lưu bi_dram[] (size/bank) vào bloblist
  └─ write_spl_handoff()
       │  bloblist tồn tại trong DRAM, survive qua jump
       ▼
U-Boot proper
  └─ bloblist_find(BLOBLISTT_U_BOOT_SPL_HANDOFF)
  └─ Đọc DRAM info → không cần probe lại
```

---

### Phần 2 — Radxa ROCK 4D (RK3576): Boot Flow chi tiết

#### Điểm khác biệt so với u-boot tổng quát

| | **U-Boot tổng quát (`CONFIG_TPL=y`)** | **ROCK 4D (RK3576)** |
|---|---|---|
| TPL | `tpl/u-boot-tpl.bin` (u-boot code) | `rk3576_ddr_*.bin` (Rockchip blob) |
| `CONFIG_TPL` | được set | **không set** |
| DRAM training | TPL u-boot làm | DDR blob làm (closed-source) |
| SPL `dram_init()` | bỏ qua (`#if !defined(CONFIG_TPL)`) | **chạy** — đọc lại DRAM size |
| Sau SPL jump tới | U-Boot / OS trực tiếp | **BL31 (TF-A)** trước, rồi mới U-Boot |

> **Lý do `CONFIG_TPL` không set:** ROCK 4D sử dụng **external TPL riêng** là DDR blob
> closed-source của Rockchip. U-Boot không build TPL stage cho board này vì TPL đã được
> thay thế hoàn toàn bởi blob ngoài. `ROCKCHIP_TPL` chỉ là biến Makefile trỏ đến blob để
> `mkimage` đóng gói vào `idbloader.img`, không liên quan đến `CONFIG_TPL`.

#### Call graph đầy đủ cho ROCK 4D

```
BootROM (silicon, không thể sửa)
  │  Quét SPI NOR (offset 0x8000) hoặc SD/eMMC (sector 64)
  │  Tìm magic "RKNS" → load TPL vào SRAM nội
  │
  ▼
[External TPL: rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v*.bin]
  │  Closed-source blob, Rockchip cung cấp qua rkbin
  │  Chạy trong SRAM (~192KB), không có DRAM
  │  → LPDDR4/LPDDR5 training (timing calib, ZQ calib, DQS gate training)
  │  → Init DRAM controller
  │  → Output @ 1,500,000 baud (hardcoded trong blob)
  │  → Load u-boot-spl.bin vào DRAM, jump → SPL _start
  │
  ▼  ════════════════════════ SPL ════════════════════════════════════
arch/arm/cpu/armv8/start.S          ← assembly entry point của SPL
  │  Setup CPU state, clear BSS, init sp
  │
  ▼
arch/arm/mach-rockchip/spl.c
board_init_f()                      ← Phase: CONFIG_SPL_BUILD
  ├─ board_early_init_f()           (weak no-op trên RK3576)
  ├─ spl_early_init()               common/spl/spl.c:479
  │    └─ spl_common_init(true)
  │         ├─ malloc pool init     SRAM @ CFG_MALLOC_F_ADDR
  │         ├─ bootstage_init()
  │         ├─ fdtdec_setup()       parse DTB được binman nhúng vào SPL
  │         ├─ dm_init_and_scan()   probe devices có bootph-* trong DTB:
  │         │    ├─ CRU (clocks)   [bootph-all]
  │         │    ├─ pinctrl        [bootph-all]
  │         │    ├─ serial         [bootph-all]
  │         │    ├─ SFC NOR flash  [bootph-pre-ram + bootph-some-ram]
  │         │    ├─ SDMMC          [bootph-pre-ram + bootph-some-ram]
  │         │    └─ SDHCI (eMMC)   [bootph-pre-ram + bootph-some-ram]
  │         └─ dm_autoprobe()
  ├─ arch_cpu_init()                (weak no-op)
  ├─ rockchip_stimer_init()         init Rockchip system timer
  ├─ dram_init()                    !CONFIG_TPL → chạy
  │    → không training DRAM (DDR blob đã làm)
  │    → đọc DRAM size → gd->ram_size, gd->ram_base
  │    → gd->ram_top = gd->ram_base + effective_memsize
  ├─ arch_reserve_mmu()             dự trữ page table ở top of DRAM
  ├─ enable_caches()                bật D-cache + I-cache
  └─ preloader_console_init()       UART @ 115200 (CONFIG_BAUDRATE), in SPL banner
  │
  ▼  [stack relocation to DRAM]
spl_relocate_stack_gd()             common/spl/spl.c
  → stack pointer mới trong DRAM (CONFIG_SPL_STACK_R_ADDR)
  → copy gd sang DRAM
  │
  ▼
board_init_r()                      common/spl/spl.c:624
  ├─ spl_set_bd()
  ├─ mem_malloc_init()              full malloc pool trong DRAM
  ├─ spl_init()                     common/spl/spl.c:495
  │    └─ GD_FLG_SPL_EARLY_INIT đã set → không gọi lại spl_common_init
  ├─ timer_init()
  ├─ bloblist_init()
  ├─ setup_spl_handoff()            tạo BLOBLISTT_U_BOOT_SPL_HANDOFF
  ├─ dram_init_banksize()           điền gd->bd->bi_dram[] (cần cho ATF)
  ├─ lmb_init()
  ├─ pci_init()                     CONFIG_PCI=y trên evb_rk3576_qnm
  ├─ board_boot_order()
  │    → đọc DTS: u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci
  │    → spl_boot_list = [BOOT_DEVICE_SPI, BOOT_DEVICE_MMC1, BOOT_DEVICE_MMC2]
  ├─ boot_from_devices()
  │    └─ spl_spi_load_image()      nếu boot từ SPI NOR (offset 0x60000)
  │    └─ spl_mmc_load_image()      nếu boot từ SD/eMMC (sector 16384)
  │         └─ spl_load_simple_fit()
  │              ├─ load [atf-1] → 0x3FE70000  (BL31 exception vectors,  16KB)
  │              ├─ load [atf-2] → 0x40060000  (BL31 main code,         120KB)
  │              ├─ load [atf-3] → 0x400F0000  (BL31 RO data,            20KB)
  │              └─ load [u-boot]→ 0x40800000  (U-Boot proper,          ~900KB)
  │              điền: spl_image.os          = IH_OS_ARM_TRUSTED_FIRMWARE
  │              điền: spl_image.entry_point = 0x40060000
  ├─ jumper = spl_invoke_atf        os == IH_OS_ARM_TRUSTED_FIRMWARE
  ├─ write_spl_handoff()            ghi DRAM info → bloblist
  ├─ spl_board_prepare_for_boot()   flush D-cache (cleanup_before_linux)
  └─ spl_invoke_atf(&spl_image)     common/spl/spl_atf.c:254
       ├─ bl32_entry = 0            không có OP-TEE trong config này
       ├─ bl33_entry = 0x40800000   U-Boot proper (từ /fit-images node)
       └─ bl31_entry(0x40060000,    ← BL31 entry point
                     0,             ← bl32 (OP-TEE, không có)
                     0x40800000,    ← bl33 (U-Boot proper)
                     fdt_addr)      ← DTB address (platform param)
  │
  ▼  ════════════════════════ BL31 / TF-A (EL3) ═══════════════════════
rk3576_bl31_v*.elf @ 0x40060000
  │  Chạy ở EL3 (Exception Level 3 — highest privilege)
  │  → GIC init, exception vectors EL3
  │  → TrustZone memory partition
  │  → PSCI handlers: CPU_ON/OFF, SYSTEM_RESET, SYSTEM_OFF
  │  → SPSR = EL2 | AArch64 | IRQ/FIQ masked
  │  eret → jump to U-Boot @ 0x40800000, EL2
  │
  ▼  ════════════════════════ U-Boot proper (EL2) ════════════════════
common/board_r.c : board_init_r()
  └─ initcall_run_r()
       ├─ initr_reloc()             set GD_FLG_RELOC
       ├─ initr_caches()            enable D-cache post-relocation
       ├─ initr_malloc()            full heap (CONFIG_SYS_MALLOC_LEN)
       ├─ initr_of_live()           parse live device tree (full DTS)
       ├─ initr_dm()                Driver Model full (không có bootph filter)
       ├─ board_init()              arch/arm/mach-rockchip/board.c
       ├─ initr_dm_devices()        probe tất cả devices trong DTS
       ├─ serial_initialize()       UART devices
       ├─ initr_announce()          in "Model: Radxa ROCK 4D QNM"
       ├─ power_init_board()        PMIC RK806 init
       ├─ initr_mmc()               MMC controllers
       ├─ initr_env()               load environment
       ├─ initr_net()               Ethernet DWC_ETH_QOS
       ├─ board_late_init()         set boot_targets (SPI→UFS→SD→USB)
       └─ run_main_loop()
            └─ main_loop()          autoboot countdown → bootcmd / shell "=> "
```

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
