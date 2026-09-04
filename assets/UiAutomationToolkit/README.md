# UiAutomationToolkit

Thư viện + CLI dùng chung để **tự động test UI của app WPF/WinForms đang chạy**
(Revit add-in, hoặc bất kỳ app desktop nào khác) từ bên ngoài, qua Windows UI
Automation (FlaUI) kết hợp Win32 thuần cho phần dialog. Xây dựng sau khi rút
kinh nghiệm thực tế từ việc test 1 add-in Revit (RevitAddIn1) — mọi quyết định
kiến trúc dưới đây đều xuất phát từ 1 lỗi thật đã gặp và đã verify cách sửa.

## Cấu trúc

```
src/
  UiAutomationToolkit.Core/   thư viện lõi (FlaUI.Core + FlaUI.UIA3)
  UiAutomationToolkit.Cli/    CLI "uitest" — gọi trực tiếp từ terminal, không cần viết code
```

## Vì sao chạy từ process riêng, không tiêm code vào process đích

Cách đầu tiên (đã thử và bỏ): dùng cơ chế "chạy code trong process đích" của
add-in (kiểu `revit_send_code_to_revit` của rvt-mcp) để tự bấm nút UI bằng
`AutomationPeer.Invoke()`. Vấn đề: khi nút đó mở ra 1 `MessageBox` xác nhận,
cần 1 thread khác tự tìm và bấm "Yes" — nhưng thread tạo vội bên trong process
khác (`Task.Run`, `new Thread(...)`, kể cả set `ApartmentState.STA`) **không có
message pump chuẩn của Windows**, nên cả UI Automation lẫn `SendKeys` chạy từ
thread đó đều không hoạt động ổn định, dễ treo cả app.

→ **`UiAutomationToolkit.Cli` chạy như 1 process hoàn toàn tách biệt**, có
entry point + message pump của riêng nó ngay từ đầu — đây là lý do FlaUI (và
UI automation nói chung) luôn được khuyến nghị chạy như vậy, không phải chi
tiết vặt.

## 2 lỗi thật đã gặp — và cách né

### 1. UI Automation không thấy `MessageBox.Show(...)` khi UI thread lồng sâu

**Hiện tượng**: `Application.GetAllTopLevelWindows()` (FlaUI) và
`AutomationElement.RootElement.FindFirst/FindAll` (`System.Windows.Automation`
gốc) — cả 2 cách, dùng chung 1 COM interface `IUIAutomation` bên dưới — **không
bao giờ liệt kê được** cửa sổ `MessageBox` dù nó đang hiện thật, chặn cả app.
Verify bằng Win32 `EnumWindows` thuần: thấy cửa sổ đó ngay lập tức, tiêu đề
đúng nguyên vẹn.

**Nguyên nhân khả dĩ nhất**: UI Automation build cây control bằng cách gửi
`WM_GETOBJECT` tới cửa sổ đích và chờ phản hồi — khi UI thread của app đích
đang lồng trong 1 message loop khác (ví dụ Revit add-in được nạp qua 1 loader
runtime khác thay vì pipeline chuẩn), thông điệp đó không được xử lý đúng lúc,
nên UI Automation "không thấy" cửa sổ dù nó hoàn toàn bình thường ở tầng Win32.

**Cách né**: [`NativeDialogHelper`](src/UiAutomationToolkit.Core/NativeDialogHelper.cs)
dùng thẳng `EnumWindows` + `EnumChildWindows` + `SendMessage(BM_CLICK)` — không
qua UI Automation — để tìm và bấm nút trên dialog. `WindowExtensions.ClickButtonAndHandleDialog(...)`
dùng cách này. Nút chính (mở dialog) vẫn bấm qua UI Automation bình thường —
vấn đề chỉ nằm ở dialog con.

### 2. Tiêu đề cửa sổ (không phải tên control) bị Windows làm hỏng dấu tiếng Việt

**Hiện tượng**: `Window.Title` qua UI Automation trả về `"Danh sách tu?ng"`
thay vì `"Danh sách tường"` thật — `ư`(U+01B0)→`u`, `ờ`(U+1EDD)→`?`. Verify
bằng cách đọc trực tiếp `Window.Title` trong chính process (giá trị đúng), và
đọc qua `GetWindowText` (Win32, Unicode) từ bên ngoài (cũng đúng) — chỉ riêng
**UI Automation Name property của `ControlType.Window`** bị lỗi này. Tên control
con (nút, ví dụ `"Xoá tường đã chọn"`) đọc qua UI Automation vẫn đúng nguyên
vẹn, không bị ảnh hưởng.

**Cách né**: khi lọc theo tiêu đề cửa sổ (`WaitForWindow`, `--window` của CLI),
dùng 1 đoạn con **không dấu** đủ đặc trưng (vd `"Danh s"` thay vì
`"Danh sách tường"`). Khi lọc theo tên nút/control thì dùng nguyên văn có dấu
bình thường, không vấn đề gì.

Ngoài ra, mọi so khớp chuỗi trong toolkit đều đi qua
[`TextMatch`](src/UiAutomationToolkit.Core/TextMatch.cs) (Unicode-normalize
trước khi so — phòng trường hợp môi trường khác trả về dạng tổ hợp dấu khác
nhau, dù trong lần điều tra này hoá ra không phải nguyên nhân, để lại cho chắc).

