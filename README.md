# revit-addin-mcp-workflow

Claude Code skill: quy trình phát triển + **bắt buộc test qua Revit thật**
(không chỉ build sạch) cho Revit add-in dùng
[Nice3point.Revit.Templates](https://github.com/Nice3point/RevitTemplates),
điều khiển qua MCP client [rvt-mcp](https://github.com/bimwright/rvt-mcp).
Đúc kết từ 1 phiên làm việc thực tế — mọi kỹ thuật, mọi lỗi trong này đều đã
verify bằng cách chạy thật trên Revit, không phải lý thuyết. Chi tiết đầy đủ
nằm trong [SKILL.md](SKILL.md) và các file trong [references/](references).

## Cài đặt (lần đầu)

Skill cài ở **cấp user** — dùng được cho mọi Revit add-in project trên máy đó,
không riêng 1 project cụ thể.

```bash
git clone https://github.com/ninhpham96/Revit-mcp-autotest.git ~/.claude/skills/revit-addin-mcp-workflow
```

Windows PowerShell:

```powershell
git clone https://github.com/ninhpham96/Revit-mcp-autotest.git $env:USERPROFILE\.claude\skills\revit-addin-mcp-workflow
```

Build sẵn `UiAutomationToolkit` (bundle trong `assets/`, dùng để tự động hoá
test UI qua Revit thật — xem [references/04-ui-automation-testing.md](references/04-ui-automation-testing.md)):

```bash
cd ~/.claude/skills/revit-addin-mcp-workflow/assets/UiAutomationToolkit
dotnet build
```

Mở 1 phiên **Claude Code mới** (danh sách skill chỉ nạp lúc khởi động phiên,
skill vừa cài sẽ không xuất hiện ở phiên đang mở sẵn) — vậy là xong.

## Yêu cầu trước khi dùng

- **[rvt-mcp](https://github.com/bimwright/rvt-mcp)** đã cài và kết nối được
  với Revit đang chạy (đây là kênh Claude dùng để điều khiển Revit).
- **.NET SDK** (để build add-in và `UiAutomationToolkit`).
- Revit add-in đang phát triển dùng `Nice3point.Revit.Templates` — nếu dùng
  template khác, phần lớn kỹ thuật vẫn áp dụng được nhưng cần đọc kỹ
  [references/01-trigger-ribbon-button.md](references/01-trigger-ribbon-button.md)
  để đối chiếu cách command được đăng ký trong project của bạn.

## Cách dùng

Skill tự trigger khi làm việc trong Claude Code và nhắc tới các tình huống
liên quan (sửa/thêm tính năng Revit add-in, bấm nút ribbon qua MCP, debug
command không rõ chạy tới đâu, cửa sổ WPF treo khi mở dialog, test UI tự động
không cần chuột thật...) — không cần gọi thủ công. Ví dụ 1 câu lệnh thực tế:

```
/revit-addin-mcp-workflow thêm nút xuất danh sách tường ra Excel, test luôn
```

Claude sẽ tự đọc [SKILL.md](SKILL.md), theo đúng quy trình: sửa code → build
→ bấm nút ribbon qua MCP để chạy thử với DLL mới → verify kết quả thật (không
dừng ở "build sạch") → nếu có thao tác UI thì test qua `UiAutomationToolkit`
→ phục hồi dữ liệu Revit về nguyên trạng trước khi báo hoàn thành.

## Cập nhật khi skill có bản mới

```bash
cd ~/.claude/skills/revit-addin-mcp-workflow
git pull
```

Nếu `assets/UiAutomationToolkit` có thay đổi, build lại:

```bash
cd assets/UiAutomationToolkit && dotnet build
```

## Cấu trúc repo

```
SKILL.md                              — nội dung chính, Claude đọc khi skill trigger
references/
  01-trigger-ribbon-button.md         — bấm nút ribbon Revit từ MCP (PostCommand)
  02-debug-log-pattern.md             — xác nhận command chạy tới đâu (DebugLog)
  03-external-event-pattern.md        — gọi API Revit từ cửa sổ WPF modeless
  04-ui-automation-testing.md         — test UI tự động, không cần chuột thật
  05-safe-testing.md                  — test không phá dữ liệu Revit thật
assets/
  UiAutomationToolkit/                — toolkit test UI (FlaUI), dùng được
                                         cho cả app WPF/WinForms khác, không
                                         riêng Revit — xem UiAutomationToolkit/README.md
```

## Đóng góp / báo lỗi

Sửa trực tiếp file trong repo này (commit + push) — mọi người dùng skill chỉ
cần `git pull` để nhận bản mới, không cần cài lại từ đầu. Nếu phát hiện 1 kỹ
thuật trong skill không còn đúng (Revit đổi version, rvt-mcp đổi hành vi...),
cập nhật lại file reference tương ứng kèm ghi chú đã verify lại ở version nào.
