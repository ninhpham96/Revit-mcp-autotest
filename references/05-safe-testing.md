# Khẳng định đúng chỗ, và test không phá dữ liệu thật

Hai mặt của cùng một việc: đặt khẳng định vào nguồn đáng tin, và trả mọi thứ về
nguyên trạng sau đó. Mọi kỹ thuật ở đây đều chạy trên **dữ liệu thật của người
dùng** — không có "file test riêng" tách biệt trong quy trình này.

## Luật: đừng kiểm chứng UI bằng chính UI vừa bấm

Bấm nút rồi đọc lại chính nút đó chỉ chứng minh **UI đã vẽ lại** — không chứng
minh lệnh đã chạy, càng không chứng minh nó làm đúng việc. Một binding hỏng vẫn
"trông đúng" ngay sau khi bấm.

Mỗi bước test cần một **nguồn độc lập với UI**:

| Host | Kênh | Ví dụ |
|---|---|---|
| Revit | rvt-mcp | `revit_send_code_to_revit` đọc thẳng state — [02](02-debug-log-pattern.md) |
| AutoCAD | COM | `ModelSpace.Count`, `GetVariable('USERI1')` — [08](08-autocad-com.md) |
| Bất kỳ | file | log / config / marker do chính add-in ghi ra |

```powershell
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected 1
# $r.Ok, $r.Value, $r.ElapsedMs
```

`Wait-UiState` trả về cả **thời gian** vì đó là thứ phân biệt "sai" với "chậm".
Một `Start-Sleep 2` cố định sẽ khi pass khi fail, và kết quả chập chờn đó trông
y hệt bug sản phẩm — đã mất một vòng debug thật vì chuyện này.

### Bẫy: log ghi nối tiếp qua nhiều phiên

Khẳng định "log không có dòng `[ERR]`" **fail ngay lần đầu chạy**: 10 dòng lỗi,
không dòng nào thuộc lần chạy đó — tất cả của các phiên trước, vì add-in ghi nối
tiếp vào cùng file.

→ Lấy mốc **trước** khi mở host, rồi chỉ xét dòng từ mốc đó trở đi:

```powershell
$t0 = Get-Date                      # TRƯỚC khi Start-RevitHost
# ...
$errors = @(Get-Content $LogGlob -Encoding UTF8 | Where-Object {
    ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') -and
    ([datetime]$Matches[1] -ge $t0) -and ($_ -match '\[(ERR|FTL)\]')
})
```

Cùng cách đó cho marker và số dòng: chụp giá trị nền trước, so **hiệu**, không so
giá trị tuyệt đối.

## Phục hồi — Revit, test logic thuần: Transaction + Rollback

Khi chỉ cần xác nhận một đoạn logic (thường là nội dung một
`IExternalEventHandler.Execute()` — xem
[03-external-event-pattern.md](03-external-event-pattern.md)) chạy đúng, không
cần thao tác qua UI thật:

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

Ưu điểm: nhanh, không rủi ro (rollback ngay trong cùng một lệnh
`revit_send_code_to_revit`, không bước nào có thể bị bỏ dở).
Nhược điểm: chỉ verify được đúng đoạn logic đó — không verify luồng UI thật.

## Phục hồi — Revit, test qua nút UI thật: `PostCommand(Undo)`

Khi cần verify **cả luồng UI** (bấm nút → dialog xác nhận → xử lý), bước này
commit transaction thật. Phục hồi bằng lệnh Undo chuẩn:

```csharp
var undoCmdId = RevitCommandId.LookupPostableCommandId(PostableCommand.Undo);
app.PostCommand(undoCmdId);
```

`PostCommand` chỉ **queue** — đợi một lệnh `revit_send_code_to_revit` riêng
(round-trip tiếp theo) rồi mới kiểm tra, đừng giả định đã chạy xong.

## Phục hồi — AutoCAD: `UNDO` qua COM

```powershell
Invoke-AcadCommand -Document $doc -Command "._UNDO`r1`r"
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected $before
if (-not $r.Ok) { "!! CHƯA PHỤC HỒI ĐƯỢC — dừng lại, đừng chạy tiếp" }
```

Đã verify đủ vòng: `ModelSpace` 0 → 1 → 0. Chi tiết ở [08](08-autocad-com.md).

