# Test không phá dữ liệu Revit thật

Mọi kỹ thuật ở đây đều test trên **file Revit thật của người dùng** (không có
"file test riêng" tách biệt trong quy trình này) — nên mọi bước có khả năng
đổi dữ liệu (xoá, sửa element...) đều phải phục hồi ngay sau khi verify xong,
theo 2 cách tuỳ tình huống.

## Test logic thuần (không qua nút UI thật): Transaction + Rollback

Khi chỉ cần xác nhận 1 đoạn logic (thường là nội dung 1 `IExternalEventHandler.Execute()`
— xem [03-external-event-pattern.md](03-external-event-pattern.md)) chạy đúng,
không cần thao tác qua UI thật:

```csharp
var targetId = new ElementId(38541);
var before = doc.GetElement(targetId);
if (before == null) return "Không tìm thấy phần tử để test";

using (var t = new Transaction(doc, "TEST - sẽ rollback"))
{
    t.Start();
    var deletedIds = doc.Delete(targetId);
    var during = doc.GetElement(targetId); // phải null — đã xoá trong transaction
    var result = $"Deleted count={deletedIds.Count}; during tx (null?)={during}";
    t.RollBack(); // KHÔNG Commit — trả model về nguyên trạng ngay lập tức
    var after = doc.GetElement(targetId); // phải khôi phục lại
    return result + $"; after rollback (exists?)={after != null}";
}
```

Ưu điểm: nhanh, không cần UI thật, không rủi ro (rollback ngay trong cùng 1
lệnh `revit_send_code_to_revit`, không có bước nào có thể bị bỏ dở).

Nhược điểm: chỉ verify được đúng đoạn logic đó — không verify được luồng UI
thật (nút có enable đúng lúc không, dialog xác nhận có hiện đúng không...).

## Test qua nút UI thật (cần commit thật): `PostCommand(Undo)`

Khi cần verify **cả luồng UI** (bấm nút → dialog xác nhận → xử lý), xem
[04-ui-automation-testing.md](04-ui-automation-testing.md) — dùng
`UiAutomationToolkit` để bấm nút UI thật + tự xác nhận dialog. Bước này commit
transaction thật (không rollback được từ trong handler, vì handler không biết
mình đang "được test"). Phục hồi bằng lệnh Undo chuẩn của Revit:

```csharp
var undoCmdId = RevitCommandId.LookupPostableCommandId(PostableCommand.Undo);
app.PostCommand(undoCmdId);
```

Verify lại sau đó (đếm lại số phần tử, hoặc `doc.GetElement(id) != null`) để
chắc chắn đã phục hồi đúng — đừng giả định `PostCommand` chạy xong ngay, đợi
1 lệnh `revit_send_code_to_revit` riêng (round-trip tiếp theo) mới kiểm tra,
vì `PostCommand` chỉ queue (xem
[01-trigger-ribbon-button.md](01-trigger-ribbon-button.md)).

## Dọn dẹp cửa sổ test

Nếu mở cửa sổ WPF của add-in nhiều lần để test (mỗi lần build lại DLL có thể
tạo thêm 1 instance cửa sổ nếu quên đóng cái cũ), luôn đóng cửa sổ test trước
khi kết thúc phiên — vừa để không để lại rác UI cho người dùng thật, vừa để
tránh nhầm lẫn lần test sau (tìm nhầm cửa sổ cũ còn mở thay vì cửa sổ mới vừa
mở với code mới build).

```csharp
var win = System.Windows.PresentationSource.CurrentSources
    .Cast<System.Windows.PresentationSource>()
    .Select(s => s.RootVisual)
    .OfType<System.Windows.Window>()
    .FirstOrDefault(w => w.GetType().FullName == "YourAddin.Views.MyWindow");
win?.Close();
```

Lưu ý: cửa sổ WPF của add-in giữ 1 `ObservableCollection` load tại thời điểm
mở — nếu đã xoá 1 phần tử qua chính cửa sổ đó (danh sách tự gỡ dòng), rồi sau
đó `PostCommand(Undo)` ở tầng Revit, **danh sách trong cửa sổ KHÔNG tự đồng bộ
lại** (đúng hành vi — Undo không kích hoạt lại event của add-in). Nếu cần test
tiếp trên danh sách đầy đủ, đóng cửa sổ cũ và mở lại cửa sổ mới sau khi Undo,
đừng tưởng nhầm là bug.

## Checklist trước khi báo cáo "test xong"

- [ ] Model đã về đúng số lượng/trạng thái phần tử ban đầu (đếm lại, đừng chỉ
      tin vào việc "đã gọi Undo/Rollback").
- [ ] Không còn cửa sổ test nào của add-in bị bỏ mở.
- [ ] Không còn dialog nào đang treo chờ input (kiểm tra bằng 1 lệnh
      `revit_send_code_to_revit` nhẹ, ví dụ đọc view info — nếu treo, lệnh đó
      sẽ timeout thay vì trả kết quả ngay).
