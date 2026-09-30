# Bài 4: Cấu hình tường lửa bảo vệ máy chủ (UFW và Cloud Firewall Integration)

## 1. Mục tiêu

- Thiết lập UFW trên Ubuntu để lọc gói tin đi vào máy chủ (Lớp 1).
- Kết hợp Cloud Firewall ở tầng hạ tầng của nhà cung cấp (Lớp 2) theo mô hình phòng thủ nhiều lớp.
- Kiểm chứng: SSH và HTTP 80 không bị tường lửa chặn, các cổng khác bị chặn (timeout).

Môi trường thực hiện:

| Thông tin | Giá trị |
|-----------|---------|
| Máy chủ | Ubuntu Server 24.04.3 LTS, IP `103.116.104.228` |
| Hệ điều hành | Ubuntu 24.04.3 LTS |
| Máy kiểm tra | Máy cá nhân Windows 11 (curl, ssh, ping, PowerShell) |

Các file trong thư mục này:

| File | Nội dung |
|------|----------|
| `README.md` | Báo cáo (file này) |
| `ufw_status.txt` | Output thật của `ufw status verbose` / `numbered` / thường |
| `setup_ufw.sh` | Script bash idempotent cấu hình UFW |
| `do_cloud_firewall_rules.md` | Bảng rule Inbound/Outbound cho DigitalOcean Cloud Firewall |

## 2. Mô hình hai lớp

```text
Internet
   |
   v
[ Lớp 2: Cloud Firewall (tầng hạ tầng, ngoài Droplet) ]  chỉ cho 22/tcp, 80/tcp
   |
   v
[ Máy chủ Ubuntu ]
   |
   v
[ Lớp 1: UFW (iptables/nftables trong hệ điều hành) ]    default deny incoming, cho 22/tcp, 80/tcp
   |
   v
Dịch vụ (sshd :22, nginx :80)
```

Lý do dùng hai lớp (defense in depth):

- Cloud Firewall lọc gói tin ở biên hạ tầng, trước khi chúng tới máy chủ. Gói bị chặn không tiêu tốn CPU, băng thông xử lý hay bảng conntrack của máy chủ.
- Một cấu hình Cloud Firewall có thể gán cho nhiều máy chủ (theo tên hoặc tag), quản lý tập trung.
- UFW là lớp dự phòng: nếu Cloud Firewall cấu hình sai hoặc bị gỡ, máy chủ vẫn có chính sách chặn riêng. Ngược lại, nếu UFW vô tình bị tắt, Cloud Firewall vẫn chặn ở biên.
- Hai lớp độc lập nên một lỗi cấu hình đơn lẻ không làm lộ dịch vụ ra Internet.

## 3. Lớp 1: UFW

### 3.1. Hiện trạng trước khi cấu hình

Máy chủ đã bật UFW từ trước với một rule duy nhất cho SSH (profile OpenSSH):

```text
$ sudo ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp (OpenSSH)           ALLOW IN    Anywhere                  
22/tcp (OpenSSH (v6))      ALLOW IN    Anywhere (v6)             
```

Các cổng đang lắng nghe (`ss -tlnp`, cột Local Address và tiến trình):

```text
0.0.0.0:80         nginx
[::]:80            nginx
0.0.0.0:22         sshd
[::]:22            sshd
127.0.0.53%lo:53   systemd-resolved
```

Nhận xét: chỉ `sshd` (22) và `nginx` (80, site ptit-web của bài 3) lắng nghe trên mọi địa chỉ. `systemd-resolved` chỉ bind loopback nên không thể truy cập từ Internet bất kể cấu hình firewall. Đây chính là hai cổng cần mở; mọi cổng khác phải bị chặn.

