# revit-cad-addin-autotest

Claude Code skill: quy trình phát triển + **bắt buộc test qua host thật** (không
chỉ build sạch) cho add-in **Revit** và **AutoCAD**.

Hai nửa bổ sung nhau:

- **Bên trong process** — điều khiển Revit qua MCP client
  [rvt-mcp](https://github.com/bimwright/rvt-mcp): bấm nút ribbon bằng
  `PostCommand`, đọc state bằng `revit_send_code_to_revit`, pattern
  `ExternalEvent` cho cửa sổ WPF modeless.
- **Bên ngoài process** — lái host từ ngoài: mở app, vượt dialog khởi động, bấm
  control bằng UI Automation hoặc chuột thật, và điều khiển AutoCAD qua COM
  (AutoCAD không cần MCP).

Đúc kết từ các phiên làm việc thực tế — mọi kỹ thuật, mọi lỗi trong này đều đã
verify bằng cách chạy thật, không phải lý thuyết; chỗ nào chưa verify thì ghi rõ.
Chi tiết đầy đủ trong [SKILL.md](SKILL.md) và [references/](references).

## Cài đặt (lần đầu)

Skill cài ở **cấp user** — dùng được cho mọi project add-in trên máy đó.

```bash
git clone https://github.com/ninhpham96/Revit-mcp-autotest.git ~/.claude/skills/revit-cad-addin-autotest
```

Windows PowerShell:

```powershell
git clone https://github.com/ninhpham96/Revit-mcp-autotest.git $env:USERPROFILE\.claude\skills\revit-cad-addin-autotest
```

`scripts/HostUiTest.psm1` dùng được ngay, không cần build. Chỉ
`UiAutomationToolkit` mới cần build, và chỉ khi bạn cần thao tác UI phức tạp
(chọn dòng DataGrid, xác nhận dialog — xem
[references/04-ui-automation-testing.md](references/04-ui-automation-testing.md)):

```bash
cd ~/.claude/skills/revit-cad-addin-autotest/assets/UiAutomationToolkit
dotnet build
```

Mở một phiên **Claude Code mới** (danh sách skill chỉ nạp lúc khởi động phiên).

> **Đổi tên thư mục từ bản cũ**: nếu đang cài ở
> `~/.claude/skills/revit-addin-mcp-workflow`, chỉ cần đổi tên thư mục thành
> `revit-cad-addin-autotest` — git remote và mọi đường dẫn nội bộ đều giữ nguyên.

## Yêu cầu trước khi dùng

- **Windows PowerShell 5.1+** — cho `scripts/HostUiTest.psm1` (có sẵn trên Windows).
- **[rvt-mcp](https://github.com/bimwright/rvt-mcp)** — chỉ cần nếu làm add-in
  Revit và muốn điều khiển từ trong process.
- **.NET SDK** — để build add-in, và `UiAutomationToolkit` nếu dùng tới.
- **AutoCAD bản full** (không phải LT) nếu làm add-in AutoCAD — LT không có
  COM/.NET API.

## Cách dùng

Skill tự trigger khi nhắc tới các tình huống liên quan — không cần gọi thủ công.
Ví dụ:

```
/revit-cad-addin-autotest thêm nút xuất danh sách tường ra Excel, test luôn
```

Claude sẽ theo đúng quy trình: sửa code → build → mở host thật → chạy tính năng
với DLL mới → verify bằng nguồn ngoài UI → phục hồi dữ liệu → mới báo xong.

Chạy thử ngay không cần add-in nào:

```powershell
& "$env:USERPROFILE\.claude\skills\revit-cad-addin-autotest\examples\acad-smoke.ps1"
```

## Cập nhật khi skill có bản mới

```bash
~/.claude/skills/revit-cad-addin-autotest/update-skill.sh
```

```powershell
& "$env:USERPROFILE\.claude\skills\revit-cad-addin-autotest\update-skill.ps1"
```

Script tự `git pull`, build lại `UiAutomationToolkit` nếu source đổi, kiểm BOM
của các file PowerShell, và dừng lại nếu có thay đổi local chưa commit.

## Cấu trúc repo

```
SKILL.md                              — nội dung chính, Claude đọc khi skill trigger
references/
  01-trigger-ribbon-button.md         — bấm nút ribbon Revit từ MCP (PostCommand)
  02-debug-log-pattern.md             — xác nhận command chạy tới đâu (DebugLog)
  03-external-event-pattern.md        — test cửa sổ WPF: .Show() khác .ShowDialog() thế nào
  04-ui-automation-testing.md         — CHỌN công cụ nào; vì sao chạy ngoài process
  05-safe-testing.md                  — khẳng định đúng chỗ + không phá dữ liệu thật
  06-host-lifecycle.md                — mở host, biết khi nào nó THẬT SỰ sẵn sàng
  07-uia-blind-spots.md               — UIA không thấy gì, vì sao, và leo thang ra sao
  08-autocad-com.md                   — AutoCAD: COM là kênh chạy lệnh + đọc state
  09-powershell-traps.md              — bẫy PowerShell trong harness test
  10-dynamic-loader-resolution.md      — tìm đúng nút khi add-in nạp qua dev loader slot chung
scripts/
  HostUiTest.psm1                     — module lái host (không cần build)
examples/
  revit-smoke.ps1                     — smoke test add-in Revit, chạy được ngay
  acad-smoke.ps1                      — smoke test add-in AutoCAD, chạy được ngay
assets/
  UiAutomationToolkit/                — toolkit test UI (FlaUI), dùng cho mọi app
                                         WPF/WinForms — xem README riêng bên trong
```

## Lưu ý khi sửa file trong repo

`scripts/*.psm1` và `examples/*.ps1` phải lưu **UTF-8 CÓ BOM**. Windows
PowerShell 5.1 đọc file UTF-8 không BOM theo ANSI và làm hỏng **âm thầm** mọi ký
tự ngoài ASCII — phép so khớp sẽ trượt mà không báo lỗi gì. `update-skill` có
bước kiểm; xem [references/09-powershell-traps.md](references/09-powershell-traps.md).

## Đóng góp / báo lỗi

Sửa trực tiếp file trong repo này (commit + push) — người dùng chỉ cần `git pull`.
Nếu phát hiện một kỹ thuật không còn đúng (Revit/AutoCAD đổi version, rvt-mcp đổi
hành vi...), cập nhật file reference tương ứng **kèm ghi chú đã verify lại ở
version nào** — và nếu thử lại mà không tái hiện được, ghi rõ điều đó thay vì xoá
đi, như phần đính chính trong `04-ui-automation-testing.md`.
