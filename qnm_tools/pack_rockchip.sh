#!/bin/bash
set -e

# Khai báo đường dẫn
UBOOT_DIR="/home/quangnm/workdir/raxda/u-boot"
SDK_UBOOT_DIR="/home/quangnm/workdir/buildroot/u-boot"
RKBIN_DIR="/home/quangnm/workdir/buildroot/rkbin"

echo "=== Đóng gói idblock.bin (TPL + SPL) ==="
TPL_BIN="${RKBIN_DIR}/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin"
SPL_BIN="${UBOOT_DIR}/spl/u-boot-spl.bin"

if [ ! -f "$TPL_BIN" ] || [ ! -f "$SPL_BIN" ]; then
    echo "Lỗi: Không tìm thấy TPL hoặc SPL!"
    exit 1
fi

${UBOOT_DIR}/tools/mkimage -n rk3576 -T rksd -d ${TPL_BIN}:${SPL_BIN} idblock.bin
echo "Đã tạo thành công idblock.bin"

echo "=== Đóng gói uboot.img (FIT Image chứa ATF, TEE, U-Boot) ==="
# Đánh lừa Rockchip fit.sh bằng cách cung cấp u-boot.bin (chứa sẵn dtb bên trong)
cp ${UBOOT_DIR}/u-boot.bin ${SDK_UBOOT_DIR}/u-boot-nodtb.bin
cp ${UBOOT_DIR}/u-boot.dtb ${SDK_UBOOT_DIR}/

cd ${SDK_UBOOT_DIR}
# Chạy fit.sh để nó tự động bóc tách ATF, TEE và sinh ra file fit/u-boot.its mẫu
./scripts/fit.sh --ini-trust ../rkbin/RKTRUST/RK3576TRUST.ini --chip RK3576

# Lấy lại file u-boot.its từ thư mục fit ra ngoài thư mục gốc để đường dẫn file bin được chính xác
cp fit/u-boot.its ./

# Tuy nhiên fit.sh mặc định ép uboot chạy ở 0x40200000, chúng ta cần nó chạy ở 0x40800000 (đúng chuẩn Das U-Boot)
sed -i 's/0x40200000/0x40800000/g' u-boot.its

# Đóng gói lại FIT image bằng file cấu hình đã sửa, BẮT BUỘC phải dùng -E để tách data (tránh lỗi malloc SPL)
./tools/mkimage -f u-boot.its -E -p 0x1000 u-boot.itb

# Tạo uboot.img bằng cách nhân đôi file itb và căn lề 2MB (như Rockchip SPL yêu cầu cho A/B slot)
rm -f uboot.img
cp u-boot.itb uboot.img
truncate -s %2048K uboot.img
cat u-boot.itb >> uboot.img
truncate -s %2048K uboot.img

# Mang uboot.img về lại thư mục U-Boot của mình
cp uboot.img ${UBOOT_DIR}/
cd ${UBOOT_DIR}

echo "======================================"
echo "HOÀN TẤT!"
echo "Các image để Flash:"
echo "1. idblock.bin (Nạp vào Sector 64)"
echo "2. uboot.img (Nạp vào phân vùng uboot)"
echo "======================================"
