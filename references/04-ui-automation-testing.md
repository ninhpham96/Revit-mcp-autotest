# Test UI thật: chọn công cụ nào, và vì sao chạy từ process riêng

## Chọn công cụ

Skill này có **ba** kênh. Dùng cái rẻ nhất còn làm được việc, chỉ leo lên khi
kênh dưới thật sự không làm được — và ghi lại lý do đã leo.

| Việc cần làm | Dùng | Vì sao |
|---|---|---|
| Mở/đóng host, vượt dialog khởi động, chờ sẵn sàng | `scripts/HostUiTest.psm1` | Không cần build; xử lý sẵn cả Revit lẫn AutoCAD — [06](06-host-lifecycle.md) |
| Chạy một lệnh add-in **Revit** | `PostCommand` qua rvt-mcp | Đi đúng pipeline chính thức của Revit — [01](01-trigger-ribbon-button.md) |
| Chạy một lệnh add-in **AutoCAD** | COM `SendCommand` | Không cần MCP, gọi thẳng tên `[CommandMethod]` — [08](08-autocad-com.md) |
| Đọc state để khẳng định | rvt-mcp / COM / file log | Nguồn độc lập với UI — [02](02-debug-log-pattern.md), [05](05-safe-testing.md), [08](08-autocad-com.md) |
| Bấm nút, **chọn dòng trong DataGrid**, xác nhận dialog trong cửa sổ WPF của add-in | `assets/UiAutomationToolkit` (`uitest.exe`) | Có sẵn `select-row`, `click-and-confirm`; xử lý được pattern phức tạp |
| Kiểm nhanh một phần tử, đếm dòng, gõ vào ô tìm kiếm | `scripts/HostUiTest.psm1` | Một dòng PowerShell, không cần exe, không cần `dotnet build` |
| Bấm control **không có peer UIA** | `HostUiTest.psm1`, chuột thật | FlaUI cũng không thấy — [07](07-uia-blind-spots.md) |

Nói ngắn: **`HostUiTest.psm1` cho vòng đời host và kiểm tra nhanh; `uitest.exe`
cho thao tác UI phức tạp trong cửa sổ add-in.** Hai cái không thay thế nhau.

Khi UI không phản hồi như mong đợi, đọc [07-uia-blind-spots.md](07-uia-blind-spots.md)
trước khi kết luận add-in hỏng — có quy trình chẩn đoán 5 bước theo thứ tự.

## Cách đầu tiên đã thử — và tại sao bỏ

Bản năng đầu tiên: dùng `revit_send_code_to_revit` để tự bấm nút WPF bằng
`AutomationPeer.Invoke()`, rồi khi nút đó mở ra `MessageBox` xác nhận, spawn một
thread nền (`Task.Run`, `new Thread(...)`, kể cả set `ApartmentState.STA`) để tìm
và bấm "Yes".

**Thất bại nhiều lần liên tiếp, treo cả Revit thật**, cần người dùng bấm tay giải
cứu — 5-6 lần trong một phiên, thử cả 3 cách: UI Automation trên MTA, y hệt trên
STA, và `SendKeys.SendWait("{ENTER}")`.

**Nguyên nhân**: một thread tạo vội bên trong process khác **không có message
pump chuẩn của Windows**. UI Automation và input simulation đòi thread gọi phải
tham gia đúng vòng lặp thông điệp của hệ điều hành.

→ **Đây chính là lý do mọi framework automation (FlaUI, WinAppDriver...) luôn
chạy như một process hoàn toàn tách biệt** — không phải chi tiết vặt, mà là điều
kiện cần. Cả `uitest.exe` lẫn `HostUiTest.psm1` đều chạy ngoài process đích.

## `UiAutomationToolkit`

Toàn bộ source ở [assets/UiAutomationToolkit](../assets/UiAutomationToolkit);
`dotnet build` trong `src/UiAutomationToolkit.Cli` ra `uitest.exe`, dùng được cho
bất kỳ app WPF/WinForms nào.

