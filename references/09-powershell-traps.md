# Bẫy PowerShell trong harness test

Không cái nào trong này là bug của app được test. Tất cả đều là harness tự bắn
vào chân mình, và tất cả đều đã tốn thời gian thật — vài cái còn *giả dạng* thành
bug sản phẩm, tức là còn tệ hơn crash.

## 1. PS 5.1 đọc file UTF-8 không BOM theo ANSI

Windows PowerShell 5.1 đọc `.ps1` **không có BOM** theo codepage ANSI. Mọi ký tự
ngoài ASCII trong script — nhãn nút tiếng Việt, tiêu đề dialog tiếng Nhật — bị
hỏng **âm thầm**, và phép so khớp trượt mà không báo lỗi gì.

→ Lưu mọi `.ps1`/`.psm1` có ký tự ngoài ASCII bằng **UTF-8 CÓ BOM**:

```powershell
$t = [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
```

Hoặc tránh hẳn: dựng chuỗi từ code point bằng `Get-UiText`.

## 2. `Set-Content -Encoding utf8` mã hoá chồng lên file đã là UTF-8

Đây là cái tệ nhất trong danh sách, vì nó **hỏng file nguồn của dự án**.

`Set-Content -Encoding utf8` của PS 5.1 hiểu nội dung đang ở codepage hiện hành
rồi chuyển sang UTF-8. Nếu nội dung **vốn đã là UTF-8**, nó bị mã hoá lần hai:
`ế` → `áº¿`. Đã làm hỏng một file `.cs` có chú thích tiếng Việt; phải
`git checkout --` để khôi phục.

→ Sửa file nguồn bằng công cụ sửa file, không bằng `Set-Content`. Nếu buộc phải
dùng PowerShell, đi qua `[IO.File]::ReadAllText/WriteAllText` với encoding chỉ
định rõ như trên.

## 3. `[char] + [char]` là CỘNG SỐ NGUYÊN

```powershell
[char]0x4E + [char]0x1EA1     # -> 7921  (số!), không phải "Nạ"
```

→ Dùng `-join`, hoặc `Get-UiText 0x4E,0x1EA1,0x70`.

## 4. `-notmatch` trên MẢNG luôn "đúng" trong `if`

```powershell
$out = dotnet build ... 2>&1          # MẢNG nhiều dòng
if ($out -notmatch "Build succeeded") { "BUILD FAILED" }   # SAI
```

Với mảng, `-notmatch` là **toán tử lọc**: nó trả về *các phần tử không khớp*.
Build thành công vẫn có hàng chục dòng khác không chứa "Build succeeded", nên
mảng trả về khác rỗng → truthy → luôn báo fail.

→ Nối trước rồi mới so:

```powershell
if (($out -join "`n") -notmatch "Build succeeded") { ... }
```

## 5. `$home` là biến tự động CHỈ ĐỌC

```powershell
$home = Find-UiElement ... -AutomationId 'ACAD.ID_TabHome'
# Cannot overwrite variable HOME because it is read-only or constant.
```

`$home`, `$host`, `$pid`, `$input`, `$args`, `$error`, `$matches` đều là biến tự
động. `$host` và `$home` là **hằng**, ghi đè là lỗi ngay.

→ Đặt tên riêng: `$tabHome`, `$hostApp`, `$procId`.

## 6. `$null.Count` trả về `0`, không ném lỗi

```powershell
$x = $null
$x.Count            # -> 0
$x.Count -eq 0      # -> True
```

PowerShell 3+ gắn `.Count` cho cả `$null`. Nên với COM chưa nạp xong:

```powershell
if ($acad.Documents.Count -eq 0) { $acad.Documents.Add() }
```

"`Documents` còn null vì app chưa nạp xong" và "đã sẵn sàng, chưa mở bản vẽ nào"
cho ra **cùng một giá trị**. Nhánh `if` chạy, rồi `.Add()` mới nổ.

→ Kiểm `$null -ne $obj.Thành_viên` trước khi tin vào `.Count`. Xem
[06-host-lifecycle.md](06-host-lifecycle.md).

## 7. `-ErrorAction SilentlyContinue` không làm lệnh "không fail"

Nó chỉ chặn **hiển thị** lỗi; cmdlet vẫn thất bại và exit code vẫn là 1.

→ Muốn bỏ qua thật sự thì nâng lên terminating rồi nuốt:

```powershell
try { Cmdlet ... -ErrorAction Stop } catch { }
```

## 8. Đừng truyền tham số có dấu qua Git Bash

Git Bash truyền tham số UTF-8 có dấu cho exe Windows không ổn định — cùng một
lệnh cho kết quả khác nhau giữa các lần chạy. Dùng **PowerShell** hoặc **cmd** khi
tham số chứa ký tự ngoài ASCII.

Hệ quả cho môi trường này: heredoc của Bash cũng không phải cách tốt để ghi file
`.ps1` có ký tự ngoài ASCII (mất BOM) hoặc có khối C# nhúng (vỡ quoting).

## 9. `2>&1` trên native exe làm hỏng `$?`

Trong PS 5.1, chuyển hướng stderr của một exe **bọc mỗi dòng vào `ErrorRecord`**
(`NativeCommandError`) và đặt `$?` thành `$false` **kể cả khi exe trả về exit code
0**. Đừng chuyển hướng stderr nếu chỉ cần đọc output.

## 10. `[IO.File]` bỏ qua `Set-Location`

```powershell
Set-Location C:\skill
[IO.File]::ReadAllText(".\scripts\x.psm1")   # tìm ở cwd CŨ của process, không phải C:\skill
```

Cmdlet PowerShell (`Get-ChildItem`, `Get-Content`) theo `Set-Location`; **method
tĩnh .NET thì không** — chúng dùng `[Environment]::CurrentDirectory`, và
`Set-Location` không cập nhật biến đó.

Bẫy này cắn đúng lúc khó chịu nhất: mục 1 và 2 ở trên bảo dùng
`[IO.File]::WriteAllText` để ghi BOM cho đúng, và đó lại chính là API dính lỗi này.

→ Luôn truyền **đường dẫn tuyệt đối** cho method tĩnh .NET, hoặc `Resolve-Path` trước.

## 11. Alias thắng function

```powershell
function CP([string]$s) { ... }
CP $title        # chay Copy-Item, KHONG chay function vua dinh nghia
```

Thứ tự phân giải lệnh của PowerShell là **Alias → Function → Cmdlet →
Application**, nên alias có sẵn nuốt mất function cùng tên. `cp`, `mv`, `ls`,
`rm`, `sc`, `cat`, `gc`, `sl`, `where` đều là alias.

Triệu chứng rất dễ lạc hướng: lỗi báo về `Copy-Item` trong khi trong script không
có chữ `Copy-Item` nào.

→ Đặt tên function theo quy ước `Verb-Noun` (`Get-CodePoint`), hoặc gọi bằng
`& (Get-Command CP -CommandType Function)`.
