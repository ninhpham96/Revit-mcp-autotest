# Test cửa sổ WPF: `.Show()` (modeless) khác `.ShowDialog()` (modal) thế nào

> **File này chỉ nói cách TEST một cửa sổ đã tồn tại, không phải quy tắc bạn
> phải viết code theo.** Đọc code hiện có để biết nó đang mở kiểu nào và đã
> dùng cơ chế gì, rồi test đúng theo cái ĐANG CÓ. Đừng lấy nội dung này làm lý
> do tự ý sửa/refactor code người dùng sang một pattern khác khi họ không yêu
> cầu việc đó.

## Vì sao hai kiểu cửa sổ cần test khác nhau — bối cảnh

**`.Show()` (modeless)**: `Execute()` của command đã trả về xong, Revit tiếp
tục xử lý message loop bình thường trong khi cửa sổ vẫn mở. Code chạy trong
event handler của WPF (`Button.Click`) lúc đó **không có Revit API context hợp
lệ** — nếu code gọi thẳng `new Transaction(doc, "...").Start()` hay
`doc.Delete(id)` ngay trong handler đó, sẽ lỗi hoặc hành vi không xác định. Vì
vậy cửa sổ modeless thường (không phải luôn luôn — tuỳ code có sẵn) đi qua
`IExternalEventHandler` + `ExternalEvent`: nút bấm chỉ set property rồi gọi
`.Raise()`, Revit gọi lại `Execute(app)` sau đó khi nó rảnh — nghĩa là **không
đồng bộ**, không có cách nào biết chắc lệnh đã chạy xong ngay trong cùng một
lời gọi.

**`.ShowDialog()` (modal)**: chặn ngay trên chính thread đã gọi nó (thường là
main thread của Revit, nếu `ShowDialog()` được gọi từ trong `Execute()`) bằng
một nested message loop. Code trong handler nút của dialog đó vẫn chạy trên
đúng thread, vẫn có API context hợp lệ — gọi thẳng `Transaction` từ đây là
bình thường, **không cần** `ExternalEvent`. Nhưng đổi lại, trong khi dialog còn
mở, thread đó bị chiếm — mọi cơ chế tự động hoá khác cần chạy trên cùng thread
(round-trip `revit_send_code_to_revit` khác, `Idling`, hàng đợi reload...) đều
bị **hoãn lại** cho tới khi dialog đóng. Đã verify hiện tượng này khi test
MiniAppLoader: reload bị hoãn (không nạp) trong lúc Revit đang kẹt 1 modal
dialog, và chạy ngay sau khi dialog đóng.

## Test khi cửa sổ mở bằng `.Show()` (modeless)

**Nếu code đã dùng `IExternalEventHandler` + `ExternalEvent`** (cách phổ biến
nhất cho modeless) — xem mục "Cạm bẫy khi TEST qua reflection" ngay dưới, đây
là phần quan trọng nhất của file này.

**Nếu không rõ code dùng cơ chế gì**, hoặc bấm nút xong thấy lỗi lạ: đọc
`DebugLog` (xem [02](02-debug-log-pattern.md)) để biết exception thật là gì,
thay vì đoán. Một `NullReferenceException`/exception về API context ngay khi
bấm nút trên cửa sổ modeless là dấu hiệu code đang gọi API Revit trực tiếp từ
handler mà không qua `ExternalEvent` — đây là **thông tin để hiểu triệu chứng
đang thấy**, không phải kết luận "phải sửa lại".

### Cạm bẫy khi TEST qua reflection: đừng tạo instance mới

Khi verify 1 handler qua `revit_send_code_to_revit` (không qua UI thật), có 2
cách:

**Cách sai (trông có vẻ đúng, dễ bỏ sót)**: `Activator.CreateInstance(handlerType)`
tạo 1 instance MỚI rồi set property + gọi `Execute(app)` trực tiếp. Document
đổi đúng — nhưng nếu handler có `event Action<...> Changed` để cửa sổ tự cập
nhật UI, sự kiện đó **không ai lắng nghe** vì chỉ instance thật trong cửa sổ
mới được `.Changed += OnXyzChanged` lúc constructor chạy. Test kiểu này chỉ
verify được phần Document, bỏ sót hoàn toàn phần đồng bộ UI — dễ báo "test
xong" trong khi UI có bug thật.

**Cách đúng**: lấy đúng field private của handler + `ExternalEvent` đã được
wire sẵn trong cửa sổ đang mở, qua reflection:

```csharp
var win = /* tìm cửa sổ qua PresentationSource.CurrentSources, xem 04 */;
var winType = win.GetType();

var handlerField = winType.GetField("_myHandler", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var eventField = winType.GetField("_myEvent", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var realHandler = handlerField.GetValue(win);
var realEvent = eventField.GetValue(win);

realHandler.GetType().GetProperty("ElementId").SetValue(realHandler, someId);
realEvent.GetType().GetMethod("Raise").Invoke(realEvent, null); // không đồng bộ — kiểm tra ở lệnh SAU
```

Sau đó, ở 1 lệnh `revit_send_code_to_revit` RIÊNG (round-trip tiếp theo — vì
`.Raise()` không đồng bộ, xem [01](01-trigger-ribbon-button.md)), verify CẢ 2:
Document đã đổi đúng, **VÀ** UI (danh sách/label trong cửa sổ) cũng hiển thị
đúng giá trị mới. Chỉ verify Document mà bỏ qua UI là chưa test đủ phần quan
trọng nhất (người dùng nhìn thấy UI, không nhìn thấy Document trực tiếp).

## Test khi cửa sổ mở bằng `.ShowDialog()` (modal)

Bấm nút xong verify **ngay trong cùng một lời gọi** — không cần round-trip 2
lệnh như trên, vì không có `ExternalEvent.Raise()` bất đồng bộ ở giữa (miễn là
code không tự thêm cơ chế bất đồng bộ khác).

**Nhưng bản thân modal lại chặn automation ở một tầng khác**: trong lúc dialog
còn mở, `revit_send_code_to_revit` gọi tiếp có thể không chạy được / phải chờ,
và cây UIA có thể "biến mất" phần nội dung phía sau (xem điểm 1 ở
[07-uia-blind-spots.md](07-uia-blind-spots.md): *"có dialog nào đang mở
không?"*). Muốn bấm nút bên trong chính dialog đó: dùng đúng route cho loại
dialog — dialog native (`MessageBox`, `TaskDialog`) thì qua Win32
`BM_CLICK` (`Invoke-HostNativeButton` trong `HostUiTest.psm1`,
[06](06-host-lifecycle.md)), dialog WPF thật thì qua UIA/`PostCommand` như
bình thường. Luôn `Close-StrayWindow` trước/sau khi xong (xem
[05-safe-testing.md](05-safe-testing.md)) — một dialog bị bỏ quên mở sẽ chặn
mọi bước test sau đó, không riêng gì round-trip MCP.

## Vì sao mỗi hành động 1 handler riêng, không gộp chung 1 handler "đa năng"

Đây là quan sát về code hay gặp, không phải yêu cầu: handler có state (property)
được set trước khi `Raise()` — nếu 1 handler dùng chung cho nhiều hành động
khác nhau, nó cần thêm 1 field kiểu "loại hành động" rồi switch trong
`Execute()`. Khi gặp code như vậy, test riêng từng nhánh hành động một, đừng
gộp chung một lượt "test tất cả" — dễ bỏ sót nhánh không được set đúng field
loại hành động.