### 3.2. Các lệnh cấu hình

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw enable
```

| Lệnh | Giải thích |
|------|-----------|
| `ufw default deny incoming` | Chính sách mặc định: chặn mọi kết nối đi vào chưa có rule cho phép (nguyên tắc từ chối mặc định). |
| `ufw default allow outgoing` | Cho phép mọi kết nối đi ra để máy chủ cập nhật gói, phân giải DNS, gọi API. |
| `ufw allow 22/tcp` | Mở SSH để quản trị từ xa. Phải chạy trước `enable`. |
| `ufw allow 80/tcp` | Mở HTTP cho web server. |
| `ufw enable` | Bật UFW và tự khởi động cùng hệ thống. Khi chạy qua SSH không tương tác dùng `ufw --force enable` để bỏ qua câu hỏi xác nhận. |

Các lệnh được gom trong script idempotent [setup_ufw.sh](setup_ufw.sh). UFW bỏ qua rule trùng nên chạy lại nhiều lần không sinh rule lặp. Do máy chủ đã có sẵn UFW hoạt động, các lệnh được chạy trực tiếp (không `reset`, không `disable`, không xóa rule cũ) và phiên SSH không bị gián đoạn.

Output thật khi chạy trên máy chủ (qua SSH, dùng `--force enable`):

```text
Default incoming policy changed to 'deny'
(be sure to update your rules accordingly)
Default outgoing policy changed to 'allow'
(be sure to update your rules accordingly)
Rule added
Rule added (v6)
Rule added
Rule added (v6)
Firewall is active and enabled on system startup
```

Dòng "policy changed" là thông báo UFW in ra mỗi khi chạy lệnh `default`; chính sách vốn đã là deny/allow từ trước nên không có thay đổi thực chất (`ufw status verbose` trước và sau đều ghi `deny (incoming), allow (outgoing)`).

### 3.3. Kết quả sau khi cấu hình

```text
$ sudo ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp (OpenSSH)           ALLOW IN    Anywhere                  
22/tcp                     ALLOW IN    Anywhere                  
80/tcp                     ALLOW IN    Anywhere                  
22/tcp (OpenSSH (v6))      ALLOW IN    Anywhere (v6)             
22/tcp (v6)                ALLOW IN    Anywhere (v6)             
80/tcp (v6)                ALLOW IN    Anywhere (v6)             
```

```text
$ sudo ufw status numbered
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] OpenSSH                    ALLOW IN    Anywhere                  
[ 2] 22/tcp                     ALLOW IN    Anywhere                  
[ 3] 80/tcp                     ALLOW IN    Anywhere                  
[ 4] OpenSSH (v6)               ALLOW IN    Anywhere (v6)             
[ 5] 22/tcp (v6)                ALLOW IN    Anywhere (v6)             
[ 6] 80/tcp (v6)                ALLOW IN    Anywhere (v6)             
```

```text
$ sudo ufw status
Status: active

