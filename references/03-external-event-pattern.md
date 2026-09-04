# Gọi API Revit từ cửa sổ WPF modeless — ExternalEvent pattern

## Vấn đề

Cửa sổ mở bằng `.Show()` (không phải `.ShowDialog()`) chạy **modeless** — code
trong `Execute()` của command đã trả về xong, Revit tiếp tục xử lý message
loop bình thường trong khi cửa sổ vẫn mở. Bấm 1 nút trên cửa sổ đó (ví dụ
"Xoá"), code chạy trong event handler của WPF (`Button.Click`) — **không có
Revit API context hợp lệ** tại thời điểm đó. Gọi thẳng
`new Transaction(doc, "...").Start()` hoặc `doc.Delete(id)` từ đây sẽ lỗi
hoặc hành vi không xác định.

## Giải pháp chuẩn: `IExternalEventHandler` + `ExternalEvent`

1. Viết 1 `IExternalEventHandler` riêng cho mỗi hành động cần làm — property
   chứa dữ liệu cần thiết (element id, giá trị mới...), `Execute(UIApplication)`
   chứa logic thật (transaction, gọi API).
2. Trong constructor của cửa sổ: `ExternalEvent.Create(handler)` — tạo **1
   lần duy nhất**, giữ lại làm field.
3. Khi bấm nút: set property trên handler rồi gọi `.Raise()` — Revit sẽ gọi
   `handler.Execute(app)` khi nó rảnh (API context hợp lệ lúc đó).

### Ví dụ: xoá 1 element

```csharp
// Handlers/DeleteElementHandler.cs
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using System;

public class DeleteElementHandler : IExternalEventHandler
{
    public ElementId ElementId { get; set; } = ElementId.InvalidElementId;

    public event Action<ElementId>? Deleted;

    public void Execute(UIApplication app)
    {
        var document = app.ActiveUIDocument.Document;

        using var transaction = new Transaction(document, "Xoá phần tử");
        transaction.Start();
        document.Delete(ElementId);
        transaction.Commit();

        Deleted?.Invoke(ElementId);
    }

    public string GetName() => "Xoá phần tử đã chọn";
}
```

```csharp
// Views/MyWindow.xaml.cs
public partial class MyWindow : Window
{
    private readonly DeleteElementHandler _deleteHandler = new();
    private readonly ExternalEvent _deleteEvent;

    public MyWindow(/* ... */)
    {
        InitializeComponent();
        _deleteEvent = ExternalEvent.Create(_deleteHandler);
        _deleteHandler.Deleted += OnDeleted;
    }

    private void DeleteButton_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedItem is not MyItem selected) return;

        _deleteHandler.ElementId = selected.ElementId;
        _deleteEvent.Raise(); // không chạy đồng bộ — trả về ngay, Execute() chạy sau
    }

    private void OnDeleted(ElementId deletedId)
    {
        Dispatcher.Invoke(() => { /* cập nhật UI, ví dụ gỡ dòng khỏi list */ });
    }
}
```

## Vì sao mỗi hành động 1 handler riêng, không gộp chung 1 handler "đa năng"

Handler có state (property) được set trước khi `Raise()` — nếu dùng chung 1
handler cho nhiều hành động khác nhau (vừa xoá vừa đổi màu), phải thêm 1 field
kiểu "loại hành động" rồi switch trong `Execute()`, dễ nhầm lẫn và khó test
độc lập từng hành động. Tách riêng (`DeleteElementHandler`,
`ChangeColorHandler`, `ShowElementHandler`...) — mỗi handler làm đúng 1 việc,
dễ test riêng qua `revit_send_code_to_revit` (gọi thẳng `Execute(app)` trong
1 transaction test rồi rollback — xem
[05-safe-testing.md](05-safe-testing.md)).

## Pattern khác hay dùng: đổi màu / override đồ hoạ trong view hiện tại

