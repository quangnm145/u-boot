# Tổng hợp quá trình Bring-up U-Boot cho Radxa Rock 4D (RK3576)

Quá trình porting Upstream Das U-Boot lên nền tảng RK3576 (cụ thể là board Radxa Rock 4D) gặp khá nhiều rào cản do sự khác biệt giữa chuẩn của Upstream và quy trình đóng gói độc quyền của Rockchip. Dưới đây là tổng hợp toàn bộ các thay đổi và lý do đằng sau những thiết lập đó.

## 1. Cấu hình U-Boot (Defconfig & Kconfig)

Mọi cấu hình gốc của U-Boot được đặt trong file `configs/evb_rk3576_qnm_defconfig`.

### a. Vô hiệu hóa Binman
Mặc định, Upstream U-Boot sử dụng Binman để đóng gói các firmware nhị phân (TPL, SPL, ATF, OP-TEE). Tuy nhiên, trên RK3576, Binman gặp lỗi khi xử lý các file OP-TEE dạng `.bin` (do Binman đòi hỏi chuẩn `.elf`). Để vượt qua rào cản này, chúng ta quyết định **tắt hoàn toàn Binman** và đóng gói thủ công.
```ini
# CONFIG_BINMAN is not set
```
*(Chúng ta cũng phải sửa file `arch/arm/Kconfig` để gỡ bỏ phụ thuộc bắt buộc vào Binman của kiến trúc Rockchip).*

### b. Kích hoạt chuẩn FIT Image
Do không dùng Binman, chúng ta phải bật hệ thống hỗ trợ chuẩn FIT (Flattened Image Tree) để nạp các thành phần bảo mật.
```ini
CONFIG_FIT=y
CONFIG_SPL_FIT=y
CONFIG_SPL_LOAD_FIT=y
CONFIG_SPL_ATF=y
```

### c. Cấu hình Load Address và Baudrate
*   **TEXT_BASE (`0x40800000`)**: Rockchip SDK mặc định U-Boot chạy ở `0x40200000`, nhưng Upstream U-Boot được thiết kế để chạy ở `0x40800000` nhằm tránh ghi đè lên các vùng nhớ khởi tạo sớm. Việc tuân thủ đúng `0x40800000` giúp U-Boot không bị crash khi cấp phát bộ nhớ.
*   **Baudrate (`1500000`)**: Upstream mặc định baudrate là `115200`. Tuy nhiên, Rockchip sử dụng `1500000`. Việc không đồng bộ baudrate khiến cho quá trình khởi động bị "câm" (không in ra log), dẫn đến việc Watchdog phần cứng tự động reset lại mạch sau vài giây do không được U-Boot feed.

```ini
CONFIG_TEXT_BASE=0x40800000
CONFIG_BAUDRATE=1500000
CONFIG_DEBUG_UART_ANNOUNCE=y
```

## 2. Xử lý Device Tree (DTSI)

Để tắt triệt để các cảnh báo lỗi của Binman, file `arch/arm/dts/rockchip-u-boot.dtsi` đã được chỉnh sửa để loại bỏ các Node quy định bắt buộc phải đóng gói OP-TEE và ATF bằng Binman. Nhờ đó, quá trình biên dịch `make` sinh ra file `u-boot.bin` mà không bị ngắt quãng bởi lỗi thiếu file nhị phân.

## 3. Script đóng gói tùy chỉnh (`pack_rockchip.sh`)

Sự khác biệt lớn nhất nằm ở khâu đóng gói. Thay vì dùng Binman, chúng ta viết một bash script lai (`pack_rockchip.sh`), mượn một số công cụ mã nguồn đóng từ Rockchip SDK (`boot_merger` và `fit.sh`) để tạo ra file image cuối cùng.

### a. Vấn đề 1: Tránh lỗi mất Device Tree (Silent Panic)
Upstream U-Boot (`CONFIG_OF_SEPARATE=y`) mong đợi file cấu hình phần cứng (DTB) được dán cứng (appended) ngay sau đuôi file thực thi. Nếu không tìm thấy, nó sẽ gọi hàm `panic()` và reset ngay lập tức.
Script `fit.sh` của Rockchip lại bóc tách chúng ra làm 2 thành phần độc lập (`u-boot-nodtb.bin` và file `fdt` riêng).
**Giải pháp:** Đánh lừa Rockchip bằng cách copy nguyên file `u-boot.bin` (file đã được Upstream tự động đính sẵn DTB ở đuôi) và đổi tên nó thành `u-boot-nodtb.bin`. Khi đó, U-Boot khi chạy sẽ đọc đúng địa chỉ nhãn `_end` và tìm thấy cây FDT của mình.