```powershell
cd assets\UiAutomationToolkit\src\UiAutomationToolkit.Cli
dotnet build

.\bin\Debug\net8.0-windows\win-x64\uitest.exe select-row --pid <pid> --window "..." --grid <AutomationId> --row 0
.\bin\Debug\net8.0-windows\win-x64\uitest.exe click-and-confirm --pid <pid> --window "..." `
    --button "Tên nút" --dialog-button "Yes" --dialog-title "..."
```

Lệnh debug hữu ích khi không chắc UIA đang thấy gì: `debug-titles` (in cả code
point của tiêu đề), `debug-buttons`, `list-windows`. API + lệnh đầy đủ trong
[assets/UiAutomationToolkit/README.md](../assets/UiAutomationToolkit/README.md).

## Đính chính: lỗi dấu tiếng Việt ở tiêu đề cửa sổ

Bản trước của tài liệu này ghi rằng UIA đọc `Window.Title` bị hỏng dấu tiếng Việt
(`"Danh sách tường"` → `"Danh sách tu?ng"`), và khuyên **luôn** lọc cửa sổ bằng
một đoạn con **không dấu**.

**Đã thử lại và không tái hiện được.** Dựng một cửa sổ WPF tiêu đề
`"Danh sạch tường"` ở process riêng, đọc bằng cả ba đường — kết quả code point
**giống hệt nhau và giống hệt bản gốc**:

| Đường đọc | Code point trả về |
|---|---|
| Win32 `GetWindowTextW` | `0044 0061 006E 0068 0020 0073 1EA1 0063 0068 0020 0074 01B0 1EDD 006E 0067` |
| `System.Windows.Automation` | giống hệt |
| FlaUI (`uitest debug-titles`) | giống hệt |

→ Hiện tượng cũ **có thật** nhưng **không tổng quát** — nó gắn với ngữ cảnh cụ
thể lúc đó, không phải hành vi cố hữu của UIA. Đừng bỏ dấu khi lọc như một thói
quen; **kiểm bằng `debug-titles` hoặc `Get-HostWindow` trước**, chỉ né khi thật
sự thấy hỏng. Lọc bằng chuỗi không dấu làm phép khớp lỏng đi vô cớ và dễ trúng
nhầm cửa sổ khác.

`Get-HostWindow` trong `HostUiTest.psm1` đọc bằng Win32 `GetWindowTextW`
(Unicode) nên vốn đã miễn nhiễm với cả lớp lỗi này.

## Tốc độ

1. **Nút cổ chai nằm ở khâu tìm phần tử**, không phải ở khởi động process. Để
   UIA lọc ngay phía provider (`FindFirstDescendant` với điều kiện gộp) thay vì
   `FindAllDescendants().Where(...)`. Đo trên AutoCAD 2027: **95 ms** so với
   **3050 ms** — chênh 32 lần. Chi tiết ở [07](07-uia-blind-spots.md).
2. **Native AOT không dùng được** cho project dùng FlaUI — FlaUI dựa vào COM
   interop kiểu cũ (`CUIAutomation8Class`), AOT báo các method đó "sẽ luôn
   throw". Dùng `PublishReadyToRun` thay thế.
3. Gộp nhiều bước vào một lần chạy (`run-script`) tiết kiệm chi phí `Attach()`
   lặp lại, nhưng ảnh hưởng nhỏ hơn kỳ vọng.

## Yêu cầu phía app được test

Control cần bấm/chọn phải **có tên** — `x:Name` trong XAML là đủ (WPF tự expose
làm `AutomationId`, không cần set `AutomationProperties.AutomationId` thủ công).
Không cần sửa gì khác trong app để "test được".

Ưu tiên khớp theo `AutomationId` hơn theo `Name` — lý do và ví dụ thật ở
[07](07-uia-blind-spots.md).