To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere                  
22/tcp                     ALLOW       Anywhere                  
80/tcp                     ALLOW       Anywhere                  
OpenSSH (v6)               ALLOW       Anywhere (v6)             
22/tcp (v6)                ALLOW       Anywhere (v6)             
80/tcp (v6)                ALLOW       Anywhere (v6)             
```

Toàn bộ output (kèm thời điểm chụp) lưu ở [ufw_status.txt](ufw_status.txt). Trạng thái `active`, mặc định `deny (incoming)` / `allow (outgoing)`, và 22/tcp, 80/tcp đều có rule cho cả IPv4 lẫn IPv6.

Ghi chú: rule `OpenSSH` (có từ trước, là profile ứng dụng trỏ tới 22/tcp) và rule `22/tcp` mới thêm có tác dụng trùng nhau. Rule cũ được giữ nguyên để không đụng tới cấu hình đang chạy; trên máy mới chỉ cần `22/tcp` là đủ.

## 4. Lớp 2: DigitalOcean Cloud Firewall

Ghi chú quan trọng về ảnh chụp: máy chủ dùng trong bài này (`103.116.104.228`) không nằm trên DigitalOcean và người thực hiện không có tài khoản DigitalOcean, nên không thể tạo Cloud Firewall thật và không có ảnh chụp DO Console. Ảnh chụp được thay bằng hướng dẫn từng bước và bảng rule bên dưới; mục này chưa được áp dụng thực tế. Với nhà cung cấp VPS hiện tại, tương đương là tính năng firewall ở tầng hạ tầng (Security Group / Firewall trong trang quản trị) nếu nhà cung cấp có hỗ trợ; nguyên tắc rule giữ nguyên như bảng dưới.

### 4.1. Các bước trên DigitalOcean Console

1. Đăng nhập DigitalOcean Control Panel.
2. Menu bên trái chọn Networking, chuyển sang tab Firewalls.
3. Bấm Create Firewall.
4. Mục Name: nhập tên, ví dụ `fw-web-ssh-http`.
5. Mục Inbound Rules, xóa các rule mặc định không cần thiết và khai báo:
   - Type `SSH`, Protocol TCP, Port 22, Sources: All IPv4 và All IPv6 (hoặc, an toàn hơn, chỉ nhập địa chỉ IP cá nhân dạng `x.x.x.x/32`).
   - Type `HTTP`, Protocol TCP, Port 80, Sources: All IPv4 và All IPv6.
6. Mục Outbound Rules: giữ mặc định (ICMP, All TCP, All UDP tới All IPv4/IPv6).
7. Mục Apply to Droplets: gõ tên hoặc tag của Droplet cần bảo vệ rồi chọn Droplet đó.
8. Bấm Create Firewall. Firewall có hiệu lực gần như ngay lập tức, không cần khởi động lại Droplet.

### 4.2. Bảng rule

Inbound Rules:

| Type | Protocol | Port | Sources |
|------|----------|------|---------|
| SSH | TCP | 22 | All IPv4, All IPv6 (hoặc IP cá nhân `/32`) |
| HTTP | TCP | 80 | All IPv4, All IPv6 |

Outbound Rules (mặc định):

| Type | Protocol | Port | Destinations |
|------|----------|------|--------------|
| ICMP | ICMP | - | All IPv4, All IPv6 |
| All TCP | TCP | All | All IPv4, All IPv6 |
| All UDP | UDP | All | All IPv4, All IPv6 |

Chi tiết và bảng đối chiếu với UFW xem [do_cloud_firewall_rules.md](do_cloud_firewall_rules.md).

Hệ quả khi áp dụng: Cloud Firewall là allow-list, nên ICMP echo (ping) từ ngoài cũng bị chặn vì Inbound không có rule ICMP. Nếu muốn cho ping thì thêm rule Inbound ICMP.

## 5. Kiểm tra

Thực hiện từ máy cá nhân Windows tới `103.116.104.228`. Hiện chỉ Lớp 1 (UFW) được áp dụng thật, nên kết quả dưới đây phản ánh UFW.

### 5.1. SSH (22/tcp): thành công

Mở kết nối SSH mới sau khi bật cấu hình:

```text
$ ssh -o BatchMode=yes root@103.116.104.228 'echo SSH_OK; hostname'
SSH_OK
halo
```

```text
PS> Test-NetConnection -ComputerName 103.116.104.228 -Port 22
ComputerName    RemotePort TcpTestSucceeded
------------    ---------- ----------------
103.116.104.228         22             True
```

### 5.2. HTTP (80/tcp): thành công

Site tĩnh `ptit-web` (bài 3) lắng nghe `0.0.0.0:80`, nên sau khi UFW mở 80/tcp, máy cá nhân truy cập được bằng IP:

```text
$ curl -sI -m 10 http://103.116.104.228/
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 01 Oct 2026 03:12:41 GMT
Content-Type: text/html
Content-Length: 934
Last-Modified: Thu, 01 Oct 2026 02:58:17 GMT
Connection: keep-alive
ETag: "68dc9a29-3a6"
Accept-Ranges: bytes
```

```text
$ curl -s -m 10 -o /dev/null -w "%{http_code}
" http://103.116.104.228/
200
```

Mở trình duyệt tới `http://103.116.104.228` hiển thị trang HTML với dòng chữ "Welcome to PTIT DevOps Course - Session 02". Trên máy chủ, nhật ký truy cập của site ghi nhận request đi qua:

```text
devops@halo:~$ sudo tail -n 2 /var/log/nginx/ptit-web.access.log
14.191.72.35 - - [01/Oct/2026:10:12:41 +0700] "HEAD / HTTP/1.1" 200 0 "-" "curl/8.9.1"
14.191.72.35 - - [01/Oct/2026:10:12:44 +0700] "GET / HTTP/1.1" 200 934 "-" "curl/8.9.1"
```

Cần phân biệt hai kiểu kết quả khi kiểm tra một cổng từ ngoài:

- Có phản hồi HTTP (như trên) hoặc `Connection refused`: gói SYN đã đi qua UFW tới tầng TCP của hệ điều hành. `refused` xảy ra khi rule đã mở nhưng chưa có tiến trình lắng nghe công khai trên cổng đó.
- `Connection timed out`: gói bị firewall DROP im lặng (xem mục 5.3).

### 5.3. Cổng không mở: bị chặn (timeout)

```text
$ curl -s -m 5 http://103.116.104.228:8080/ ; echo "exit=$?"
exit=28

$ curl -s -m 5 http://103.116.104.228:3306/ ; echo "exit=$?"
exit=28
```

```text
$ curl -sv -m 5 http://103.116.104.228:8080/
*   Trying 103.116.104.228:8080...
* Connection timed out after 5012 milliseconds
```

```text
PS> Test-NetConnection -ComputerName 103.116.104.228 -Port 8080
ComputerName    RemotePort TcpTestSucceeded
------------    ---------- ----------------
103.116.104.228       8080             False

PS> Test-NetConnection -ComputerName 103.116.104.228 -Port 3306
ComputerName    RemotePort TcpTestSucceeded
------------    ---------- ----------------
103.116.104.228       3306             False
```

