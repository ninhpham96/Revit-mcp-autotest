# AutoCAD: COM là kênh điều khiển và kiểm chứng

Bên Revit, rvt-mcp đóng hai vai: **chạy** lệnh
([01-trigger-ribbon-button.md](01-trigger-ribbon-button.md)) và **đọc state** để
khẳng định ([02-debug-log-pattern.md](02-debug-log-pattern.md)).

Bên AutoCAD không cần MCP — **COM có sẵn làm cả hai việc đó**, và đơn giản hơn
hẳn: không phải đào field private nào, không phải tra ID nội bộ của ribbon.

Đã verify đủ vòng trên **AutoCAD 2027**.

## Lấy đối tượng COM

```powershell
$acad = Get-AutoCadCom            # trong scripts/HostUiTest.psm1
```

Đừng tự gọi thẳng `Marshal.GetActiveObject` rồi dùng ngay — có hai bẫy chồng
nhau về thời điểm, mô tả đầy đủ ở
[06-host-lifecycle.md](06-host-lifecycle.md). Tóm tắt: COM phản hồi **trước khi**
dùng được, và `$null.Count` trả về `0` nên trạng thái "chưa nạp xong" trông y hệt
"sẵn sàng, chưa mở bản vẽ nào".

## Chạy lệnh: `SendCommand`

Đây là bản CAD của `PostCommand` bên Revit, nhưng **không có phần khó**: add-in
AutoCAD đăng ký lệnh bằng `[CommandMethod("MYCMD")]`, và tên đó gọi thẳng được.

```powershell
Invoke-AcadCommand -Document $doc -Command "._LINE`r0,0`r100,100`r`r"
Invoke-AcadCommand -Document $doc -Command "._MYADDINCMD`r"
```

Ba chi tiết bắt buộc:

- **`` `r `` (carriage return) kết thúc mỗi tham số** — thiếu là lệnh treo giữa
  chừng chờ nhập, và mọi khẳng định sau đó sai hết.
- **Tiền tố `_`** gọi tên lệnh theo tiếng Anh bất kể AutoCAD đang chạy ngôn ngữ
  nào. Máy này có Revit bản tiếng Nhật; đừng giả định ngôn ngữ giao diện.
- **Tiền tố `.`** buộc dùng lệnh gốc, bỏ qua bản đã bị `UNDEFINE`/định nghĩa lại.
  Một add-in khác trong cùng phiên có thể đã ghi đè lệnh đó.

### Hai hành vi của `SendCommand` sẽ cắn bạn

Dùng `Invoke-AcadCommand` chứ đừng gọi `SendCommand` trần:

```powershell
$doc = Get-AcadDocument -Application $acad     # lay MOT lan, dung suot
Invoke-AcadCommand -Document $doc -Command "._UNDO`r1`r"
```

**1. `SendCommand` CHẶN cho tới khi lệnh chạy xong.** Gửi một chuỗi thiếu tham số
thì lệnh ngồi chờ nhập và lời gọi **không bao giờ trả về**:

```powershell
$doc.SendCommand("._LINE`r0,0`r")     # moi mot diem -> treo vinh vien
```

Đo thật: treo hết 300 giây rồi phải kill AutoCAD. → Chuỗi lệnh phải **tự kết
thúc**, trả lời đủ mọi prompt.

**2. Gửi khi còn lệnh đang dở thì trượt IM LẶNG.** Cùng một script, hai lần đầu
pass, lần thứ ba `._UNDO` không có tác dụng — model vẫn giữ nguyên đối tượng vừa
tạo, không lỗi nào được ném ra. Khác biệt duy nhất: trước đó có thao tác chuột lên
ribbon.

Sysvar **`CMDACTIVE`** cho biết dòng lệnh có rảnh không — `0` là rảnh, đã verify.
`Invoke-AcadCommand` chờ `CMDACTIVE` về 0 rồi mới gửi, và **ném lỗi nếu hết giờ**
thay vì gửi bừa: biến một lần trượt im lặng thành một lần fail nhìn thấy được.

**Không huỷ được lệnh từ COM.** `SendCommand` với ký tự ESC bị AutoCAD trả
`COMException: Invalid input` — đã thử. Nên hàm này chỉ *chờ*, không tự huỷ; âm
thầm huỷ lệnh của người dùng cũng không phải việc của test harness.

