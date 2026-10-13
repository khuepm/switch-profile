# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

Công cụ nhỏ trên macOS giúp mở link từ ứng dụng khác bằng đúng profile Google Chrome.

**Trạng thái: bản demo cục bộ (v0.1.0).** Ứng dụng được build từ mã nguồn thành một `.app` cục bộ, ký ad-hoc. Chưa có bản phát hành để tải xuống. Trình duyệt mục tiêu ban đầu là Google Chrome.

## Cách hoạt động

`Bấm link trong ứng dụng khác → macOS → Switch Profile → kiểm tra quy tắc → profile Chrome`

Người dùng đặt Switch Profile làm trình duyệt mặc định một lần. Ứng dụng nhận link HTTP/HTTPS được chuyển cho trình duyệt mặc định của hệ thống, chọn profile và chuyển nguyên URL sang Chrome. Các ứng dụng dùng trình duyệt tích hợp hoặc chỉ định trình duyệt riêng có thể bỏ qua luồng này.

Ứng dụng chạy trên thanh menu và xử lý quy tắc cục bộ. Không cần máy chủ hay GitHub/GitLab API. Quyền truy cập repository sử dụng phiên đăng nhập sẵn có trong profile Chrome được chọn.

## Quy tắc demo

Quy tắc theo repository được ưu tiên trước quy tắc chung theo tên miền.