## Cài đặt

```bash
cd src/UiAutomationToolkit.Cli
dotnet build
# ra: bin/Debug/net8.0-windows/uitest.exe   (dùng khi phát triển)

dotnet publish -c Release
# ra: bin/Release/net8.0-windows/win-x64/publish/uitest.exe   (dùng khi chạy test thật — nhanh hơn)
```

## Tốc độ — 3 điều đã đo được, xếp theo mức ảnh hưởng

1. **`FindButton` từng chậm ~10 lần** (1380ms thay vì ~130-300ms) vì dùng
   `FindAllDescendants` (quét TOÀN BỘ cây control, kể cả bên trong `DataGrid`)
   rồi mới lọc theo tên ở phía managed. Đã sửa: ưu tiên
   `FindFirstDescendant(ByName + ByControlType)` — UI Automation lọc ngay phía
   provider (native), chỉ fallback về cách quét chậm nếu không khớp exact.
   **Đây là chỗ đáng sửa nhất** — ảnh hưởng mọi lệnh có bấm nút.
2. **`run-script`** gộp nhiều bước vào 1 lần `Attach()` — tiết kiệm được phần
   chi phí gắn lại vào process + quét cửa sổ ban đầu mỗi lệnh, nhưng đo thực tế
   chỉ ~7% (phần lớn thời gian nằm ở bước UI Automation tìm phần tử, không phải
   ở việc khởi động process/attach).
3. **`PublishReadyToRun` + self-contained** — cải thiện ~10% thời gian khởi
   động .NET runtime. Đã thử **Native AOT trước** nhưng **không dùng được**:
   FlaUI dựa vào COM interop kiểu cũ (`CUIAutomation8Class`...), AOT báo thẳng
   các method đó "sẽ luôn throw" — tức dù ép build được cũng crash ngay khi
   chạy. ReadyToRun giữ nguyên CoreCLR (COM interop hoạt động bình thường) nên
   an toàn.

**Kết quả tổng**: luồng test thật (chọn dòng + bấm nút + tự xác nhận dialog)
giảm từ overhead nặng do FindButton chậm xuống còn **~2 giây/lần** end-to-end.

## Dùng CLI

```
uitest <lệnh> --process <tên> | --pid <id> [--timeout <giây>] [tham số riêng của lệnh]
```

| Lệnh | Tham số riêng | Mô tả |
|---|---|---|
| `list-windows` | | Liệt kê tiêu đề mọi cửa sổ top-level của process |
| `list-buttons` | `--window` | Liệt kê tên mọi nút trong 1 cửa sổ |
| `click-button` | `--window --button` | Bấm 1 nút (không có dialog con) |
| `click-and-confirm` | `--window --button --dialog-button [--dialog-title]` | Bấm nút + tự xử lý dialog con mở ra sau đó |
| `select-row` | `--window --grid <AutomationId> --row <index>` | Chọn 1 dòng trong DataGrid (WPF) |
| `run-script` | `--file <path>` | Chạy nhiều lệnh trên, gộp trong 1 lần attach (xem cú pháp file bên dưới) |

Ví dụ (PowerShell — **khuyến nghị dùng PowerShell/cmd thay vì Git Bash khi
tham số có dấu tiếng Việt**, Git Bash truyền UTF-8 qua exe Windows không ổn định):

```powershell
uitest select-row --pid 23484 --window "Danh s" --grid WallsDataGrid --row 0
uitest click-and-confirm --pid 23484 --window "Danh s" `
    --button "Xoá tường đã chọn" --dialog-button "Yes" --dialog-title "nh"
```

## Yêu cầu phía app được test

- Control cần bấm/chọn phải **có tên** (`x:Name` trong XAML là đủ — WPF tự
  expose làm `AutomationId` mặc định, không cần set `AutomationProperties.AutomationId`
  thủ công, đã verify).
- Không có yêu cầu gì đặc biệt khác — mọi kỹ thuật ở đây hoạt động với app đã
  build sẵn, không cần sửa code app để "test được".

## Dùng thư viện `Core` trong code C# khác (không qua CLI)

```csharp
using var session = AutomationSession.AttachByProcessId(pid);
var window = session.WaitForWindow("Danh s"); // ASCII-safe substring nếu tiêu đề có dấu
window.SelectDataGridRow("WallsDataGrid", 0);
window.ClickButtonAndHandleDialog(session, "Xoá tường đã chọn", "Yes", dialogTitleContains: "nh");
```

## Lệnh debug đi kèm (chẩn đoán khi gặp lỗi lạ)

- `debug-echo --window <text>` — in ra mã Unicode từng ký tự của 1 tham số, để
  loại trừ lỗi encoding khi truyền qua shell.
- `debug-titles --pid <id>` — in tiêu đề + mã Unicode của mọi cửa sổ UI
  Automation thấy được.
- `debug-buttons --pid <id> --window <text>` — in tên + mã Unicode mọi nút
  trong 1 cửa sổ.
- `watch-windows --pid <id> --seconds <n> --log <path>` — ghi log mọi cửa sổ
  top-level MỚI xuất hiện (theo UI Automation) trong n giây — dùng để phát
  hiện trường hợp UI Automation "không thấy" 1 cửa sổ (như lỗi #1 ở trên).
