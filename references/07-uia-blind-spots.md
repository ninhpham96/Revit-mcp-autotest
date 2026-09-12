# Điểm mù của UI Automation, và leo thang khi nào

UI Automation thấy **phần lớn** UI, không phải toàn bộ. Mỗi điểm mù dưới đây đều
gặp thật, và chúng có chung một triệu chứng — "không tìm thấy control dù nó đang
hiện rõ" — nhưng nguyên nhân và cách né khác hẳn nhau. Chẩn đoán trước, đừng
nhảy thẳng sang bấm bằng toạ độ.

## Chẩn đoán theo thứ tự

Khi UIA không thấy thứ đang hiện trên màn hình, kiểm theo đúng thứ tự này:

1. **Có dialog nào đang mở không?** `Get-HostWindow -ProcessId $pid` — một modal
   đang mở làm **toàn bộ** nội dung pane biến mất khỏi cây. Đây là nguyên nhân
   hay gặp nhất và dễ bỏ qua nhất.
2. **Cửa sổ có đang ở trước không?** WPF chỉ dựng visual tree cho phần thật sự vẽ
   ra. Nội dung trong `ScrollViewer` của cửa sổ bị che hoặc thu nhỏ có thể không
   có peer. `Set-HostForeground`.
3. **Đã phân giải lại từ gốc chưa?** Element giữ từ bước trước thành stale sau khi
   WPF dựng lại `ItemsControl`.
4. **Có phải dialog native không?** `MessageBox`, `TaskDialog`, `OpenFileDialog`
   → UIA có thể không thấy, Win32 thì thấy ngay.
5. **Đúng là không có peer thật.** Lúc này mới leo sang chuột thật.

## 1. Dialog native — UIA không thấy, Win32 thấy ngay

UIA dựng cây bằng cách gửi `WM_GETOBJECT` tới cửa sổ đích rồi chờ trả lời. Khi UI
thread của host đang lồng trong một message loop khác — đúng tình huống add-in
nạp qua dev loader — thông điệp đó không được xử lý đúng lúc, nên UIA "không
thấy" dù cửa sổ hoàn toàn bình thường ở tầng Win32.

Cả **FlaUI** lẫn **`System.Windows.Automation`** đều dính lỗi này — hai API khác
nhau nhưng dùng chung một COM interface `IUIAutomation` bên dưới, nên đổi sang
`uitest.exe` cũng không cứu được. Chỉ Win32 thô mới thấy.

→ `Get-HostWindow` / `Invoke-HostNativeButton` đi thẳng `EnumWindows` +
`EnumChildWindows` + `SendMessage(BM_CLICK)`, bỏ qua UIA cho riêng phần dialog.
Nút **chính** (nút mở ra dialog) vẫn bấm qua UIA bình thường.

Lưu ý: Win32 giữ ký tự tắt trong text của nút (`"&OK"`), nên phải bỏ `&` trước
khi so khớp.

## 2. Nút trong `DataTemplate` — không hề có peer

Trong một dockable pane WPF: nút trên thanh công cụ và các dòng log **có** peer,
nhưng nút nằm trong `DataTemplate` của thẻ thì **không bao giờ** có — lặp lại y
hệt qua nhiều lần chạy, không phải chập chờn.

→ Đây là trường hợp duy nhất buộc phải dùng **chuột thật**. Nhưng đừng hardcode
toạ độ: neo vào một phần tử *có* peer rồi tính lệch.

```powershell
$anchor = Find-UiElement -ProcessId $pid -Name 'Plugin Hub' -Type Pane
Invoke-UiClickOffset -Anchor $anchor -Dx 612 -Dy 96
```

**Vì sao không hardcode**: giữa hai lần chạy, một dòng gợi ý hiện thêm đã đẩy cả
hàng nút xuống 13 pixel. Test vẫn báo "bấm thành công" — vì nó bấm trúng *một*
nút, chỉ là nút khác.

## 3. Modal đang mở che cả cây

Một `OpenFileDialog` bỏ quên làm mọi `FindAll` trên pane trả về rỗng. Tệ hơn:
mọi thao tác gõ/bấm sau đó rơi vào chính hộp thoại đó. Xem
[05-safe-testing.md](05-safe-testing.md) — chuyện này đã ghi
nhầm dữ liệu thật vào file config.

→ `Close-StrayWindow` trước và sau mỗi bước.

**Nhưng lọc theo class, đừng lọc theo tiêu đề.** Bản đầu của hàm này lọc theo
tiêu đề và đã đóng nhầm một cửa sổ nội bộ của Revit tên `<guid>Monitor`. Host có
cửa sổ phụ riêng với tiêu đề không đoán được; class thì đoán được — `MessageBox`,
`TaskDialog`, `OpenFileDialog` đều là `#32770`.

## 4. Element stale sau khi danh sách dựng lại

Sau `ICollectionView.Refresh()`, WPF dựng lại container của `ItemsControl`. Mọi
`AutomationElement` giữ từ trước đó thành stale, và `FindAll` từ nó trả về rỗng —
**nhìn y hệt "danh sách trống"**, nên rất dễ báo nhầm thành bug sản phẩm.

→ `Find-UiElement` phân giải lại từ gốc **mỗi vòng poll**. Đừng bao giờ giữ
element qua một thao tác có thể làm danh sách đổi.

## 5. Đừng khớp theo chuỗi bị cắt

