---
name: revit-cad-addin-autotest
description: >
  Quy trình phát triển + BẮT BUỘC test qua host thật (build sạch KHÔNG phải là
  xong) cho add-in Revit và AutoCAD: tự mở app, vượt dialog khởi động, chạy lệnh,
  bấm nút, rồi khẳng định bằng trạng thái thật của app chứ không bằng chính UI
  vừa bấm. Mọi kỹ thuật đều đã verify bằng cách chạy thật. Dùng khi: sửa/thêm
  tính năng cho add-in Revit hoặc AutoCAD và cần tự test trước khi báo xong; cần
  bấm một nút ribbon Revit từ code/MCP; cần chạy lệnh AutoCAD và đọc lại model để
  kiểm chứng; debug command không rõ chạy tới đâu; cửa sổ WPF modeless treo/crash
  khi gọi API Revit; UI Automation "không tìm thấy" control dù nó đang hiện rõ;
  cần bấm control không có peer UIA; dialog khởi động của host chặn test tự động;
  test UI cho kết quả chập chờn lúc pass lúc fail; hoặc script PowerShell của
  harness hỏng dấu tiếng Việt. Áp dụng cho cả app WPF/WinForms desktop khác.
---

# Test tự động add-in Revit & AutoCAD qua host thật

Skill này gói lại bài học từ nhiều phiên làm việc thực tế: xây + test một Revit
add-in qua [rvt-mcp](https://github.com/bimwright/rvt-mcp), và lái Revit/AutoCAD
từ bên ngoài bằng UI Automation + chuột thật.

**Mọi kỹ thuật dưới đây đều đã verify bằng cách chạy thật**, kể cả những lần thất
bại (Revit treo, phải nhờ người dùng bấm tay giải cứu) — giữ nguyên phần "tại
sao" để không lặp lại đúng những lỗi đó. Chỗ nào chưa verify thì ghi rõ là chưa.

## Luật số một, hai tầng

> **Khẳng định phải dựa vào nguồn độc lập với thứ đang được test.**

**Tầng 1 — build sạch KHÔNG phải là xong.** `dotnet build` thành công chỉ chứng
minh code hợp lệ về cú pháp/kiểu dữ liệu. Ví dụ thật: một tính năng "đổi loại
tường qua ComboBox" build sạch, mở cửa sổ không crash, nhưng verify bằng cách tạo
một `IExternalEventHandler` MỚI qua reflection **trông có vẻ đúng** (Document đổi
type thật) mà **UI không hề cập nhật** — vì sự kiện `Changed` chỉ có người nghe
khi raise qua ĐÚNG instance đã wire trong constructor cửa sổ.

**Tầng 2 — chạy được trong host thật cũng chưa phải là xong.** Bấm một nút rồi
đọc lại chính nút đó chỉ chứng minh UI đã vẽ lại. Phải đọc state từ nguồn khác:
rvt-mcp, COM của AutoCAD, hoặc file log/config do add-in ghi ra.

Nếu không có kênh nào sống (không MCP target, không mở được host), **nói thẳng là
chưa test được** — đừng báo "xong" như thể đã verify.

## Vòng lặp chuẩn sau MỖI lần sửa code

1. **Build** — `dotnet build ... -c Debug.R2x`.
2. **Mở host tới trạng thái test được** — màn hình Home của Revit ẩn ribbon,
   AutoCAD dừng ở tab Start với 0 document; cả hai đều chưa test được gì.
   `Start-RevitHost` / `Start-AutoCadHost` → [06](references/06-host-lifecycle.md).
3. **Chạy tính năng với đúng DLL vừa build** — Revit: `PostCommand` qua ID nội bộ
   → [01](references/01-trigger-ribbon-button.md). AutoCAD: COM `SendCommand`
   → [08](references/08-autocad-com.md).
4. **Xác nhận đúng kết quả mong đợi** — so giá trị **trước/sau**, không dừng ở
   "không có exception" → [02](references/02-debug-log-pattern.md),
   [05](references/05-safe-testing.md).
5. **Nếu qua `ExternalEvent`**: lấy **đúng field private của instance đang chạy**
   (`GetField(..., NonPublic | Instance)`), **đừng** `Activator.CreateInstance`
   handler mới → [03](references/03-external-event-pattern.md).
6. **Nếu có thao tác UI**: chọn công cụ theo bảng trong
   [04](references/04-ui-automation-testing.md); khi UIA "không thấy" thì chẩn
   đoán theo [07](references/07-uia-blind-spots.md) trước khi kết luận add-in hỏng.
7. **Phục hồi dữ liệu, rồi ĐỌC LẠI xác nhận đã phục hồi** →
   [05](references/05-safe-testing.md).

Hai mẫu chạy được ngay, copy về sửa:
[examples/revit-smoke.ps1](examples/revit-smoke.ps1) ·
[examples/acad-smoke.ps1](examples/acad-smoke.ps1)

```powershell
Import-Module "$env:USERPROFILE\.claude\skills\revit-cad-addin-autotest\scripts\HostUiTest.psm1"
```

## Đọc file nào khi nào — theo triệu chứng

| Tình huống | Đọc |
|---|---|
| Cần bấm một nút ribbon Revit từ MCP (không phải người dùng bấm) | [01-trigger-ribbon-button.md](references/01-trigger-ribbon-button.md) |
| Nút ribbon của add-in không thấy đâu cả (dev loader tạo tab riêng), hoặc tên nút chỉ là số/generic (`GenericCommand00`..) không biết ứng với add-in nào | [10-dynamic-loader-resolution.md](references/10-dynamic-loader-resolution.md) |
| Không biết command đã chạy tới đâu, lỗi ở bước nào | [02-debug-log-pattern.md](references/02-debug-log-pattern.md) |
| Cần test 1 cửa sổ WPF bấm nút gọi API Revit — cửa sổ modeless (`.Show()`) hay modal (`.ShowDialog()`) test khác nhau thế nào | [03-external-event-pattern.md](references/03-external-event-pattern.md) |
| Không biết nên dùng `uitest.exe`, `HostUiTest.psm1` hay MCP/COM | [04-ui-automation-testing.md](references/04-ui-automation-testing.md) |
| Sợ test phá dữ liệu thật; không biết đặt khẳng định vào đâu | [05-safe-testing.md](references/05-safe-testing.md) |
| Mở host xong test ngay thì hỏng; không biết khi nào host mới thật sự sẵn sàng | [06-host-lifecycle.md](references/06-host-lifecycle.md) |
| UIA không thấy control dù nó hiện rõ; test lúc pass lúc fail; tìm phần tử rất chậm | [07-uia-blind-spots.md](references/07-uia-blind-spots.md) |
| Làm add-in AutoCAD: chạy lệnh, đọc model, nạp DLL, hoàn tác | [08-autocad-com.md](references/08-autocad-com.md) |
| Script PowerShell hỏng dấu tiếng Việt, hoặc `if` luôn đúng một cách vô lý | [09-powershell-traps.md](references/09-powershell-traps.md) |

## Bức tranh tổng quan

**Revit** có rvt-mcp làm kênh vào tận trong process: chạy lệnh bằng `PostCommand`
với ID nội bộ, đọc state bằng `revit_send_code_to_revit`. Test một cửa sổ WPF thì
cách khác nhau tuỳ nó mở bằng `.Show()` hay `.ShowDialog()` — xem
[03](references/03-external-event-pattern.md).

**AutoCAD** không cần MCP — **COM có sẵn làm cả hai vai đó**, và đơn giản hơn:
`SendCommand` gọi thẳng tên `[CommandMethod]`, `ModelSpace`/`GetVariable` đọc
state trực tiếp. Đây là lý do add-in AutoCAD dễ test hơn Revit.

**Cả hai** dùng chung phần ngoài process: mở host và chờ đúng tín hiệu sẵn sàng,
dọn dialog còn sót, tìm/bấm control qua UIA, và rơi xuống chuột thật khi control
không có peer.

## Ba công cụ trong repo này

| | Cần build | Dùng cho |
|---|---|---|
| `scripts/HostUiTest.psm1` | không | vòng đời host, dialog khởi động, kiểm tra nhanh, chuột thật |
| `assets/UiAutomationToolkit` (`uitest.exe`) | `dotnet build` | thao tác UI phức tạp trong cửa sổ add-in (`select-row`, `click-and-confirm`) |
| rvt-mcp / COM | không | chạy lệnh + đọc state để khẳng định |

Bảng chọn chi tiết ở [04](references/04-ui-automation-testing.md).

## Ghi chú

**rvt-mcp là mã nguồn mở.** Gặp giới hạn của bộ tool có sẵn thì clone về sửa/mở
rộng — đó chính là cách các kỹ thuật `PostCommand`/`revit_send_code_to_revit`
trong skill này được khai thác.

**Áp dụng cho project khác.** Mọi pattern viết theo kiểu template độc lập với một
project cụ thể — không giả định tên class/namespace nào ngoài quy ước chuẩn của
Nice3point.Revit.Templates. Đổi tên class/namespace theo project của bạn, phần
logic giữ nguyên. `UiAutomationToolkit` và `HostUiTest.psm1` dùng được cho bất kỳ
app WPF/WinForms nào, không riêng Revit/AutoCAD.

## Giới hạn đã biết

- **Kéo-thả file** đã làm được — dùng Explorer làm nguồn OLE và `SendInput`
  ([07](references/07-uia-blind-spots.md)). `mouse_event` thì **không**: bấm chạy
  nhưng kéo không bao giờ khởi động.
- **`NETLOAD` nạp add-in AutoCAD chưa verify** trong phiên nào — mới chạy lệnh
  dựng sẵn. AutoCAD không unload assembly được, nên vòng sửa-code phải khởi động
  lại app (~20–30 giây).
- Số đo tốc độ lấy trên **một máy** (Revit 2026, AutoCAD 2027). Tỉ lệ giữa các
  cách thì ổn định, con số tuyệt đối thì không nên coi là chuẩn.
- Kỹ thuật ID nội bộ ribbon dựa vào field private `m_RibbonItem` — verify trên
  Revit 2024.3 và 2026, không có cam kết ổn định giữa các version.
- Chưa thử trên nhiều màn hình DPI khác nhau; `Invoke-UiClick` dùng toạ độ màn
  hình vật lý.
- Kỹ thuật đọc slot của dev loader ([10](references/10-dynamic-loader-resolution.md))
  phụ thuộc shape nội bộ của TỪNG loader cụ thể — verify trên MiniAppLoader,
  chưa thử loader khác.
