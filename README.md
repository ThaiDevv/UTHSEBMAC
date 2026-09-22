# UTH SEB macOS (v1.0.4) - Mã Nguồn Tái Cấu Trúc & Phân Tích Kỹ Thuật

Dự án này là mã nguồn hoàn chỉnh được dịch ngược (reverse-engineered / decompiled) và tái cấu trúc 100% từ gói cài đặt `UTHSEB-Setup-1.0.4.pkg` của Trường Đại học Giao thông vận tải TP.HCM (UTH).

---

## 1. Cấu trúc Thư mục Dự án

```
UTHSEBMac-1.0.4-Source/
├── Package.swift                    # File cấu hình Swift Package Manager (SPM)
├── Info.plist                       # Cấu hình Bundle, URL scheme (uthseb://), quyền ứng dụng
├── Resources/
│   ├── bgcourses.jpg                # Hình nền trang Launcher (UTH branding)
│   └── launcher.html                # Giao diện HTML của Launcher khởi động bài thi
└── Sources/
    ├── main.swift                   # Điểm khởi chạy ứng dụng (NSApplication)
    ├── AppDelegate.swift            # Điều khiển vòng đời, giám sát tiến trình, phím tắt, giao diện kiosk
    ├── DomainPolicy.swift           # Kiểm tra whitelist tên miền (*.ut.edu.vn, localhost), URL scheme
    ├── RequestAuthenticator.swift   # Thuật toán ký Request Header (SHA-256 + Secret Key)
    ├── VirtualMachineDetector.swift # Bộ phát hiện môi trường máy ảo (VMware, VirtualBox, Parallels, QEMU...)
    ├── VirtualMachinePolicy.swift   # Danh sách chữ ký và quy tắc nhận diện máy ảo
    ├── KioskWindow.swift            # Cửa sổ toàn màn hình Kiosk Window (chặn thoát, bắt phím Escape)
    ├── LockedWebView.swift          # WKWebView tùy biến (chặn chuột phải, chuột giữa, chặn Inspect Element)
    └── InputPassthroughView.swift   # Lớp phủ trong suốt cho phép click xuyên qua
```

---

## 2. Phân Tích Kiến Trúc & Cơ Chế Bảo Mật Bản 1.0.4

### 2.1. Xác thực Request (Request Authentication)
- **Cơ chế**: Mỗi yêu cầu duyệt web hợp lệ đến máy chủ thi (`*.ut.edu.vn`) đều được gắn thêm HTTP Header:
  ```http
  X-UTHSEB-Request-Hash: <SHA256_HEX>
  ```
- **Khóa bí mật (Secret Key)**: Được lưu trữ dạng mảng 32 bytes XOR để chống đọc chuỗi tĩnh:
  - Khóa sau khi giải mã XOR: `ATDGMFUeicurzkek5234=5575;645755`
- **Công thức băm**:
  ```
  Signature = SHA256(URL.absoluteString + SecretKey).lowercased_hex
  ```
- **Luồng hoạt động**:
  1. Khi người dùng bấm liên kết, `WKNavigationDelegate` (`decidePolicyFor`) chặn lại.
  2. Kiểm tra xem request đã có header `X-UTHSEB-Request-Hash` hợp lệ chưa.
  3. Nếu chưa có, tạo bản sao request mới, tính hash, gắn header `X-UTHSEB-Request-Hash` rồi gọi `webView.load(signedRequest)`.
  4. Máy chủ UTH xác thực hash này để đảm bảo sinh viên đang thi bằng đúng trình duyệt UTH SEB.

### 2.2. Kiểm soát Tên miền & URL Scheme
- **Tên miền cho phép**:
  - `ut.edu.vn` và tất cả subdomain `*.ut.edu.vn` (ví dụ: `courses.ut.edu.vn`, `thnn.ut.edu.vn`, `portal.ut.edu.vn`)
  - `localhost`, `127.0.0.1`, `::1`
- **URL Scheme**:
  - Đăng ký scheme `uthseb://` trong `Info.plist`.
  - Hỗ trợ tham số: `uthseb://exam?url=https%3A%2F%2Fcourses.ut.edu.vn%2F...` để mở trực tiếp từ trình duyệt bên ngoài vào chế độ thi an toàn.

### 2.3. Phát hiện & Chặn Máy ảo (Anti-VM)
1. **Kiểm tra phần cứng & CPU**:
   - Gọi `/usr/sbin/system_profiler SPHardwareDataType`
   - Gọi `/usr/sbin/sysctl machdep.cpu.brand_string`
   - Đối chiếu với từ khóa: `vmware`, `virtualbox`, `innotek`, `xen`, `qemu`, `kvm`, `bochs`, `parallels`, `bhyve`, `virtual machine`, `virtualmac`, `apple virtualization`, `microsoft corporation`.