**Gọi Undo xong không có nghĩa là đã undo.** Đọc lại state một lần nữa, ở cả hai
host.

## An toàn trên máy thật của người dùng

### Sự cố đã xảy ra

Một lần chạy harness để quên hộp thoại "+ Thêm" (`OpenFileDialog`) đang mở. Mọi
lệnh `SetValue`/bấm sau đó rơi vào chính hộp thoại đó, và nó **thêm một DLL từ
project không liên quan của người dùng vào file config thật**. Phải báo lại và
dọn tay.

Ba luật rút ra, cả ba đã đưa vào `HostUiTest.psm1`:

1. **`Close-StrayWindow` trước VÀ sau mỗi bước.** Hộp thoại bỏ quên không chỉ làm
   test sai — nó lái input đi chỗ khác. Lọc theo **class** (`#32770`), không theo
   tiêu đề: bản lọc theo tiêu đề đã đóng nhầm cửa sổ nội bộ của Revit.
2. **`Set-UiValue` bắt buộc có `-Scope`.** Lấy "ô Edit đầu tiên trong cả cửa sổ"
   chính là cách gõ nhầm vào ô tên file của hộp thoại đang mở.
3. **Kiểm kết quả thao tác hủy/gỡ bằng file, không bằng UI.** Nếu bước đó ghi vào
   config thật, phải biết ngay nó ghi cái gì.

### Đừng đổi thiết lập vĩnh viễn của máy

`Start-RevitHost` mặc định bấm **"Load Once"** trên dialog add-in chưa ký, không
phải "Always Load" — "Always Load" đổi thiết lập tin cậy **vĩnh viễn**. Chỉ dùng
`-AlwaysLoad` khi người dùng đã đồng ý.

Cùng tinh thần: đừng cài MSI, đừng sửa registry, đừng ghi vào `Program Files`
trong lúc test. Đó là quyết định của người dùng.

### Ưu tiên đóng sạch hơn kill cứng

```powershell
$doc.Close($false)                   # $false = không lưu
$acad.Quit()
```

Đã verify đóng sạch, không cần `Stop-Process`. Kill cứng để lại file khoá và
journal dở dang; chỉ dùng để dọn khi lần chạy trước chết giữa chừng.

## Dọn cửa sổ test của add-in

Nếu mở cửa sổ WPF của add-in nhiều lần để test, luôn đóng trước khi kết thúc
phiên — vừa không để rác UI cho người dùng, vừa tránh lần sau tìm nhầm cửa sổ cũ
thay vì cửa sổ mới build.

```csharp
var win = System.Windows.PresentationSource.CurrentSources
    .Cast<System.Windows.PresentationSource>()
    .Select(s => s.RootVisual)
    .OfType<System.Windows.Window>()
    .FirstOrDefault(w => w.GetType().FullName == "YourAddin.Views.MyWindow");
win?.Close();
```

Lưu ý: cửa sổ WPF giữ một `ObservableCollection` load tại thời điểm mở — nếu đã
xoá một phần tử qua chính cửa sổ đó rồi `PostCommand(Undo)` ở tầng Revit, **danh
sách trong cửa sổ KHÔNG tự đồng bộ lại** (đúng hành vi — Undo không kích hoạt lại
event của add-in). Đóng và mở lại cửa sổ sau khi Undo, đừng tưởng nhầm là bug.

## Checklist trước khi báo "test xong"

- [ ] Dữ liệu đã về đúng trạng thái ban đầu — **đếm lại**, đừng chỉ tin là đã gọi
      Undo/Rollback.
- [ ] Không còn cửa sổ test nào của add-in bị bỏ mở.
- [ ] Không còn dialog nào treo chờ input (`Get-HostWindow` liệt kê ra ngay).
- [ ] Không có thay đổi vĩnh viễn nào trên máy người dùng (tin cậy add-in, config,
      registry).
- [ ] Khẳng định dựa trên nguồn ngoài UI, và có chặn mốc thời gian nếu đọc log.

## Báo kết quả trung thực

Nếu host không mở được, hoặc không có kênh state nào sống, **nói thẳng là chưa
test được** — đừng báo "xong" khi mới chỉ build sạch.

Và khi harness tự gây ra thay đổi ngoài ý muốn trên máy người dùng, báo lại ngay
kèm đúng thứ đã đổi. Chuyện đó đã xảy ra một lần rồi.
