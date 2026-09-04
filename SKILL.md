---
name: revit-addin-mcp-workflow
description: >
  Quy trình phát triển + BẮT BUỘC test qua Revit thật (build sạch KHÔNG phải là
  xong) cho Revit add-in (Nice3point.Revit.Templates) có cửa sổ WPF modeless,
  điều khiển qua MCP client rvt-mcp — đúc kết từ thực chiến, mọi lỗi trong này
  đều đã verify thật. Dùng khi: sửa/thêm tính năng cho Revit add-in (thêm nút,
  đổi cột thành ComboBox, đổi logic xử lý...) — luôn tự chạy qua Revit thật
  trước khi báo hoàn thành, không dừng ở build; cần bấm 1 nút ribbon Revit từ
  code/MCP; debug command không rõ chạy tới đâu; cửa sổ WPF treo/crash khi mở
  MessageBox; gọi API Revit từ cửa sổ modeless (Show(), không ShowDialog());
  hoặc tự động hoá test UI (bấm nút, chọn dòng, xác nhận dialog) không cần
  chuột thật. Áp dụng mọi Revit add-in dùng Nice3point.Revit.Templates.
---

# Revit Add-in + MCP: quy trình dev & test tự động

Skill này gói lại toàn bộ bài học từ 1 phiên làm việc thực tế xây + test 1 Revit
add-in qua [rvt-mcp](https://github.com/bimwright/rvt-mcp) (MCP client cho Revit).
Mỗi kỹ thuật dưới đây đều đã **verify bằng cách chạy thật trên Revit**, kể cả những
lần thất bại (Revit treo, phải nhờ người dùng bấm tay giải cứu) — giữ nguyên phần
"tại sao" để không lặp lại đúng những lỗi đó.

## Bắt buộc: build sạch KHÔNG có nghĩa là xong

Đây là điều dễ bỏ sót nhất khi dùng skill này, và đã từng bỏ sót thật: sửa
code + `dotnet build` thành công **chỉ chứng minh code hợp lệ về mặt cú
pháp/kiểu dữ liệu** — không chứng minh tính năng chạy đúng. Ví dụ thật đã gặp:
1 tính năng "đổi loại tường qua ComboBox" build sạch, mở cửa sổ không crash,
nhưng khi thực sự test mới lộ ra chỗ dễ nhầm — verify bằng cách tạo 1 instance
`IExternalEventHandler` MỚI qua reflection để gọi `Execute()` trực tiếp
**trông có vẻ đúng** (Document đổi type thật) nhưng **UI không tự cập nhật**,
vì sự kiện `Changed` chỉ có người nghe (`OnXyzChanged`) khi raise qua ĐÚNG
instance handler đã được wire trong constructor cửa sổ — instance mới tạo
không có ai subscribe. Chỉ phát hiện ra vì đã tự so sánh Document vs UI sau
khi đổi, không dừng lại ở "không có exception".

**Sau MỖI lần sửa code (tính năng mới, sửa bug, refactor có ảnh hưởng hành
vi), coi task chỉ thực sự xong khi đã làm đủ các bước sau — không phải khi
build sạch:**

1. Build sạch (`dotnet build ... -c Debug.R2x`).
2. Bấm nút ribbon qua MCP để chạy tính năng với đúng DLL mới build —
   [01-trigger-ribbon-button.md](references/01-trigger-ribbon-button.md).
3. Xác nhận qua `DebugLog` + đọc trực tiếp state qua `revit_send_code_to_revit`
   rằng tính năng cho **đúng kết quả mong đợi** — so sánh giá trị trước/sau,
   không chỉ "không crash" —
   [02-debug-log-pattern.md](references/02-debug-log-pattern.md).
4. Nếu tính năng gọi API Revit qua `ExternalEvent`
   ([03-external-event-pattern.md](references/03-external-event-pattern.md)):
   khi test, luôn lấy **đúng field private handler/event của cửa sổ đang mở**
   (`GetField("_tênField", BindingFlags.NonPublic | BindingFlags.Instance)`)
   để set property + `Raise()` — **đừng** `Activator.CreateInstance` 1 handler
   mới, event `Changed`/tương tự sẽ không có ai lắng nghe, dễ tưởng nhầm là
   test đủ trong khi UI không được verify thật.
5. Nếu tính năng có UI thao tác (nút, chọn dòng, sửa cell...), verify qua
   UiAutomationToolkit khi khả thi, hoặc qua cách (4) khi thao tác UI đó chưa
   có sẵn tool tự động (ví dụ sửa cell ComboBox trong DataGrid) —
   [04-ui-automation-testing.md](references/04-ui-automation-testing.md).
6. Phục hồi dữ liệu Revit về nguyên trạng, rồi **đọc lại state 1 lần nữa để
   xác nhận đã phục hồi đúng** — đừng chỉ tin đã gọi Undo/set lại giá trị cũ —
   [05-safe-testing.md](references/05-safe-testing.md).

Nếu không có kết nối MCP tới 1 phiên Revit đang chạy (không có target khả
dụng để test), nói thẳng với người dùng rằng chưa test được qua Revit thật —
đừng báo "xong"/"hoàn thành" như thể đã verify khi chỉ mới build sạch.

## Khi nào đọc file tham khảo nào

| Tình huống | Đọc |
|---|---|
| Cần bấm 1 nút ribbon Revit từ MCP (không phải người dùng bấm) | [references/01-trigger-ribbon-button.md](references/01-trigger-ribbon-button.md) |
| Cần biết command đã chạy tới đâu, lỗi ở bước nào (không đoán qua exception) | [references/02-debug-log-pattern.md](references/02-debug-log-pattern.md) |
| Cửa sổ WPF modeless cần gọi Document.Delete/bất kỳ API Revit nào khi bấm nút | [references/03-external-event-pattern.md](references/03-external-event-pattern.md) |
| Cần test tự động UI (bấm nút, chọn dòng, xác nhận dialog) không cần chuột thật | [references/04-ui-automation-testing.md](references/04-ui-automation-testing.md) |
| Test có đụng vào dữ liệu Revit thật (xoá/sửa element) — làm sao không phá model | [references/05-safe-testing.md](references/05-safe-testing.md) |

## Bức tranh tổng quan

1. **Bấm nút ribbon qua MCP** (`01-trigger-ribbon-button.md`) → mở cửa sổ WPF của add-in.
2. **Xác nhận đã chạy tới đâu** (`02-debug-log-pattern.md`) → đọc file log, không đoán qua exception hay query state WPF từ thread khác.
3. Cửa sổ WPF gọi API Revit qua **ExternalEvent** (`03-external-event-pattern.md`) — không được gọi thẳng vì cửa sổ modeless không có API context hợp lệ.
4. **Test tự động UI thật** bằng UiAutomationToolkit (`04-ui-automation-testing.md`) — chạy như 1 process tách biệt, xử lý được cả dialog native mà UI Automation "không thấy".
5. Mọi thao tác test đụng dữ liệu thật đều **phục hồi ngay sau đó** (`05-safe-testing.md`) — Transaction Rollback khi test logic thuần, `PostCommand(Undo)` khi test qua nút UI thật.

## Ghi chú quan trọng: rvt-mcp là open source

[rvt-mcp](https://github.com/bimwright/rvt-mcp) là mã nguồn mở. Nếu gặp giới hạn
của bộ tool có sẵn (thiếu 1 tool cụ thể, hành vi không như ý), **có thể clone về
sửa/mở rộng cho phù hợp** — không bị khoá cứng vào bản build sẵn. Đây chính xác là
cách các kỹ thuật `PostCommand`/`revit_send_code_to_revit` trong skill này được
khai thác: dùng tool "escape hatch" sẵn có (`revit_send_code_to_revit`) của
rvt-mcp để làm những việc không có tool riêng.

## Áp dụng cho project khác

Mọi pattern trong skill này viết theo kiểu **template độc lập với 1 project cụ
thể** — không giả định tên class/namespace nào ngoài quy ước chuẩn của
Nice3point.Revit.Templates (`ExternalCommand`, `.addin` manifest...). Khi áp dụng:
đổi tên class/namespace theo project của bạn, phần logic giữ nguyên.

`UiAutomationToolkit` (dùng ở bước 4) được đóng gói sẵn toàn bộ source trong
[assets/UiAutomationToolkit](assets/UiAutomationToolkit) — copy nguyên thư mục đó
ra ngoài, `dotnet build`, là dùng được ngay cho bất kỳ project nào, không riêng
Revit.
