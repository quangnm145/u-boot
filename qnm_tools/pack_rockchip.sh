#!/bin/bash
set -e

# Chuyển đến thư mục chứa script (qnm_tools)
cd "$(dirname "$0")"

# Khai báo đường dẫn tương đối so với qnm_tools
UBOOT_DIR=".."
TOOLS_DIR="."
BLOBS_DIR="rkbin_blobs"

echo "=== Đóng gói idblock.bin (TPL + SPL) ==="
TPL_BIN="${BLOBS_DIR}/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin"
SPL_BIN="${UBOOT_DIR}/spl/u-boot-spl.bin"

if [ ! -f "$TPL_BIN" ] || [ ! -f "$SPL_BIN" ]; then
    echo "Lỗi: Không tìm thấy TPL hoặc SPL!"
    exit 1
fi

${UBOOT_DIR}/tools/mkimage -n rk3576 -T rksd -d ${TPL_BIN}:${SPL_BIN} ${UBOOT_DIR}/idblock.bin
echo "Đã tạo thành công idblock.bin"

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
