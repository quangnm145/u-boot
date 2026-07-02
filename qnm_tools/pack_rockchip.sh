#!/bin/bash
set -e

# Chuyển đến thư mục chứa script (qnm_tools)
cd "$(dirname "$0")"

# Khai báo đường dẫn tương đối so với qnm_tools
UBOOT_DIR=".."
TOOLS_DIR="."
BLOBS_DIR="rkbin_blobs"

echo "=== Đóng gói idblock.bin bằng boot_merger ==="
SPL_BIN="${UBOOT_DIR}/spl/u-boot-spl.bin"

if [ ! -f "$SPL_BIN" ]; then
    echo "Lỗi: Không tìm thấy SPL!"
    exit 1
fi

# Cực kỳ quan trọng: Copy SPL vào chung thư mục để tránh lỗi đường dẫn tương đối của boot_merger
cp "$SPL_BIN" "${BLOBS_DIR}/u-boot-spl.bin"

./boot_merger RK3576_UBOOT.ini
echo "Đã tạo thành công idblock.bin chuẩn Loader RK3576"

echo "=== Cập nhật BL31 từ thư mục rkbin mới ==="
BL31_ELF="../../rkbin/bin/rk35/rk3576_bl31_v1.24.elf"
aarch64-linux-gnu-objcopy -O binary -j .text_pmusram $BL31_ELF rkbin_blobs/bl31_0x3fe70000.bin
aarch64-linux-gnu-objcopy -O binary -j .ddr_m0_bin $BL31_ELF rkbin_blobs/bl31_0x400f0000.bin
aarch64-linux-gnu-objcopy -O binary -j ro -j .sram.text -j .data -j .sram.data -j stacks -j .bss -j xlat_table -j coherent_ram $BL31_ELF rkbin_blobs/bl31_0x40060000.bin

echo "=== Đóng gói uboot.img (FIT Image chứa ATF, TEE, U-Boot) ==="

# Đóng gói lại FIT image bằng template u-boot.its của riêng chúng ta
# Cờ -E tách data ra ngoài cấu trúc FIT, ngăn lỗi tràn malloc của SPL
${UBOOT_DIR}/tools/mkimage -f u-boot.its -E -p 0x1000 u-boot.itb

# Tạo uboot.img bằng cách nhân đôi file itb và căn lề 2MB (như Rockchip SPL yêu cầu cho A/B slot)
rm -f ${UBOOT_DIR}/uboot.img
cp u-boot.itb ${UBOOT_DIR}/uboot.img
truncate -s %2048K ${UBOOT_DIR}/uboot.img
cat u-boot.itb >> ${UBOOT_DIR}/uboot.img
truncate -s %2048K ${UBOOT_DIR}/uboot.img

# Dọn dẹp file tạm
rm u-boot.itb

echo "======================================"
echo "HOÀN TẤT ĐÓNG GÓI ĐỘC LẬP!"
echo "Các image để Flash (nằm ở thư mục gốc U-Boot):"
echo "1. idblock.bin (Nạp vào Sector 64)"
echo "2. uboot.img (Nạp vào phân vùng uboot)"
echo "======================================"