2. **Kiểm tra thiết bị lưu trữ**:
   - Gọi `/usr/sbin/system_profiler SPStorageDataType`
   - Đối chiếu với từ khóa ổ đĩa ảo: `vmware`, `vbox`, `virtualbox`, `virtual`, `qemu`, `kvm`, `xen`, `parallels`.
3. **Kiểm tra tiến trình Guest Tools**:
   - Quét qua `/bin/ps -axo comm`
   - Tìm kiếm: `vmtools`, `vmware tools`, `vboxservice`, `vboxtray`, `virtualbox guest`, `qemu-ga`, `qemu guest`, `xenservice`, `xen guest`, `prl_tools`, `parallels tools`, `prltoolsd`.
- Nếu phát hiện bất kỳ dấu hiệu nào, ứng dụng hiển thị thông báo cảnh báo và lập tức thoát (`NSApp.terminate`).

### 2.4. Khóa Chế độ Kiosk & Chống Gian Lận (Anti-Cheat)
- **Toàn màn hình Kiosk**:
  - Cửa sổ mức `.screenSaver` (đè lên Menu Bar và Dock).
  - Tắt chuột phải và Inspect Element (`LockedWebView`).
  - Chặn mở cửa sổ mới (`createWebViewWith... -> nil`).
  - Dữ liệu duyệt web riêng tư (`WKWebsiteDataStore.nonPersistent()`).
  - Thêm User-Agent nhận diện: `(Official Build; School-ID: UTH-2026; SecureMode)`.
- **Phát hiện đa màn hình (Multi-Monitor Detection)**:
  - `Timer` chạy định kỳ mỗi 2 giây.
  - Nếu `NSScreen.screens.count >= 2`: Báo lỗi gian lận và tự hủy phiên thi ngay lập tức.
- **Giám sát & Diệt tiến trình cấm (Process Enforcement)**:
  - Lắng nghe sự kiện ứng dụng mới mở qua KVO `\NSWorkspace.runningApplications`.
  - Tự động gọi `app.forceTerminate()` nếu tên tiến trình chứa:
    - Trình ghi màn hình: `obs`, `camtasia`, `screen recorder`, `quicktime player`...
    - Điều khiển từ xa: `teamviewer`, `ultraviewer`, `anydesk`, `rustdesk`, `supremo`, `nomachine`, `parsec`, `screenconnect`, `connectwise`, `splashtop`, `remote desktop`, `vnc`...
    - Gọi thoại / liên lạc: `zoom`, `skype`, `discord`, `microsoft teams`, `teams`, `webex`, `gotomeeting`, `bluejeans`, `slack`, `telegram`, `whatsapp`...
    - AI & Trợ lý: `copilot`, `microsoft copilot`...
    - Trình duyệt khác: `google chrome`, `chrome`, `firefox`, `microsoft edge`, `brave browser`, `brave`, `opera`, `vivaldi`, `chromium`, `tor browser`, `waterfox`, `librewolf`, `coc coc`...
- **Chặn tổ hợp phím hệ thống**:
  - Chặn `Cmd + Q`, `Cmd + W`, `Cmd + M`, `Cmd + H`, `Cmd + R`, `Cmd + L`, `Cmd + N`, `Cmd + T`, `Cmd + ,`, `Cmd + \``.
  - Chặn `Ctrl + 3`, `Ctrl + 4`, `Ctrl + 5` (chụp/quay màn hình macOS và Mission Control).
  - Phím `Esc`: Hiển thị Modal hộp thoại tùy biến hỏi "Xác nhận thoát" với 2 nút "Ở lại" và "Thoát".

---

## 3. Hướng Dẫn Biên Dịch & Đóng Gói

### 3.1. Biên dịch dự án (trên máy macOS hoặc macOS VM/CI):
```bash
cd UTHSEBMac-1.0.4-Source
swift build -c release
```

### 3.2. Tạo App Bundle (`UTH SEB.app`):
```bash
mkdir -p "UTH SEB.app/Contents/MacOS"
mkdir -p "UTH SEB.app/Contents/Resources"

cp .build/release/UTHSEBMac "UTH SEB.app/Contents/MacOS/UTHSEBMac"
cp Info.plist "UTH SEB.app/Contents/Info.plist"
cp Resources/bgcourses.jpg "UTH SEB.app/Contents/Resources/"
cp Resources/launcher.html "UTH SEB.app/Contents/Resources/"
chmod +x "UTH SEB.app/Contents/MacOS/UTHSEBMac"
```

### 3.3. Ký mã nguồn (Codesign) & Tạo file `.pkg`:
```bash
codesign --force --deep --sign - "UTH SEB.app"
pkgbuild --root "UTH SEB.app" --install-location "/Applications/UTH SEB.app" --identifier "vn.edu.uth.seb.mac" --version "1.0.4" UTHSEB-Setup-1.0.4.pkg
```
