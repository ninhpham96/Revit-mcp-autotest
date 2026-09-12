# Add-in nạp qua dev loader dùng slot chung — tìm đúng nút trước khi bấm

Khi add-in KHÔNG được Revit nạp qua `.addin` của chính nó, mà qua một loader
trung gian (dev loader kiểu MiniAppLoader: gán DLL vào một "slot" ribbon tạo sẵn
lúc runtime) — kỹ thuật bấm nút ở [01](01-trigger-ribbon-button.md) vẫn đúng,
nhưng bước **tìm** đúng nút trước đó gãy theo 2 cách cụ thể. File này chỉ lo phần
tìm; bấm xong thì quay lại đúng chuỗi kỹ thuật ở `01`.

## Triệu chứng đã gặp thật

Test add-in `TestAuto` nạp qua MiniAppLoader (dev loader): bấm nút qua rvt-mcp mất
nhiều vòng dò dẫm dù `PostCommand` vẫn đúng lý thuyết. Hai nguyên nhân cụ thể:

1. **`app.GetRibbonPanels()` không tham số CHỈ thấy tab "Add-Ins"** — đây là hành
   vi tài liệu chính thức của Revit API, không phải giới hạn của kỹ thuật ở `01`.
   Dev loader tạo tab riêng (`"MiniApps"`), nên snippet mặc định không thấy add-in
   dù nó đã nạp thật trong process — xác nhận được qua
   `AppDomain.CurrentDomain.GetAssemblies()`.
2. **Nút do dev loader tạo là slot chung, tên generic/đánh số**
   (`GenericCommand00`..`15`), không tự nói lên slot nào đang giữ add-in nào.
   Đọc `Text`/`Name` qua `m_RibbonItem` (kỹ thuật ở `01`) trả về **RỖNG** riêng
   cho loại nút này — dễ hiểu nhầm thành "nút không dùng được", trong khi nó
   dùng `PostCommand` bình thường một khi đã biết đúng slot.

## Quy trình 5 bước — đã verify thật

### 1. Xác nhận loader-assembly và add-in-assembly cùng có trong process

```csharp
var names = AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetName().Name).ToList();
return string.Join("\n", names);
```

`AppDomain.CurrentDomain.GetAssemblies()` trên .NET Core/8+ liệt kê assembly từ
**mọi** `AssemblyLoadContext` trong process, không chỉ Default — nên loader
assembly (nạp trong ALC riêng của nó) vẫn hiện ra ở đây.

Chưa biết tên loader trước: đối chiếu với các `<AddIn Type="Application">` khai
trong file `.addin` ở `%APPDATA%\Autodesk\Revit\Addins\<year>\` — assembly nào có
mặt trong process mà không phải add-in bạn đang tìm chính là ứng viên loader.

### 2. Reflect vào loader assembly, tìm singleton

```csharp
var loaderAsm = AppDomain.CurrentDomain.GetAssemblies().First(a => a.GetName().Name == "TênLoader");
var candidates = loaderAsm.GetTypes()
    .Where(t => System.Text.RegularExpressions.Regex.IsMatch(t.Name, "Host|Slot|Entry|Manager|Plugin"))
    .ToList();
return string.Join("\n", candidates.Select(t => t.FullName));
```

Lọc theo tên gợi ý trước, không cần biết tên chính xác. Tìm trong danh sách đó
một static property/field kiểu `Current`/`Instance` — đó là singleton loader dùng
để tra state runtime.

### 3. Dump generic property của singleton — đây là phần THỰC SỰ tổng quát

**Đừng hardcode tên property.** Lấy toàn bộ `GetProperties(Public | Instance)`
của singleton (và của từng phần tử trong collection nó trả về), in `Name=Value`:

```csharp
object Dump(object obj) => string.Join(", ", obj.GetType()
    .GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)
    .Select(p => { try { return $"{p.Name}={p.GetValue(obj)}"; } catch { return $"{p.Name}=<lỗi đọc>"; } }));
```

Kỹ thuật này đã lòi ra `Id`, `DllPath`, `Status` của MiniAppLoader mà không cần
đọc tài liệu trước — chỉ bằng cách dump rồi nhìn giá trị.

**Nếu một property trả về không phải kiểu nguyên thuỷ** (ví dụ singleton có
property `Slots` nhưng kiểu trả về lại là một wrapper object (`SlotPool`) chứ
chưa phải collection — bản thân wrapper đó lại có một property `Slots` khác mới
là collection thật) — lặp lại dump ở lớp đó cho tới khi ra collection. Đừng dừng
lại ở property đầu tiên tên đẹp; kiểm `GetType()` của giá trị trả về trước khi
tin nó đã là thứ cần tìm.

### 4. Đối chiếu DllPath với DLL thật

Chỉ kết luận "slot N == add-in của tôi" khi một property (thường tên `DllPath`
hoặc tương đương) khớp **đường dẫn file** thật của add-in đang tìm — lấy đường
dẫn đó từ `Assembly.Location` ở bước 1. Đừng kết luận qua trùng tên tình cờ.

### 5. Quay lại API chính thức để bấm

Một khi đã biết đúng slot (ví dụ slot có `Id="MyPlugin"` là slot số 1), quay lại
API công khai để tìm `RibbonItem` thật rồi bấm — dùng đúng chuỗi kỹ thuật đã có
ở [01](01-trigger-ribbon-button.md) (`GetRibbonPanels(tabName)` →
`item.Name` khớp tên slot → `m_RibbonItem` → `LookupCommandId` → `PostCommand`).
**Không** bấm qua route reflection-vào-loader ở các bước trên — route đó chỉ
dùng để xác định đúng nút, không phải để thay thế `PostCommand`.

## An toàn

Route reflection ở các bước 2–4 chỉ dùng để **đọc**. Đừng gọi bất kỳ method nào
tìm thấy qua `GetMethods()` của loader — một method tưởng vô hại (ví dụ trông như
getter) vẫn có thể là mutator thật (unload slot, ghi lại config...) mà không có
gì trong tên báo trước điều đó. Cùng nguyên tắc thận trọng đã nêu ở
[05-safe-testing.md](05-safe-testing.md): chỉ đọc property, việc sinh ra Hành động
thật (chạy lệnh, đổi state) đi qua đúng API công khai ở bước 5.

## Vì sao tổng quát được / vì sao không

Bước 3 (dump generic property, không hardcode tên) áp dụng được cho **bất kỳ**
dev loader nào theo mô hình slot — không riêng MiniAppLoader. Tên class cụ thể
(`PluginHost`, `SlotPool`, `DllPath`...) là của MiniAppLoader; loader khác đặt
tên khác, nhưng quy trình 5 bước giữ nguyên.

## Giới hạn

Mới verify trên MiniAppLoader. Heuristic tên type (`Host|Slot|Entry|Manager|Plugin`
ở bước 2) có thể không khớp loader khác — nếu vậy, dump toàn bộ type public
trong loader assembly rồi lọc bằng mắt thay vì regex.