### b. Vấn đề 2: Sửa lỗi Address Mismatch
Script `fit.sh` cứng nhắc thiết lập Load Address của U-Boot vào `0x40200000` (địa chỉ cũ của Rockchip).
**Giải pháp:** Dùng lệnh `sed` để can thiệp trực tiếp vào file cấu hình cấu trúc `fit/u-boot.its` sau khi nó được sinh ra, ép nó đổi thành `0x40800000` để khớp với `CONFIG_TEXT_BASE`.

### c. Vấn đề 3: Sửa lỗi Tràn bộ nhớ (Synchronous Abort) trong SPL
Đây là lỗi khó nhất. Khi chúng ta tự chạy lệnh `mkimage`, nếu không cẩn thận, toàn bộ dữ liệu nhị phân (U-Boot, ATF, TEE) sẽ bị nhúng thẳng vào trong cấu trúc file FDT. Khi Rockchip SPL cố gắng nạp file FIT này, cây FDT quá lớn sẽ làm cạn kiệt bộ đệm `malloc pool` siêu nhỏ của nó, gây ra lỗi `esr 0x96000004`.
**Giải pháp:** Phải chạy lệnh `mkimage` kèm cờ ngoại tuyến `-E -p 0x1000`. Cờ này sẽ lưu cấu trúc FDT rất nhỏ gọn ở đầu, còn dữ liệu nhị phân dung lượng lớn sẽ được tống ra ngoài (external data) theo các offset, giúp SPL không bị tràn RAM khi parse cây cấu trúc.

### d. Vấn đề 4: Format A/B Slot
BootROM và SPL của Rockchip yêu cầu file `uboot.img` phải có cấu trúc nhân đôi để dự phòng (Slot A / Slot B).
**Giải pháp:** Dùng `truncate` căn lề file thành các block 2MB (2048K) và `cat` nối chúng lại với nhau để sinh ra image hoàn chỉnh 4MB.

## Kết luận

Thành công của việc Bring-up phụ thuộc vào việc thấu hiểu sâu sắc quy trình khởi động 4 bước: **BootROM -> Rockchip TPL/SPL -> ATF (BL31) -> Upstream U-Boot (BL33)**.
Bằng cách thao tác chính xác với các offset bộ nhớ, xử lý FDT, và đồng bộ tốc độ Baudrate, Das U-Boot đã hoàn toàn làm chủ được bo mạch Radxa Rock 4D.

## 4. Hướng dẫn Build và Flash

Để tự build lại toàn bộ từ mã nguồn và nạp xuống bo mạch, bạn hãy chạy lần lượt các bước sau:

### Bước 1: Build mã nguồn U-Boot
```bash
cd /home/quangnm/workdir/raxda/u-boot
export CROSS_COMPILE=aarch64-linux-gnu-

# Thiết lập cấu hình mặc định cho mạch
make evb_rk3576_qnm_defconfig

# Biên dịch mã nguồn
make -j$(nproc)
```

### Bước 2: Đóng gói FIT Image và SPL
Chạy script đóng gói (lưu ý chạy từ thư mục gốc của U-Boot):
```bash
./qnm_tools/pack_rockchip.sh
```
Script sẽ tự động mượn công cụ của Rockchip SDK, thiết lập cờ `-E`, cấu hình Load Address `0x40800000`, và tạo ra 2 file:
- `idblock.bin`
- `uboot.img`

### Bước 3: Nạp (Flash) xuống thẻ nhớ hoặc eMMC
Chạy lệnh `dd` để ghi trực tiếp các file nhị phân vào đúng sector yêu cầu của BootROM Rockchip:
```bash
# Nạp idblock.bin (TPL + SPL) vào Sector 64
sudo dd if=idblock.bin of=/dev/sda seek=64 bs=512 conv=notrunc

# Nạp uboot.img (U-Boot, ATF, OP-TEE) vào Sector 16384 (8MB)
sudo dd if=uboot.img of=/dev/sda seek=16384 bs=512 conv=notrunc

# Đồng bộ thẻ nhớ
sync
```
*(Lưu ý: Thay `/dev/sda` bằng đường dẫn ổ đĩa chính xác của thẻ nhớ hoặc eMMC trên máy tính của bạn).*