Exit code 28 của curl là timeout: gói SYN bị UFW DROP im lặng (chính sách `deny incoming`), khác hẳn với `refused` ở cổng 80. Cổng 3306 (MySQL) không có rule cho phép nên dù có dịch vụ chạy phía sau, kẻ tấn công cũng không quét thấy, đúng như mong muốn. Máy cá nhân không cài `nmap` nên dùng `curl` và `Test-NetConnection` thay thế.

### 5.4. Ping (ICMP)

```text
C:\> ping -n 3 103.116.104.228
Pinging 103.116.104.228 with 32 bytes of data:
Reply from 103.116.104.228: bytes=32 time=29ms TTL=49
Reply from 103.116.104.228: bytes=32 time=29ms TTL=49
Reply from 103.116.104.228: bytes=32 time=29ms TTL=49

Ping statistics for 103.116.104.228:
    Packets: Sent = 3, Received = 3, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 29ms, Maximum = 29ms, Average = 29ms
```

Ping vẫn thành công. Nguyên nhân: UFW mặc định cho phép ICMP echo-request trong file `/etc/ufw/before.rules` (được xử lý trước các rule người dùng), nên `default deny incoming` không chặn ping:

```text
$ grep -n "icmp" /etc/ufw/before.rules
34:-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT
35:-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT
36:-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT
37:-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT
```

Cách chặn ping nếu muốn (không thực hiện trong bài này): sửa `/etc/ufw/before.rules`, đổi `ACCEPT` thành `DROP` cho dòng `--icmp-type echo-request` trong chain `ufw-before-input`, rồi `sudo ufw reload`. Hoặc chặn ở Lớp 2: không khai báo rule Inbound ICMP trong Cloud Firewall (mặc định đã chặn ping). Đề bài yêu cầu "ping hoặc quét cổng khác không mở phải bị chặn/timeout"; tiêu chí quét cổng khác (8080, 3000) đã đạt.

## 6. Lưu ý an toàn khi bật UFW qua SSH

- Luôn `ufw allow 22/tcp` (hoặc `ufw allow OpenSSH`) trước khi `ufw enable`. Nếu bật UFW với `default deny incoming` mà chưa mở SSH, phiên hiện tại có thể bị cắt và không thể đăng nhập lại (phải dùng console của nhà cung cấp để sửa).
- Nếu SSH chạy ở cổng khác 22 thì phải mở đúng cổng đó.
- Sau mỗi thay đổi, mở một kết nối SSH mới (giữ nguyên phiên cũ) để xác nhận vẫn vào được trước khi đóng phiên cũ. Bài này đã kiểm tra bằng `ssh ... 'echo SSH_OK; hostname'`.
- Khi chạy không tương tác dùng `ufw --force enable`.
- Không dùng `ufw reset` / `ufw disable` trên máy chủ đang phục vụ dịch vụ, tránh mở hoặc đóng ngoài ý muốn.
- Docker ghi trực tiếp vào iptables nên có thể bỏ qua rule UFW với cổng được publish dạng `0.0.0.0`. Nên bind cổng vào `127.0.0.1` hoặc dùng thêm Cloud Firewall để chặn ở biên.
- Nếu Cloud Firewall và UFW lệch nhau (một bên mở, một bên đóng) thì cổng vẫn bị chặn; cần mở cả hai lớp khi thêm dịch vụ mới.

## 7. Kết luận

- Lớp 1 (UFW) đã được cấu hình và kiểm chứng trên máy chủ thật: active, `deny (incoming)`, `allow (outgoing)`, mở 22/tcp và 80/tcp (IPv4 và IPv6).
- SSH kết nối mới thành công; các cổng không mở (8080, 3306) bị chặn với timeout (curl exit 28).
- Cổng 80 đã được UFW cho qua: máy cá nhân nhận `HTTP/1.1 200 OK` từ site ptit-web, đúng yêu cầu chỉ mở SSH và HTTP.
- Ping vẫn trả lời do UFW cho phép ICMP echo mặc định; đã trình bày cách chặn.
- Lớp 2 (DO Cloud Firewall) không thực hiện thực tế do máy chủ không nằm trên DigitalOcean; thay bằng hướng dẫn chi tiết và bảng rule. Khi áp dụng, hai lớp cùng cho phép đúng 22/tcp và 80/tcp sẽ tạo nên cơ chế phòng thủ nhiều lớp.
