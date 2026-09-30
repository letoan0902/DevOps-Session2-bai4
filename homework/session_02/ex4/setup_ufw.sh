#!/usr/bin/env bash
# setup_ufw.sh - Cấu hình UFW cho Bài 4 (Session 02): lọc gói tin đi vào.
# Script idempotent: chạy nhiều lần cho cùng một kết quả, không xóa rule hiện có.
# Cách dùng: sudo bash setup_ufw.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Cần chạy với quyền root (sudo bash $0)" >&2
  exit 1
fi

# 1. Cài ufw nếu chưa có (Ubuntu thường cài sẵn).
command -v ufw >/dev/null 2>&1 || { apt-get update -y && apt-get install -y ufw; }

# 2. Chính sách mặc định: chặn mọi kết nối đi vào, cho phép mọi kết nối đi ra.
ufw default deny incoming
ufw default allow outgoing

# 3. QUAN TRỌNG: phải allow SSH (22/tcp) TRƯỚC khi enable,
#    nếu không phiên SSH đang dùng sẽ bị cắt và mất quyền truy cập máy chủ.
ufw allow 22/tcp

# 4. Mở cổng HTTP (80/tcp) cho web server.
ufw allow 80/tcp

# 5. Bật UFW. --force bỏ qua câu hỏi xác nhận (cần khi chạy không tương tác).
#    Nếu UFW đã bật thì lệnh này không gây thay đổi nào khác.
ufw --force enable

# 6. Hiển thị kết quả để kiểm tra.
ufw status verbose
ufw status numbered