Không đổi Material gốc (ảnh hưởng mọi view/phần tử dùng chung material) — dùng
`View.SetElementOverrides` cho **view hiện tại**, dễ hoàn tác
(`SetElementOverrides(id, new OverrideGraphicSettings())` để trả về mặc định).
Lưu ý: 1 element thường có **2 kiểu hiển thị khác nhau tuỳ view** — "Surface"
(khi nhìn thấy bề mặt, ví dụ 3D/elevation) và "Cut" (khi view cắt qua nó, ví
dụ mặt bằng/mặt cắt). Muốn chắc lên màu đúng bất kể loại view, phải set cả 2:

```csharp
var overrideSettings = new OverrideGraphicSettings()
    .SetSurfaceForegroundPatternColor(color)
    .SetSurfaceForegroundPatternId(solidFillPatternId)
    .SetCutForegroundPatternColor(color)
    .SetCutForegroundPatternId(solidFillPatternId)
    .SetProjectionLineColor(color)
    .SetCutLineColor(color);
```

(`solidFillPatternId` lấy qua
`new FilteredElementCollector(doc).OfClass(typeof(FillPatternElement)).Cast<FillPatternElement>().First(p => p.GetFillPattern().IsSolidFill).Id`.)
Đã verify thật: chỉ set Surface mà view đang ở mặt bằng (cắt qua tường) thì
**không lên màu gì cả** — vì view đó hiển thị theo Cut, không phải Surface.

## Cạm bẫy khi TEST handler qua reflection: đừng tạo instance mới

Khi verify 1 handler qua `revit_send_code_to_revit` (không qua UI thật), có 2
cách:

**Cách sai (trông có vẻ đúng, dễ bỏ sót)**: `Activator.CreateInstance(handlerType)`
tạo 1 instance MỚI rồi set property + gọi `Execute(app)` trực tiếp. Document
đổi đúng — nhưng nếu handler có `event Action<...> Changed` để cửa sổ tự cập
nhật UI (như `OnWallTypeChanged`/`OnWallDeleted`), sự kiện đó **không ai lắng
nghe** vì chỉ instance thật trong cửa sổ (`_myHandler`) mới được
`.Changed += OnXyzChanged` trong constructor. Test kiểu này chỉ verify được
phần Document, bỏ sót hoàn toàn phần đồng bộ UI — dễ báo "test xong" trong khi
UI có bug thật.

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

Sau đó, ở 1 lệnh `revit_send_code_to_revit` RIÊNG (round-trip tiếp theo — xem
lý do "không đồng bộ" ở [01-trigger-ribbon-button.md](01-trigger-ribbon-button.md)),
verify CẢ 2: Document đã đổi đúng, **VÀ** UI (danh sách/label trong cửa sổ)
cũng hiển thị đúng giá trị mới — nếu chỉ verify Document mà bỏ qua UI, coi như
chưa test đủ phần quan trọng nhất của tính năng (người dùng nhìn thấy UI, không
nhìn thấy Document trực tiếp).

## Pattern khác hay dùng: "zoom tới + chọn phần tử" khi user chọn dòng trong list

```csharp
public class ShowElementHandler : IExternalEventHandler
{
    public ElementId ElementId { get; set; } = ElementId.InvalidElementId;

    public void Execute(UIApplication app)
    {
        var uidoc = app.ActiveUIDocument;
        uidoc.ShowElements(ElementId);
        uidoc.Selection.SetElementIds(new List<ElementId> { ElementId });
    }

    public string GetName() => "Zoom tới phần tử đã chọn";
}
```

Gắn vào sự kiện `SelectionChanged` của control danh sách (DataGrid...) — chọn
dòng nào, Revit tự pan/zoom + highlight phần tử đó ngay, không cần thêm nút.
`ShowElements` chỉ thực sự di chuyển view nếu phần tử **chưa nằm trong khung
nhìn hiện tại** — nếu đã thấy sẵn thì view giữ nguyên (đúng hành vi chuẩn của
Revit khi "Show" 1 phần tử, không phải bug).