`TextTrimming="CharacterEllipsis"` làm UIA trả về chuỗi **đã bị cắt**
(`".../Release/ne..."`), nên mọi phép khớp hậu tố đều trượt.

→ Đếm/khớp theo control có tên ổn định (ví dụ nút của từng dòng), đừng theo
TextBlock đường dẫn. `Measure-UiElement` làm đúng vậy.

## 6. `Name` mơ hồ và đôi khi là rác — ưu tiên `AutomationId`

Đo thật trên ribbon AutoCAD 2027:

- Tên `"Insert"` khớp **3 phần tử khác nhau** (`Custom`, `Custom`, `Button`) —
  bấm theo tên là bấm may rủi.
- Vài nút có `Name` là **dữ liệu đường vẽ**: `'M0,4L4,0 8,4z'`, `'M0,0L4,4 8,0z'`
  (mũi tên vẽ bằng `Path`, UIA lấy luôn chuỗi hình học làm tên).
- Tab ribbon **không phải `TabItem`** — tìm theo `ControlType.TabItem` trả về
  **0 kết quả**. Chúng là `Button` với `AutomationId` ổn định: `ACAD.ID_TabHome`,
  `ACAD.ID_TabInsert`, `ACAD.ID_TabAnnotate`...

→ `Find-UiElement -AutomationId 'ACAD.ID_TabHome'`. 415/741 phần tử có
`AutomationId`; ưu tiên nó bất cứ khi nào có.

Trong app WPF của **bạn**, `x:Name` trong XAML là đủ — WPF tự expose làm
`AutomationId`, không cần set `AutomationProperties.AutomationId` thủ công.

## 7. Cây lớn dần — poll, đừng chụp một phát

Cùng một cửa sổ AutoCAD, hai lần quét cách nhau vài giây: **435** rồi **741**
phần tử. UI được realize dần. Một lần đọc kèm `Start-Sleep` cố định cho kết quả
chập chờn; poll tới khi đạt rồi báo thời gian thì phân biệt được "sai" với "chậm".

## 8. Tốc độ: chênh 32 lần

Đo trên AutoCAD 2027, cùng một cửa sổ, 3 lần mỗi cách:

| Cách | Thời gian |
|---|---|
| `FindFirst` + `AndCondition(ControlType, Name)` | **103, 93, 90 ms** |
| `FindAll(Descendants, TrueCondition)` rồi tự lọc | **3083, 3097, 3005 ms** |

Để UIA lọc ngay phía provider, đừng kéo cả cây về rồi lọc trong PowerShell. Một
vòng poll 400ms mà mỗi vòng tốn 3 giây thì không còn là poll nữa.

`Find-UiElement` tự chọn đường nhanh khi có `-AutomationId`, hoặc có đủ `-Name`
và `-Type` mà không dùng `-Match`.

## 9. Kéo-thả: dùng Explorer làm nguồn OLE

UIA không kéo-thả được, và gọi thẳng API của app đích cũng không: WPF chỉ nhận
drop khi có một OLE drag source thật đang chạy `DoDragDrop`.

**Windows Explorer chính là một OLE drag source thật.** Mở Explorer ở thư mục
chứa file rồi kéo bằng chuột thật sang cửa sổ đích — app đích không phân biệt
được với người dùng thật. `Invoke-UiDragDrop` làm đúng việc đó.

```powershell
Start-Process explorer.exe $thuMucTam
# doc toa do item qua UIA cua cua so Explorer, roi:
Invoke-UiDragDrop -FromX $fx -FromY $fy -ToX $paneX -ToY $paneY
```

### Phải dùng `SendInput`, không phải `mouse_event`

Đây là chi tiết quyết định, và mất vài vòng mới tìm ra. Bản đầu dùng
`mouse_event` + `SetCursorPos`:

- **Bấm chạy tốt** — verify được là chọn đúng file trong Explorer
  (`SelectionItemPattern.IsSelected` = True).
- **Kéo thì không bao giờ khởi động.** Explorer coi cả thao tác là một cú click,
  cửa sổ đích không nhận drop nào, và không có lỗi nào được ném ra.

Đổi sang `SendInput` là ăn ngay, không đổi gì khác. `mouse_event` đã bị Microsoft
đánh dấu superseded; module này dùng `SendInput` cho **mọi** thao tác chuột.

Ba chi tiết còn lại, thiếu cái nào drag cũng không khởi động: nhích vài pixel ngay
sau khi nhấn để vượt ngưỡng kéo (mặc định 4px); di chuyển theo **nhiều bước nhỏ**
vì OLE drag chạy trong message loop riêng của nguồn; và nhúc nhích tại đích rồi
mới nhả, để đích kịp xử lý `DragEnter`/`DragOver`.

### An toàn

Thả trượt vào một thư mục khác sẽ **di chuyển** file (cùng ổ đĩa). Luôn kéo từ một
**bản sao trong thư mục tạm**, đừng kéo file gốc trong repo.

### Và đọc log trước khi đổ lỗi cho drag

Lần thả thứ hai không làm config đổi, tôi kết luận drag hỏng và đi sửa nhầm chỗ.
Đọc log của add-in mới thấy: cú thả **đã tới nơi**, và app **cố ý từ chối** file
đó vì nó không có entry point hợp lệ. Cùng một bài học với phần đầu file này —
trạng thái app là nguồn đúng, còn "UI không đổi" thì không nói lên nguyên nhân.
