# Kích hoạt 1 nút ribbon Revit từ MCP

Dùng khi cần bấm 1 nút ribbon cụ thể (của add-in đang phát triển, hoặc bất kỳ
add-in nào khác đang chạy trong cùng phiên Revit) từ tool `revit_send_code_to_revit`
của rvt-mcp — đúng như người dùng bấm chuột hoặc nhấn phím tắt thật.

## Bối cảnh

`revit_send_code_to_revit` compile + chạy C# tuỳ ý ngay trong tiến trình Revit
(có sẵn biến `doc`, `uidoc`, `app`). Không có tool riêng kiểu
`revit_click_ribbon_button`, nên muốn bấm 1 nút cụ thể phải tự viết code qua
tool này.

## 2 cách KHÔNG hoạt động (đã thử thật, khỏi thử lại)

### 1. `RevitCommandId.LookupCommandId(fullyQualifiedClassName)`

```csharp
var cmdId = RevitCommandId.LookupCommandId("MyAddin.Commands.MyCommand");
// => null nếu nút được tạo programmatic bởi 1 loader khác, không qua .addin manifest
```

Chỉ hoạt động nếu command được đăng ký đúng qua file `.addin` (`<AddIn Type="Command">`)
— `LookupCommandId` theo tên class chỉ tìm thấy command đã đăng ký qua manifest,
không tìm thấy nút do 1 loader khác tạo runtime qua `PushButtonData` (ví dụ khi
đang dev, add-in được nạp qua 1 dev loader như "Mini AppLoader" thay vì
`.addin` chính chủ).

### 2. Reflection gọi thẳng `Execute()`

```csharp
var cmd = (IExternalCommand)Activator.CreateInstance(type);
cmd.Execute(null, ref message, null); // commandData giả bằng null
```

**Crash** (`NullReferenceException`) nếu command kế thừa
`Nice3point.Revit.Toolkit.External.ExternalCommand` (chuẩn của
Nice3point.Revit.Templates) — base class này tự đọc dữ liệu thật từ
`ExternalCommandData` ngay trong `Execute()`. `ExternalCommandData` là object
Revit tạo nội bộ qua interop không quản lý, **không có constructor public** —
không thể giả bằng code.

## Cách hoạt động: `PostCommand` với ID nội bộ thật

Chìa khoá: mọi `RibbonItem` Revit tạo ra (kể cả nút programmatic) đều có 1 ID
nội bộ dạng chuỗi, **khác** với tên class — đây cũng chính là ID mà Revit dùng
khi gán phím tắt qua Keyboard Shortcuts editor.

### Bước 1 — Tìm `RibbonItem` theo tên panel/nút

```csharp
var panels = app.GetRibbonPanels();
RibbonItem target = null;
foreach (var p in panels)
    foreach (var item in p.GetItems())
        if (p.Name == "TênPanel" && item.Name == "TênNút") target = item;
```

**`GetRibbonPanels()` không tham số CHỈ thấy tab "Add-Ins"** — hành vi tài liệu
chính thức của Revit API, không phải giới hạn của kỹ thuật này. Add-in nằm ở tab
khác (kể cả tab do add-in/dev loader tự tạo) sẽ không xuất hiện trong `panels`
ở trên dù nó đã nạp thật. Hai cách đúng:

- **Cách A** (đã biết tên tab): `app.GetRibbonPanels("TênTab")`.
- **Cách B** (chưa biết tên tab): liệt kê toàn bộ
  `Autodesk.Windows.ComponentManager.Ribbon.Tabs` → panel → item — xem snippet
  dump đầy đủ ở cuối mục này.

Nếu add-in được nạp qua một dev loader dùng slot ribbon chung (nút tên
generic/đánh số, không phải tên add-in) thì còn một bước nữa TRƯỚC khi tới đây:
xác định đúng slot nào đang giữ add-in của bạn — xem
[10-dynamic-loader-resolution.md](10-dynamic-loader-resolution.md).

### Bước 2 — Lấy ID nội bộ qua reflection

`Autodesk.Revit.UI.RibbonItem` (base class của `PushButton`) giữ 1 field
private `m_RibbonItem` kiểu `Autodesk.Windows.RibbonItem` — object UI
framework thật bên dưới (namespace `Autodesk.Windows`, không phải
`Autodesk.Revit.UI` công khai). Property `Id` của object này mới là ID mà
`RevitCommandId.LookupCommandId` cần:

```csharp
var f = typeof(RibbonItem).GetField("m_RibbonItem",
    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var adItem = f.GetValue(target);
string internalId = (string)adItem.GetType().GetProperty("Id").GetValue(adItem);
// => "CustomCtrl_%CustomCtrl_%<TabName>%<PanelName>%<ButtonName>"
```

### Bước 3 — `LookupCommandId` + `PostCommand`

```csharp
var cmdId = RevitCommandId.LookupCommandId(internalId);
if (cmdId != null) app.PostCommand(cmdId);
```

`PostCommand` đẩy lệnh vào **hàng đợi command của Revit** — thực thi ngay sau
khi context code hiện tại (đoạn `revit_send_code_to_revit`) kết thúc, đi qua
**đúng pipeline chính thức**: Revit tự tạo `ExternalCommandData` hợp lệ rồi
gọi `Execute()` — y hệt khi người dùng bấm chuột hoặc nhấn phím tắt thật.

## Code đầy đủ (gộp 3 bước)

```csharp
var panels = app.GetRibbonPanels();
RibbonItem target = null;
foreach (var p in panels)
    foreach (var item in p.GetItems())
        if (p.Name == "TênPanel" && item.Name == "TênNút") target = item;

if (target == null) return "Không tìm thấy nút";

var f = typeof(RibbonItem).GetField("m_RibbonItem",
    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var adItem = f.GetValue(target);
string internalId = (string)adItem.GetType().GetProperty("Id").GetValue(adItem);

var cmdId = RevitCommandId.LookupCommandId(internalId);
if (cmdId == null) return $"LookupCommandId thất bại với Id='{internalId}'";

app.PostCommand(cmdId);
return $"Đã queue PostCommand cho '{target.Name}' (Id={internalId})";
```

Mẹo tìm đúng tên panel: liệt kê hết trước khi bấm, để biết chính xác `p.Name`/`item.Name`:

```csharp
var panels = app.GetRibbonPanels();
var items = new List<string>();
foreach (var p in panels)
    foreach (var item in p.GetItems())
        items.Add($"Panel='{p.Name}' Item='{item.Name}' Type={item.GetType().Name}");
return string.Join("\n", items);
```

## Giới hạn / lưu ý

- **Nút do dev loader tạo bằng slot chung có thể trả `Text`/`Name` RỖNG**
  qua `m_RibbonItem` — đây là điểm mù riêng của loại nút này, đừng kết luận
  "nút không dùng được". Tên đáng tin cậy là `item.Name` từ
  `RibbonPanel.GetItems()` (API công khai). Cần biết slot nào đang giữ add-in
  nào thì xem [10-dynamic-loader-resolution.md](10-dynamic-loader-resolution.md).
- Dựa vào field private `m_RibbonItem` và type nội bộ
  `Autodesk.Windows.RibbonButton` — **API không công bố chính thức**. Autodesk
  có thể đổi cấu trúc field này ở version khác mà không báo trước — đã verify
  trên **Revit 2024.3**. Nếu lỗi, kiểm tra lại field name qua reflection trước.
- `PostCommand` chỉ **queue** lệnh, không chạy đồng bộ ngay trong lời gọi —
  không có cách nào từ `revit_send_code_to_revit` biết chắc lệnh đã chạy xong
  hay chưa/kết quả ra sao (không có return value). Muốn xác nhận, xem
  [02-debug-log-pattern.md](02-debug-log-pattern.md).
- Nếu nút đích **đang bị disable** (`IsEnabled = false`, ví dụ do
  `IExternalCommandAvailability` chặn trong context hiện tại), `PostCommand`
  sẽ không làm gì — không throw, không báo lỗi.
- Không dùng nếu command cần **user tương tác trong lúc chạy** (pick point
  trên màn hình, chọn element bằng chuột...) — `PostCommand` vẫn chạy UI thật
  của Revit nên các dialog/pick-point vẫn hiện ra bình thường và **chờ người
  dùng thao tác**, chỉ là bước "bấm nút" được tự động hoá.
- Cách này **không** phải automation ở tầng OS (không mô phỏng chuột/bàn
  phím vật lý) — nó dùng đúng API `PostCommand` mà Autodesk cung cấp để gọi
  command theo chương trình, chỉ khác là tìm `RevitCommandId` bằng ID nội bộ
  thay vì tên class.
- Nếu command được đăng ký bình thường qua `.addin` (không qua dev loader),
  `RevitCommandId.LookupCommandId` theo tên class (cách 1 ở trên) rất có thể
  hoạt động luôn, đơn giản hơn — thử cách đó trước, nếu thất bại mới quay lại
  kỹ thuật ID nội bộ này (chắc chắn hoạt động bất kể command đăng ký kiểu gì).