### `ActiveDocument` chập chờn null lúc mới khởi động

Chỗ kiểm tra ngay sau `Start-AutoCadHost` báo có document, ba dòng sau thì chính
`$acad.ActiveDocument` trả về null. Cùng nguyên tắc với UI Automation ở
[07](07-uia-blind-spots.md): **phân giải lại, đừng tin một lần đọc**.

`Get-AcadDocument` lặp tới khi lấy được document có `Name` khác rỗng. Lấy **một
lần** rồi dùng đối tượng đó suốt, đừng viết `$acad.ActiveDocument` rải rác.

Phải có document đang mở. `Start-AutoCadHost` lo sẵn (AutoCAD dừng ở tab Start
với 0 document).

### Nạp DLL add-in đang dev

Lệnh `NETLOAD` nạp assembly .NET vào phiên đang chạy:

```powershell
Invoke-AcadCommand -Document $doc -Command "._NETLOAD`rD:\dev\MyAddin\bin\Debug\MyAddin.dll`r"
```

> **Chưa verify trong phiên này** — mới chỉ chạy lệnh dựng sẵn của AutoCAD, chưa
> nạp add-in tự viết. AutoCAD **không** cho unload assembly đã nạp, nên vòng lặp
> sửa-code phải khởi động lại AutoCAD; `Stop-HostApp` + `Start-AutoCadHost` làm
> việc đó, đo được ~20–30 giây mỗi vòng.

## Đọc state để khẳng định

Đây là phần khiến AutoCAD dễ test hơn Revit: state đọc thẳng, không cần add-in
tự ghi log.

| Cần biết | Đọc |
|---|---|
| Số đối tượng trong model | `$acad.ActiveDocument.ModelSpace.Count` |
| Chi tiết từng đối tượng | duyệt `ModelSpace`, xem `.ObjectName`, `.Length`, `.Layer`... |
| Biến hệ thống (kể cả `USERI1`–`USERI5`, `USERS1`–`USERS5`) | `.GetVariable('USERI1')` / `.SetVariable(...)` |
| Bản vẽ hiện hành | `$acad.ActiveDocument.Name` |
| Số bản vẽ đang mở | `$acad.Documents.Count` |

`USERI1`–`USERI5` và `USERS1`–`USERS5` là biến để trống sẵn cho người dùng — chỗ
lý tưởng để add-in "báo cáo" ra ngoài mà không cần file log. Đã verify ghi/đọc
lại đúng giá trị.

## Vòng lặp chuẩn, đã verify đầy đủ

```powershell
$before = $doc.ModelSpace.Count                           # 0

Invoke-AcadCommand -Document $doc -Command "._LINE`r0,0`r100,100`r`r"
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected ($before + 1)
# $r.Ok = True, ModelSpace 0 -> 1, sau 3-4ms

Invoke-AcadCommand -Document $doc -Command "._UNDO`r1`r"
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected $before
# $r.Ok = True, ve 0, sau 8-11ms
```

**`SendCommand` không chạy đồng bộ** — nó đẩy lệnh vào hàng đợi của AutoCAD,
giống `PostCommand` bên Revit. Luôn `Wait-UiState` chứ đừng `Start-Sleep` rồi đọc
một lần: đo thật cho thấy lệnh về trong 3–11 ms, nhưng một lệnh nặng thì không, và
sleep cố định sẽ cho kết quả chập chờn nhìn giống bug sản phẩm.

## Đóng sạch

```powershell
$doc.Close($false)                   # $false = khong luu
$acad.Quit()
```

Đã verify đóng sạch hoàn toàn, không cần `Stop-Process`. Kill cứng để lại file
khoá `.dwl`/`.dwl2` cạnh bản vẽ.

## Giới hạn

- Cần AutoCAD **full**, không phải LT (LT không có COM/.NET API).
- Nếu có nhiều phiên AutoCAD cùng chạy, `GetActiveObject` trả về phiên **đăng ký
  ROT đầu tiên**, không chọn được. Test tự động nên đảm bảo chỉ một phiên:
  `Stop-HostApp -Name 'acad'` trước khi mở.
- Số đo lấy trên AutoCAD 2027 một máy. Tỉ lệ thì ổn định, con số tuyệt đối thì
  không nên coi là chuẩn.
