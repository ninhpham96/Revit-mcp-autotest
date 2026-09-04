# Test tự động UI thật — vì sao KHÔNG tiêm code vào process đích

## Cách đầu tiên đã thử — và tại sao bỏ

Bản năng đầu tiên: dùng `revit_send_code_to_revit` để tự bấm nút WPF bằng
`AutomationPeer.Invoke()` (raise đúng sự kiện `Click`, không phải gọi thẳng
method), rồi khi nút đó mở ra 1 `MessageBox` xác nhận, spawn 1 thread nền
(`Task.Run` hoặc `new Thread(...)`, kể cả set `ApartmentState.STA`) để tự tìm
và bấm "Yes".

**Thất bại nhiều lần liên tiếp, treo cả Revit thật**, cần người dùng bấm tay
giải cứu (`MessageBox` vẫn mở, chờ input, không có cách nào huỷ từ xa) —
5-6 lần trong 1 phiên làm việc, thử cả 3 cách:

1. `System.Windows.Automation` (UI Automation COM) trên thread MTA — không
   tìm thấy dialog.
2. Y hệt nhưng đổi sang STA thread — vẫn không tìm thấy (loại trừ giả thuyết
   MTA/STA là nguyên nhân).
3. `SendKeys.SendWait("{ENTER}")` — gọi không lỗi nhưng không đóng được dialog.

**Nguyên nhân**: 1 thread tạo vội bên trong process khác **không có message
pump chuẩn của Windows** — UI Automation và input simulation phụ thuộc thread
gọi phải tham gia đúng vòng lặp thông điệp của hệ điều hành, 1 `Thread` trần
tạo tạm bên trong process khác thường không đủ điều kiện đó.

→ **Đây chính là lý do các framework automation (FlaUI, WinAppDriver...) luôn
chạy như 1 process hoàn toàn tách biệt** với entry point + message pump riêng
ngay từ đầu — không phải chi tiết vặt, mà là điều kiện cần để hoạt động ổn định.

## Giải pháp: `UiAutomationToolkit` — process tách biệt

Toàn bộ source đã đóng gói sẵn tại
[assets/UiAutomationToolkit](../assets/UiAutomationToolkit) trong skill này —
copy thư mục đó ra, `dotnet build` trong `src/UiAutomationToolkit.Cli`, ra
`uitest.exe` dùng được ngay (không riêng Revit — bất kỳ app WPF/WinForms nào).

```powershell
cd UiAutomationToolkit\src\UiAutomationToolkit.Cli
dotnet build   # hoặc: dotnet publish -c Release (nhanh hơn, xem phần Tốc độ)

.\bin\Debug\net8.0-windows\uitest.exe select-row --pid <pid> --window "..." --grid <AutomationId> --row 0
.\bin\Debug\net8.0-windows\uitest.exe click-and-confirm --pid <pid> --window "..." `
    --button "Tên nút" --dialog-button "Yes" --dialog-title "..."