| Điều kiện | Profile Chrome | Link nghiệm thu |
| --- | --- | --- |
| Tên miền chính xác `git.fis.vn`, mọi đường dẫn | `khuepm18` | [Merge requests GitLab](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| Tên miền `github.com`, repository `/TruckerPoints/trucker-points` và các trang con | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| Các link còn lại trên tên miền chính xác `github.com` | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| Tên miền khác | Profile dự phòng do người dùng chọn | Một website bất kỳ khác |

Quy tắc repository bao gồm các trang `/issues`, `/pull/123`, nhưng không được khớp `/TruckerPoints/trucker-points-other`. So khớp bằng hostname đã phân tích, không tìm chuỗi trong toàn bộ URL. Giữ nguyên đường dẫn, tham số truy vấn và phần fragment sau dấu `#`.

Tên miền được so khớp chính xác. Các tên miền con như `www.github.com`, `api.github.com`, `gist.github.com` hoặc `sub.git.fis.vn` không khớp quy tắc GitHub hay GitLab; chúng đi tới profile dự phòng.

## Giao diện

- Trạng thái trình duyệt mặc định và hướng dẫn thiết lập.
- Danh sách profile Chrome và lựa chọn profile cho từng quy tắc.
- Lựa chọn profile dự phòng.
- Ô nhập URL với nút **Check rule** (kiểm tra quy tắc) và **Open test link** (mở thử).
- Hướng xử lý rõ ràng khi profile đã cấu hình không còn tồn tại.

Tên hiển thị và địa chỉ email của profile không nhất thiết là tên thư mục. Ứng dụng ánh xạ đến thư mục profile thực tế như `Default` hoặc `Profile 2`, không suy đoán, không sửa dữ liệu đăng nhập và không âm thầm tạo profile mới.

## Kế hoạch triển khai

1. Xác minh mở đúng cả ba profile khi Chrome đang chạy và đã đóng.
2. Tạo ứng dụng macOS bằng AppKit, nhận sự kiện mở URL HTTP/HTTPS.
3. Cài quy tắc repository/tên miền với thứ tự rõ ràng, profile dự phòng và chống vòng lặp.
4. Thêm menu, cài đặt, ánh xạ profile và xem trước kết quả chọn quy tắc.
5. Kiểm thử toàn bộ luồng và đóng gói demo `.app`, kèm hướng dẫn cài đặt và gỡ bỏ.

Mục tiêu là mở tab trong cửa sổ của đúng profile, hoặc tạo cửa sổ nếu cần. Cần kiểm chứng việc tái sử dụng cửa sổ trên phiên bản Chrome thực tế. Ký ứng dụng, notarization và cập nhật tự động thuộc giai đoạn sau.

<!-- sp:requirements -->
## Yêu cầu

- macOS 13 trở lên (deployment target). Chỉ mới kiểm thử trên macOS 27.
- Google Chrome (kênh stable) trong `/Applications`, đã mở ít nhất một lần để có profile.
- Command Line Tools for Xcode (`xcode-select --install`). Không cần cài Xcode.

<!-- sp:build-install -->
## Build và cài đặt

Trong thư mục repository:

```sh
scripts/build-app.sh            # build và ký ad-hoc build/SwitchProfile.app
scripts/build-app.sh --install  # đồng thời chép vào ~/Applications/SwitchProfile.app, đăng ký và mở ứng dụng
```

Ứng dụng hiện thành biểu tượng trên thanh menu, không có biểu tượng trên Dock.

<!-- sp:configuration -->
## Cấu hình ánh xạ profile

Mở **Settings…** từ biểu tượng trên thanh menu. Mỗi quy tắc (R1 git.fis.vn, R2 trucker-points, R3 các link github.com khác, R4 dự phòng) có một Picker liệt kê các profile tìm thấy trong Chrome.

- Ở lần chạy đầu, Switch Profile tự nhận diện profile cho R1–R3 theo danh tính trong bảng quy tắc. Các dòng đó hiện "Auto-detected: matched by …". Bấm **Confirm** để chấp nhận, hoặc chọn profile khác.
- **Detect** tìm lại profile theo danh tính của quy tắc. Nếu có nhiều profile khớp, ứng dụng không tự chọn mà để bạn chọn.
- R4 là profile dự phòng cho mọi tên miền khác và không bao giờ được chọn tự động. Nếu R4 là "Not set", các link không liên quan sẽ chờ trong cửa sổ link đang chờ.
- **Check rule** cho biết quy tắc và profile của một URL mà không mở Chrome. **Open test link** gửi URL qua đúng luồng định tuyến thật.
- Profile bị mất hoặc tài khoản đã đổi được đánh dấu ở dòng tương ứng và trong menu ("Profile mapping needs attention …").

Cấu hình được lưu tại `~/Library/Application Support/SwitchProfile/config.json`. Nếu tệp không hợp lệ, menu hiện "Configuration error – Reset to defaults…". Reset giữ lại bản sao lưu tên `config.corrupt-<ngày>.json`.

<!-- sp:default-browser -->
## Đặt làm trình duyệt mặc định

Trong Settings, bấm **Set as default browser…** (menu cũng có mục "Set as Default Browser…") và xác nhận hộp thoại của macOS. Sau đó Settings cho biết Switch Profile đang xử lý `http` và `https`.

Bạn cũng có thể chọn trong System Settings → Desktop & Dock → Default web browser.

<!-- sp:troubleshooting -->
## Xử lý sự cố

- **"Chrome profiles unavailable" / lỗi Local State.** Switch Profile đọc `~/Library/Application Support/Google/Chrome/Local State`. Hãy chắc Chrome đã được cài và mở ít nhất một lần. Trên macOS 27, hệ thống có thể chặn ứng dụng đọc tệp này; hãy cấp quyền cho Switch Profile trong System Settings → Privacy & Security (App Data hoặc Full Disk Access), rồi bấm **Refresh** trong Settings hoặc **Refresh profiles** trong cửa sổ link đang chờ.
- **Cửa sổ link đang chờ.** Link chưa mở được (chưa chọn profile, profile bị mất, không mở được Chrome) được giữ lại, không bị bỏ. Mở cửa sổ từ mục "Pending links (n)…" trong menu và dùng **Open once**, **Open and use for R…**, **Retry** hoặc **Discard**.
- **Một bản sao khác đang là mặc định.** Nếu Settings báo "Another copy at … is the default; remove it.", hãy xóa bản sao đó, hủy đăng ký bằng `lsregister -u <đường dẫn>` (đường dẫn đầy đủ ở phần Gỡ bỏ), rồi đặt mặc định lại.
- **Gatekeeper.** Ứng dụng được ký ad-hoc và chưa notarize. Nếu macOS chặn, Control-click vào ứng dụng và chọn Open, hoặc cho phép trong System Settings → Privacy & Security.
- **Kiểm tra định tuyến từ Terminal.** Chạy thử (dry run) in ra quy tắc, thư mục profile và đúng tham số gửi cho Chrome mà không mở hay ghi gì:

  ```sh
  build/SwitchProfile.app/Contents/MacOS/SwitchProfile --dry-run [--assume-chrome running|closed] URL...
  ```

<!-- sp:restore -->
## Khôi phục trình duyệt mặc định trước đó

Khi đặt Switch Profile làm mặc định, ứng dụng ghi lại trình duyệt trước đó. Trong Settings, bấm **Restore previous default (…)…**. Bạn cũng có thể chọn lại trình duyệt trong System Settings → Desktop & Dock → Default web browser.

<!-- sp:remove -->
## Gỡ bỏ

1. Khôi phục trình duyệt mặc định trước đó (ở trên).
2. Thoát Switch Profile từ menu ("Quit Switch Profile").
3. Xóa `~/Applications/SwitchProfile.app` (và `build/SwitchProfile.app` nếu bạn đã build).
4. Hủy đăng ký với Launch Services:

   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/SwitchProfile.app
   ```

5. Xóa thư mục cài đặt `~/Library/Application Support/SwitchProfile/`.

<!-- sp:version -->
## Phiên bản

0.1.0 (build 1). Tối thiểu macOS 13 (deployment target); chỉ mới kiểm thử trên macOS 27.

<!-- sp:signing -->
## Giới hạn về ký ứng dụng

Ứng dụng được `scripts/build-app.sh` ký ad-hoc và chưa notarize, dùng cục bộ trên máy đã build. Ký bằng Developer ID, notarization và cập nhật tự động thuộc giai đoạn sau.

<!-- sp:known-limitations -->
## Giới hạn đã biết

- Ứng dụng dùng trình duyệt tích hợp, hoặc mở thẳng một trình duyệt cụ thể, sẽ bỏ qua Switch Profile.
- Việc link mở trong tab mới hay cửa sổ mới do Chrome quyết định.
- Hiện chỉ hỗ trợ Google Chrome.

## Tiêu chí nghiệm thu

- Cả ba link mẫu đều mở đúng profile khi bấm từ ứng dụng khác.
- Vẫn chọn đúng profile khi cửa sổ của profile khác đang ở phía trước.
- Hoạt động khi Chrome hoặc Switch Profile chưa chạy.
- Tên miền khác dùng profile dự phòng đã chọn, không gọi lặp lại Switch Profile.
- Profile thiếu hoặc không xác định duy nhất phải có lựa chọn xử lý rõ ràng; không âm thầm đổi tài khoản.
- Mở nhiều link không làm mất link hoặc mở trùng.
- Giữ nguyên query và fragment; không khớp nhầm tên miền tương tự hoặc tiền tố repository.
- Người dùng có thể khôi phục trình duyệt mặc định trước đó.

Trạng thái kiểm thử của từng tiêu chí nằm trong [ma trận nghiệm thu](docs/ACCEPTANCE.md).

## Phát triển và backlog

Xem [backlog](docs/BACKLOG.md) để theo dõi epic, các issue triển khai, mức ưu tiên, phụ thuộc và tiêu chí hoàn tất. Build bằng `swift build` và chạy kiểm thử bằng `swift test`.

Quy trình: tạo hoặc dùng lại issue → đánh dấu **Đang làm / In Progress** trong GitHub Project (hoặc label `status:in-progress` nếu không dùng Project) → nhánh có tiền tố ID issue → PR liên kết issue → kiểm tra đạt yêu cầu → merge vào `main` → đánh dấu **Hoàn tất / Done** và đóng issue đã giải quyết. PR giải quyết đầy đủ issue dùng `Closes #<id>`. Các issue triển khai giữ mở cho đến khi đạt tiêu chí nghiệm thu.

## Tài liệu kỹ thuật

- [Apple: nhận sự kiện mở URL bằng AppKit](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium: thư mục dữ liệu và profile](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
