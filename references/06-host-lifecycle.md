# Vòng đời host: mở app và biết khi nào nó THẬT SỰ sẵn sàng

Phần tốn thời gian nhất khi auto-test add-in không phải là bấm nút — mà là đưa
host tới trạng thái test được. Sai ở đây thì mọi test sau đều chập chờn, và
triệu chứng nhìn giống hệt bug trong add-in.

## Luật: "cửa sổ đã hiện" không phải là "sẵn sàng"

Đo thật trên **AutoCAD 2027**, từ lúc `Start-Process` tới lúc ổn định:

| Giây | Trạng thái |
|---|---|
| 0 | cửa sổ splash `AdSplashWindowClass`, không tiêu đề |
| 3 | cửa sổ chính `AfxMDIFrame140u`, tiêu đề `Autodesk AutoCAD 2027` |
| 6 | tiêu đề đổi thành `... - [Drawing1.dwg]` |
| 12 | tiêu đề đổi thành `... - [Start]` |
| 18 | tiêu đề đổi thành `... - EDUCATION (NON COMMERCIAL) - [Start]` |

Ai chờ "`MainWindowTitle` khác rỗng" sẽ bắt đầu test ở **giây thứ 3**, lúc app
còn đang nạp. Và tiêu đề còn chứa banner licence khác nhau tuỳ máy, nên khớp
tiêu đề vốn đã mong manh.

**Tín hiệu sẵn sàng đúng là thứ sâu nhất mà test sắp dùng tới.**

## AutoCAD: chờ COM, rồi chờ sâu hơn nữa

COM là kênh điều khiển chính cho CAD. Nhưng có hai tầng bẫy chồng nhau, cả hai
đều đã làm test fail thật:

### Bẫy 1 — COM phản hồi ≠ COM dùng được

`Marshal.GetActiveObject("AutoCAD.Application")` **thành công từ rất sớm**, trong
lúc AutoCAD còn đang nạp. Lúc đó `$acad.Documents` vẫn là `null`.

Điều làm nó khó thấy: trong PowerShell `$null.Count` trả về **`0`**, không ném
lỗi (đã verify). Nên:

```powershell
if ($acad.Documents.Count -eq 0) { $acad.Documents.Add() }   # SAI
```

"chưa nạp xong" và "đã sẵn sàng, chưa mở bản vẽ nào" cho ra **cùng một giá trị**.
Nhánh `if` chạy, rồi `.Add()` mới nổ `InvokeMethodOnNull`.

→ Phải **sờ vào một thành viên thật** mới biết. `Get-AutoCadCom` làm việc này.

### Bẫy 2 — `Documents.Add()` trả về trước khi `ActiveDocument` sẵn sàng

Ngay sau khi `Add()` trả về, `$acad.ActiveDocument` vẫn null và `SendCommand`
nổ. Đo thật: `ActiveDocument` dùng được sau thêm **~1770ms**.

→ `Start-AutoCadHost` chờ đúng `ActiveDocument.Name` khác rỗng, và **phân giải
lại COM mỗi vòng poll**: proxy lấy lúc app còn đang nạp có thể trỏ vào một
instance chưa dựng xong.

### AutoCAD dừng ở tab Start với 0 document

Giống hệt màn hình Home của Revit: chưa có bản vẽ thì chưa test được gì.
`Start-AutoCadHost` tự gọi `Documents.Add()`; dùng `-NoNewDrawing` để tắt.

## Revit: dialog chặn và màn hình Home

`Start-RevitHost` xử lý sẵn:

| Cửa sổ | Hành động | Vì sao |
|---|---|---|
| `Security - Unsigned Add-In` | bấm **Load Once** | **Không** bấm "Always Load": nó đổi thiết lập tin cậy **vĩnh viễn** trên máy người dùng. Chỉ dùng `-AlwaysLoad` khi người dùng đã đồng ý. |
| `External Tools - External Tool Failure` | ghi nhận + Close | Đây là dấu hiệu add-in **chết trong `OnStartup`**. Ghi vào `Notes` để test fail có lý do rõ, thay vì fail mơ hồ ở bước sau. |
| `New Project` | bấm OK | Hộp chọn template sau khi bấm New. |
| Màn hình **Home** | bấm `New ...` qua UIA | **Màn hình Home ẩn ribbon** — không mở project thì không có nút nào để test. |
| Dialog riêng của máy | `-DismissExtra` | Add-in bên thứ ba hay bật thông báo hạn dùng ngay lúc khởi động và chặn toàn bộ phần còn lại. |

Dialog khởi động bấm bằng **Win32 `BM_CLICK`**, không qua UIA — xem
[07-uia-blind-spots.md](07-uia-blind-spots.md).

Nếu dùng rvt-mcp, truyền `-DiscoveryPath` trỏ tới file mà nó ghi ra khi đăng ký
xong (`%LOCALAPPDATA%\RvtMcp\revit-<năm>.json`). Xoá file trước khi mở rồi chờ
nó xuất hiện — vừa là tín hiệu sẵn sàng, vừa tránh ăn nhầm file của phiên cũ.

## Đóng host: ưu tiên đóng sạch

```powershell
$acad.ActiveDocument.Close($false)   # $false = không lưu
$acad.Quit()
```

Đã verify đóng sạch, không cần kill. `Stop-HostApp` (kill cứng) chỉ để dọn khi
lần chạy trước chết giữa chừng. Kill cứng Revit/AutoCAD có thể để lại file khoá
và journal dở dang.

## Trước khi kết luận "UI hỏng", liệt kê cửa sổ

```powershell
Get-HostWindow -ProcessId $pid | Format-Table Class, Title, Enabled
```

Phần lớn trường hợp "UIA không tìm thấy gì" thật ra là **có một dialog đang
chặn**. Cái này tốn hơn một vòng debug thật mới nhận ra.