```

Đọc chi tiết đầy đủ API + lệnh CLI trong
[assets/UiAutomationToolkit/README.md](../assets/UiAutomationToolkit/README.md).
Phần dưới đây tóm tắt 2 lỗi thật đã verify khi dùng nó — **đọc trước khi tự ý
"sửa lại cho gọn"**, cả 2 đều không hiển nhiên và tốn nhiều vòng debug thật.

## Lỗi thật #1: UI Automation không thấy `MessageBox` khi UI thread lồng sâu

Cả `FlaUI.Core.Application.GetAllTopLevelWindows()` lẫn
`System.Windows.Automation.AutomationElement.RootElement.FindFirst/FindAll`
(2 API khác nhau nhưng dùng chung 1 `IUIAutomation` COM interface bên dưới)
**không bao giờ liệt kê được** cửa sổ `MessageBox.Show(...)` khi UI thread của
app đích đang lồng sâu trong 1 message loop khác — đúng tình huống 1 add-in
Revit nạp qua dev loader runtime. Verify bằng raw Win32 `EnumWindows`: thấy
cửa sổ đó **ngay lập tức**, tiêu đề đúng nguyên vẹn.

Giả thuyết nguyên nhân hợp lý nhất: UI Automation build cây control bằng cách
gửi `WM_GETOBJECT` tới cửa sổ đích và chờ phản hồi — thông điệp đó không được
xử lý đúng lúc khi UI thread lồng sâu, nên UI Automation "không thấy" dù cửa
sổ hoàn toàn bình thường ở tầng Win32.

**Cách né**: `NativeDialogHelper`
([assets/UiAutomationToolkit/src/UiAutomationToolkit.Core/NativeDialogHelper.cs](../assets/UiAutomationToolkit/src/UiAutomationToolkit.Core/NativeDialogHelper.cs))
dùng thẳng `EnumWindows` + `EnumChildWindows` + `SendMessage(BM_CLICK)` — bỏ
qua UI Automation hoàn toàn cho riêng phần dialog. Nút CHÍNH (nút mở ra
dialog) vẫn bấm qua UI Automation bình thường, vì UI Automation vẫn thấy
control WPF thông thường tốt — vấn đề chỉ nằm ở dialog native (`MessageBox`,
và khả năng cao cả `SaveFileDialog`/`ColorDialog` khác cũng vậy vì cùng cơ
chế Win32 bên dưới).

Command `click-and-confirm` của CLI đã tích hợp sẵn cách này — không cần tự
viết lại.

## Lỗi thật #2: tiêu đề cửa sổ (không phải tên nút) bị hỏng dấu tiếng Việt

`Window.Title` đọc qua UI Automation Name property bị Windows "best-fit" hỏng
ký tự tiếng Việt không có trong bảng mã ANSI — ví dụ `"Danh sách tường"` →
`"Danh sách tu?ng"` (`ư`→`u`, `ờ`→`?`). Verify: đọc trực tiếp `Window.Title`
trong chính process add-in (giá trị đúng), đọc qua `GetWindowText` — Win32,
Unicode — từ bên ngoài (cũng đúng) — **chỉ riêng UI Automation Name property
của `ControlType.Window`** bị lỗi này.

**Tên control con (nút, ví dụ `"Xoá tường đã chọn"`) đọc qua UI Automation vẫn
đúng nguyên vẹn, không bị ảnh hưởng** — đã verify tách biệt 2 hiện tượng này
(lệnh debug `debug-titles` vs `debug-buttons` trong CLI).

**Cách né**: khi lọc cửa sổ theo tiêu đề (tham số `--window` của CLI, hoặc
`WaitForWindow(...)` trong code), dùng 1 đoạn con **không dấu** đủ đặc trưng
(ví dụ `"Danh s"` thay vì `"Danh sách tường"`). Khi lọc theo tên nút/control
thì dùng nguyên văn có dấu bình thường, không vấn đề gì.

## Lưu ý về shell khi tham số có dấu tiếng Việt

Git Bash truyền tham số UTF-8 có dấu cho exe Windows không ổn định (thử
nghiệm cho kết quả không nhất quán giữa các lần chạy) — dùng **PowerShell
hoặc cmd** khi tham số CLI chứa tiếng Việt có dấu.

## Tốc độ

Đã đo thật và tối ưu — chi tiết đầy đủ trong
[assets/UiAutomationToolkit/README.md](../assets/UiAutomationToolkit/README.md#tốc-độ--3-điều-đã-đo-được-xếp-theo-mức-ảnh-hưởng),
tóm tắt:

1. **Bottleneck thật nằm ở `FindButton`** — quét toàn bộ cây control
   (`FindAllDescendants`) rồi mới lọc tên, chậm gấp ~10 lần so với để UI
   Automation lọc ngay phía provider (`FindFirstDescendant(ByName+ByControlType)`).
   Đã sửa trong `WindowExtensions.FindButton` — nếu tự thêm hàm tìm control
   mới, ưu tiên `FindFirstDescendant` với điều kiện gộp, tránh
   `FindAllDescendants().Where(...)`.
2. **Native AOT không dùng được** cho project dùng FlaUI — FlaUI dựa vào COM
   interop kiểu cũ (`CUIAutomation8Class`...), AOT báo thẳng các method đó "sẽ
   luôn throw" (build được cũng crash lúc chạy). Dùng `PublishReadyToRun`
   thay thế — giữ nguyên CoreCLR (COM interop hoạt động bình thường), vẫn
   giảm được thời gian khởi động.
3. Gộp nhiều bước vào 1 lần chạy (`run-script` — xem README) tiết kiệm được
   phần chi phí `Attach()` lặp lại, nhưng ảnh hưởng nhỏ hơn kỳ vọng (phần lớn
   thời gian nằm ở UI Automation tìm phần tử, không phải khởi động process).

## Yêu cầu phía app được test

Control cần bấm/chọn phải **có tên** — `x:Name` trong XAML là đủ (WPF tự
expose làm `AutomationId` mặc định, không cần set
`AutomationProperties.AutomationId` thủ công — đã verify). Không cần sửa gì
khác trong app để "test được".
