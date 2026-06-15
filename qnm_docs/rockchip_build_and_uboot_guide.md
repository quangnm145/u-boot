# Hướng Dẫn Bring-up Bootloader cho Radxa Rock 4D (Dựa trên Das U-Boot / Upstream)

Vì mục tiêu của bạn là tự build lại bootloader dựa trên Das U-Boot (trong thư mục `raxda/u-boot`) nhưng vẫn tận dụng các blob nhị phân (TPL/ATF) từ bộ SDK Rockchip (`buildroot/rkbin`), dưới đây là quy trình chuẩn xác sử dụng **Binman**.

Luồng khởi động của bạn sẽ là:
**Bootrom -> TPL (DDR blob từ rkbin) -> SPL (từ u-boot) -> ATF (bl31 từ rkbin) -> OP-TEE (tùy chọn) -> U-Boot Proper -> Kernel.**

### Bước 1: Khởi tạo mã nguồn và cấu hình
1. Đi vào thư mục Das U-Boot của bạn:
   ```bash
   cd /home/quangnm/workdir/raxda/u-boot
   ```
2. Nếu bạn chưa có file defconfig cho Rock 4D, hãy tạo nó. Trong trường hợp bạn đã có `configs/rock-4d-rk3576_defconfig`, hãy dùng nó. Đảm bảo bên trong defconfig có tham số:
   ```makefile
   CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3576-rock-4d"
   ```

### Bước 2: Chuẩn bị biến môi trường (Chỉ định các Blobs của SDK Rockchip)
Das U-Boot sử dụng Binman để tự động đóng gói (pack) các file nhị phân thành một file `u-boot-rockchip.bin` duy nhất để flash trực tiếp. Bạn phải khai báo đường dẫn trỏ tới các file nhị phân trong SDK `buildroot` của bạn.

Chạy các lệnh export sau trên terminal trước khi build:
```bash
# 1. Trỏ đến file Arm Trusted Firmware (TF-A / BL31)
export BL31=/home/quangnm/workdir/buildroot/rkbin/bin/rk35/rk3576_bl31_v1.12.elf

# 2. Trỏ đến OP-TEE (Tùy chọn, nếu bạn dùng TEE cho bảo mật)
# CHÚ Ý: File Device Tree của U-Boot (rockchip-u-boot.dtsi) đã được patch
# để nhận diện trực tiếp file .bin thô này thay vì bắt buộc dùng file ELF.
export TEE=/home/quangnm/workdir/buildroot/rkbin/bin/rk35/rk3576_bl32_v1.04.bin

# 3. Trỏ đến file khởi tạo DDR của Rockchip (TPL)
export ROCKCHIP_TPL=/home/quangnm/workdir/buildroot/rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin
```

### Bước 3: Biên dịch Bootloader
Vẫn tại thư mục `raxda/u-boot`, chọn cấu hình và tiến hành build:
```bash
export CROSS_COMPILE=aarch64-linux-gnu-
make rock-4d-rk3576_defconfig
make -j$(nproc)
```

Quá trình này sẽ sử dụng binman đọc tệp device tree (ví dụ `rk3576-u-boot.dtsi`) để tự động nhúng TPL, SPL, BL31, TEE và U-boot Proper.
Kết quả cuối cùng thu được trong thư mục hiện tại sẽ là file: **`u-boot-rockchip.bin`** (đã bao gồm toàn bộ mọi thứ).

### Bước 4: Ghi hình ảnh (Flash) vào SD Card/eMMC
Bootrom của Rockchip mặc định quét bootloader ở **Sector 64** (tương đương với offset 32KB) trên thẻ SD hoặc eMMC.
Dùng lệnh `dd` để flash file bin này vào bộ nhớ lưu trữ:
```bash
sudo dd if=u-boot-rockchip.bin of=/dev/sdX seek=64 bs=512 conv=notrunc
sync
```
*(Thay thế `/dev/sdX` bằng đường dẫn thực tế của thẻ nhớ)*

Sau khi hoàn tất, hãy cắm thẻ SD vào mạch Radxa Rock 4D, mở kết nối Serial (UART) ở tốc độ Baudrate `1500000` (dựa theo config hiện tại của bạn) và tận hưởng U-Boot tự build khởi động!
