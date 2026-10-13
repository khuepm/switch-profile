# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

Công cụ nhỏ trên macOS giúp mở link từ ứng dụng khác bằng đúng profile Google Chrome.

**Trạng thái: lập kế hoạch và thiết lập repository.** Repository hiện có tài liệu và backlog phát triển; chưa có ứng dụng chạy được hoặc bản phát hành để tải xuống. Trình duyệt mục tiêu ban đầu là Google Chrome.

## Cách hoạt động

`Bấm link trong ứng dụng khác → macOS → Switch Profile → kiểm tra quy tắc → profile Chrome`

Người dùng đặt Switch Profile làm trình duyệt mặc định một lần. Ứng dụng nhận link HTTP/HTTPS được chuyển cho trình duyệt mặc định của hệ thống, chọn profile và chuyển nguyên URL sang Chrome. Các ứng dụng dùng trình duyệt tích hợp hoặc chỉ định trình duyệt riêng có thể bỏ qua luồng này.

Ứng dụng dự kiến chạy trên thanh menu và xử lý quy tắc cục bộ. Không cần máy chủ hay GitHub/GitLab API. Quyền truy cập repository sử dụng phiên đăng nhập sẵn có trong profile Chrome được chọn.

## Quy tắc demo

Quy tắc theo repository được ưu tiên trước quy tắc chung theo tên miền.

| Điều kiện | Profile Chrome | Link nghiệm thu |
| --- | --- | --- |
| Tên miền chính xác `git.fis.vn`, mọi đường dẫn | `khuepm18` | [Merge requests GitLab](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| Tên miền `github.com`, repository `/TruckerPoints/trucker-points` và các trang con | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| Các link còn lại trên tên miền chính xác `github.com` | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| Tên miền khác | Profile dự phòng do người dùng chọn | Một website bất kỳ khác |

Quy tắc repository bao gồm các trang `/issues`, `/pull/123`, nhưng không được khớp `/TruckerPoints/trucker-points-other`. So khớp bằng hostname đã phân tích, không tìm chuỗi trong toàn bộ URL. Giữ nguyên đường dẫn, tham số truy vấn và phần fragment sau dấu `#`.

## Giao diện demo dự kiến

- Trạng thái trình duyệt mặc định và hướng dẫn thiết lập.
- Danh sách profile Chrome và lựa chọn profile cho từng quy tắc.
- Lựa chọn profile dự phòng.
- Ô nhập URL với nút **Kiểm tra quy tắc** và **Mở thử**.
- Hướng xử lý rõ ràng khi profile đã cấu hình không còn tồn tại.

Tên hiển thị và địa chỉ email của profile không nhất thiết là tên thư mục. Ứng dụng phải ánh xạ đến thư mục profile thực tế như `Default` hoặc `Profile 2`, không suy đoán, không sửa dữ liệu đăng nhập và không âm thầm tạo profile mới.

## Kế hoạch triển khai

1. Xác minh mở đúng cả ba profile khi Chrome đang chạy và đã đóng.
2. Tạo ứng dụng macOS bằng AppKit, nhận sự kiện mở URL HTTP/HTTPS.
3. Cài quy tắc repository/tên miền với thứ tự rõ ràng, profile dự phòng và chống vòng lặp.
4. Thêm menu, cài đặt, ánh xạ profile và xem trước kết quả chọn quy tắc.
5. Kiểm thử toàn bộ luồng và đóng gói demo `.app`, kèm hướng dẫn cài đặt và gỡ bỏ.

Mục tiêu là mở tab trong cửa sổ của đúng profile, hoặc tạo cửa sổ nếu cần. Cần kiểm chứng việc tái sử dụng cửa sổ trên phiên bản Chrome thực tế. Ước lượng demo là 2–3 ngày công, tùy kết quả thử nghiệm mở profile; ký ứng dụng, notarization và cập nhật tự động thuộc giai đoạn sau.

## Tiêu chí nghiệm thu

- Cả ba link mẫu đều mở đúng profile khi bấm từ ứng dụng khác.
- Vẫn chọn đúng profile khi cửa sổ của profile khác đang ở phía trước.
- Hoạt động khi Chrome hoặc Switch Profile chưa chạy.
- Tên miền khác dùng profile dự phòng đã chọn, không gọi lặp lại Switch Profile.
- Profile thiếu hoặc không xác định duy nhất phải có lựa chọn xử lý rõ ràng; không âm thầm đổi tài khoản.
- Mở nhiều link không làm mất link hoặc mở trùng.
- Giữ nguyên query và fragment; không khớp nhầm tên miền tương tự hoặc tiền tố repository.
- Người dùng có thể khôi phục trình duyệt mặc định trước đó.

## Phát triển và backlog

Xem [backlog](docs/BACKLOG.md) để theo dõi epic, các issue triển khai, mức ưu tiên, phụ thuộc và tiêu chí hoàn tất. Lệnh build và cài đặt sẽ được bổ sung khi có phiên bản chạy được.

Quy trình: tạo hoặc dùng lại issue → đánh dấu **Đang làm / In Progress** trong GitHub Project (hoặc label `status:in-progress` nếu không dùng Project) → nhánh có tiền tố ID issue → PR liên kết issue → kiểm tra đạt yêu cầu → merge vào `main` → đánh dấu **Hoàn tất / Done** và đóng issue đã giải quyết. PR giải quyết đầy đủ issue dùng `Closes #<id>`. Các issue triển khai giữ mở cho đến khi đạt tiêu chí nghiệm thu.

## Tài liệu kỹ thuật

- [Apple: nhận sự kiện mở URL bằng AppKit](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium: thư mục dữ liệu và profile](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
