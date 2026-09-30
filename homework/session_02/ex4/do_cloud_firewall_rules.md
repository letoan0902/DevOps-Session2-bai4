# Bảng rule DigitalOcean Cloud Firewall (Lớp 2)

Tài liệu này mô tả cấu hình Cloud Firewall cần tạo trên DigitalOcean Console
cho bài 4. Máy chủ thực tế của bài làm không nằm trên DigitalOcean nên bảng này
là cấu hình tham chiếu, chưa được áp dụng thực tế.

- Tên firewall đề xuất: `fw-web-ssh-http`
- Đối tượng áp dụng (Apply to Droplets): Droplet chạy web server (ví dụ `ptit-web-01`)

## Inbound Rules (chiều đi vào)

| Type | Protocol | Port Range | Sources | Mục đích |
|------|----------|------------|---------|----------|
| SSH  | TCP | 22 | All IPv4, All IPv6 (hoặc chỉ IP cá nhân, ví dụ `203.0.113.10/32`) | Quản trị từ xa |
| HTTP | TCP | 80 | All IPv4, All IPv6 | Truy cập website |

Mọi cổng/giao thức khác không có rule Inbound nên bị chặn mặc định
(Cloud Firewall là allow-list: không khớp rule nào thì drop).

## Outbound Rules (chiều đi ra)

Giữ mặc định của DigitalOcean (cho phép mọi đích):

| Type | Protocol | Port Range | Destinations |
|------|----------|------------|--------------|
| ICMP | ICMP | - | All IPv4, All IPv6 |
| All TCP | TCP | All ports | All IPv4, All IPv6 |
| All UDP | UDP | All ports | All IPv4, All IPv6 |

Outbound cần mở để Droplet cập nhật gói (`apt`), phân giải DNS và gọi API bên ngoài.

## Đối chiếu với UFW (Lớp 1)

| Cổng | Cloud Firewall (Lớp 2) | UFW (Lớp 1) |
|------|------------------------|-------------|
| 22/tcp | Allow | Allow |
| 80/tcp | Allow | Allow |
| Còn lại | Drop | Deny |

Hai lớp cần nhất quán. Khi cần mở thêm cổng (ví dụ 443/tcp) phải thêm ở cả hai lớp,
nếu không gói tin vẫn bị chặn ở lớp còn lại.
