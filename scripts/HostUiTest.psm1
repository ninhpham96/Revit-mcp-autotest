<#
    HostUiTest — lái UI của app host desktop (Revit, AutoCAD) từ bên ngoài để
    test add-in bằng thao tác THẬT.

    Mỗi hàm ở đây sinh ra từ một lỗi thật đã gặp, không phải tiện ích cho đủ bộ.
    references/ trong skill ghi rõ lỗi nào đẻ ra hàm nào.

    Yêu cầu: Windows PowerShell 5.1+.
    File này lưu UTF-8 CÓ BOM — PS 5.1 đọc file UTF-8 không BOM theo ANSI và làm
    hỏng mọi ký tự ngoài ASCII. Đừng lưu lại bằng `Set-Content -Encoding utf8`
    của PS 5.1: nó ghi ra BOM nhưng mã hoá lại nội dung đã là UTF-8 một lần nữa.
#>

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class HostNative
{
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);

    public struct POINT { public int X; public int Y; }
    delegate bool EnumProc(IntPtr h, IntPtr l);

    static string Text(IntPtr h) { var s = new StringBuilder(512); GetWindowTextW(h, s, 512); return s.ToString(); }
    static string Cls(IntPtr h)  { var s = new StringBuilder(256); GetClassNameW(h, s, 256);  return s.ToString(); }

    // Liet ke cua so top-level bang Win32 tho, KHONG qua UI Automation: UIA
    // khong nhin thay MessageBox khi UI thread cua app dang long trong mot
    // message loop khac, con EnumWindows thi thay ngay lap tuc.
    public static List<object[]> TopLevel(uint pid, bool visibleOnly)
    {
        var list = new List<object[]>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && (!visibleOnly || IsWindowVisible(h)))
                list.Add(new object[] { h, Cls(h), Text(h), IsWindowEnabled(h), IsWindowVisible(h) });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Bo '&' vi Win32 giu ky tu tat trong text cua nut ("&OK" -> "OK").
    public static IntPtr FindChild(IntPtr parent, string label)
    {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) => {
            if (Text(h).Replace("&", "") == label) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static void ClickNative(IntPtr btn) { SendMessageW(btn, 0x00F5, IntPtr.Zero, IntPtr.Zero); } // BM_CLICK
    public static void CloseWindow(IntPtr h)   { PostMessageW(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }   // WM_CLOSE

    // ---- Nhap lieu tong hop: SendInput, KHONG phai mouse_event ----------------
    //
    // Loi that: bam bang mouse_event + SetCursorPos thi chay tot, nhung KEO-THA thi
    // khong bao gio khoi dong duoc - Explorer coi ca thao tac la mot cu click va cua so
    // dich khong nhan duoc drop nao. Doi sang SendInput la an ngay, khong doi gi khac.
    // mouse_event da bi Microsoft danh dau superseded; dung SendInput cho MOI thu.

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public MOUSEINPUT mi; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] p, int cb);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);

    const uint MOVE = 0x0001, LEFTDOWN = 0x0002, LEFTUP = 0x0004, ABSOLUTE = 0x8000, VIRTUALDESK = 0x4000;

    static void Send(uint flags, int x, int y)
    {
        // Toa do tuyet doi la 0..65535 tren TOAN BO virtual desktop (VIRTUALDESK), nen
        // dung duoc voi nhieu man hinh va voi man hinh phu o toa do am.
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77);
        int vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);

        var i = new INPUT { type = 0 };
        i.mi.dwFlags = flags;
        if ((flags & MOVE) != 0)
        {
            i.mi.dx = (int)(((double)(x - vx) * 65535.0) / (vw - 1));
            i.mi.dy = (int)(((double)(y - vy) * 65535.0) / (vh - 1));
        }
        if (SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT))) != 1)
            throw new Exception("SendInput thất bại, GetLastError=" + Marshal.GetLastWin32Error());
    }

    public static void MoveTo(int x, int y) { Send(MOVE | ABSOLUTE | VIRTUALDESK, x, y); }
    public static void MouseDown()          { Send(LEFTDOWN, 0, 0); }
    public static void MouseUp()            { Send(LEFTUP, 0, 0); }

    public static void ClickScreen(int x, int y, bool restore)
    {
        POINT old; GetCursorPos(out old);
        MoveTo(x, y);
        System.Threading.Thread.Sleep(250);
        MouseDown();
        System.Threading.Thread.Sleep(60);
        MouseUp();
        if (restore) { System.Threading.Thread.Sleep(120); MoveTo(old.X, old.Y); }
    }
}
"@

# ===========================================================================
# Tầng 0 — Win32: cửa sổ và dialog native
# ===========================================================================

function Get-HostWindow {
    <#  .SYNOPSIS Liệt kê cửa sổ top-level của process, kèm class và title.
        .DESCRIPTION Luôn chạy cái này TRƯỚC khi kết luận "UIA hỏng" — phần lớn
        trường hợp thật ra là có một dialog đang chặn. #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [switch]$IncludeHidden
    )
    foreach ($w in [HostNative]::TopLevel([uint32]$ProcessId, -not $IncludeHidden)) {
        [pscustomobject]@{
            Handle  = [IntPtr]$w[0]
            Class   = [string]$w[1]
            Title   = [string]$w[2]
            Enabled = [bool]$w[3]
            Visible = [bool]$w[4]
        }
    }
}

function Wait-HostWindow {
    <#  .SYNOPSIS Chờ một cửa sổ có title khớp hiện ra. Trả về object cửa sổ hoặc $null. #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$Title,
        [switch]$Exact,
        [int]$TimeoutMs = 30000
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        foreach ($w in Get-HostWindow -ProcessId $ProcessId) {
            if ($Exact) { if ($w.Title -eq $Title) { return $w } }
            elseif ($w.Title -like "*$Title*") { return $w }
        }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { return $null }
        Start-Sleep -Milliseconds 400
    }
}

function Invoke-HostNativeButton {
    <#  .SYNOPSIS Bấm nút trên dialog native bằng BM_CLICK, không qua UI Automation.
        .DESCRIPTION Dùng cho MessageBox và dialog khởi động của host — chỗ UIA
        thường không nhìn thấy. Trả về $true nếu tìm thấy nút. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Window,
        [Parameter(Mandatory)][string]$Label
    )
    $btn = [HostNative]::FindChild($Window, $Label)
    if ($btn -eq [IntPtr]::Zero) { return $false }
    [HostNative]::ClickNative($btn)
    $true
}

function Close-StrayWindow {
    <#  .SYNOPSIS Đóng dialog còn sót của host, giữ nguyên cửa sổ nội bộ của nó.
        .DESCRIPTION Gọi TRƯỚC và SAU mỗi bước test. Hai lý do, cả hai đều là lỗi thật:
          1. Một modal đang mở làm TOÀN BỘ nội dung pane biến mất khỏi cây UIA —
             triệu chứng giống hệt "UI của tôi hỏng".
          2. Một OpenFileDialog bỏ quên khiến mọi thao tác gõ/bấm sau đó rơi vào
             chính nó — đã từng ghi nhầm dữ liệu thật vào file config người dùng.

        Lọc theo CLASS chứ không theo tiêu đề. Lỗi thật: bản đầu lọc theo tiêu đề
        và đã đóng nhầm một cửa sổ nội bộ của Revit tên '<guid>Monitor'. Host có
        cửa sổ phụ riêng của nó với tiêu đề không đoán được; class thì đoán được —
        MessageBox, TaskDialog và OpenFileDialog đều là '#32770'.

        Dùng -AnyClass khi cần đóng cả dialog WPF (class 'HwndWrapper[...]'), nhưng
        lúc đó phải đặt -KeepPattern cho chắc.
        Trả về danh sách title đã đóng. #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$KeepPattern,
        [string[]]$DialogClass = @('#32770'),
        [switch]$AnyClass,
        [int]$SettleMs = 700
    )
    $closed = @()
    foreach ($w in Get-HostWindow -ProcessId $ProcessId) {
        if (-not $w.Title) { continue }
        if ($KeepPattern -and $w.Title -match $KeepPattern) { continue }
        if (-not $AnyClass -and $DialogClass -notcontains $w.Class) { continue }
        [HostNative]::CloseWindow($w.Handle)
        $closed += $w.Title
        Start-Sleep -Milliseconds $SettleMs
    }
    $closed
}

function Set-HostForeground {
    <#  .SYNOPSIS Đưa host lên trước và phóng to.
        .DESCRIPTION WPF chỉ dựng visual tree cho phần thật sự vẽ ra, nên nội dung
        trong ScrollViewer của cửa sổ bị che có thể không có peer UIA. #>
    param([Parameter(Mandatory)][int]$ProcessId)
    $p = Get-Process -Id $ProcessId
    [void][HostNative]::ShowWindow($p.MainWindowHandle, 3)   # SW_MAXIMIZE
    [void][HostNative]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 900
}

# ===========================================================================
# Tầng 1 — UI Automation, luôn phân giải lại từ gốc
# ===========================================================================

function Get-UiRoot {
    param([Parameter(Mandatory)][int]$ProcessId)
    $p = Get-Process -Id $ProcessId
    [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
}

function ConvertTo-UiControlType {
    param([string]$Type)
    if (-not $Type) { return $null }
    $f = [System.Windows.Automation.ControlType].GetField($Type, 'Public,Static')
    if (-not $f) { throw "ControlType '$Type' không tồn tại." }
    $f.GetValue($null)
}

function Find-UiElement {
    <#  .SYNOPSIS Tìm một phần tử, phân giải lại từ gốc mỗi vòng lặp cho tới khi thấy.
        .DESCRIPTION Không bao giờ giữ lại AutomationElement giữa các bước: khi WPF
        dựng lại ItemsControl (ví dụ sau ICollectionView.Refresh) thì element cũ
        thành stale, và FindAll từ nó trả về rỗng — nhìn y hệt "danh sách trống".

        Ưu tiên -AutomationId hơn -Name: trên ribbon AutoCAD, tên "Insert" khớp 3
        phần tử khác nhau, và vài nút có Name là dữ liệu đường vẽ ("M0,4L4,0 8,4z").

        -Match làm so khớp chuỗi con; phải quét cả cây nên chậm hơn ~32 lần. #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$Name,
        [string]$AutomationId,
        [string]$Type,
        [switch]$Match,
        [int]$TimeoutMs = 6000
    )
    $ct = ConvertTo-UiControlType $Type
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $root = Get-UiRoot -ProcessId $ProcessId
        $fast = $null
        if ($AutomationId) {
            $fast = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
        }
        elseif ($Name -and $ct -and -not $Match) {
            # Để UIA lọc ngay phía provider. Đo thật trên AutoCAD 2027:
            # FindFirst(And) ~95ms, FindAll quét hết ~3050ms.
            $fast = New-Object System.Windows.Automation.AndCondition(
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)),
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)))
        }

        if ($fast) {
            $hit = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $fast)
            if ($hit -and $ct -and $AutomationId -and $hit.Current.ControlType -ne $ct) { $hit = $null }
            if ($hit) { return $hit }
        }
        else {
            foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
                if ($ct -and $e.Current.ControlType -ne $ct) { continue }
                if ($Name) {
                    if ($Match) { if ($e.Current.Name -notlike "*$Name*") { continue } }
                    elseif ($e.Current.Name -ne $Name) { continue }
                }
                return $e
            }
        }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { return $null }
        Start-Sleep -Milliseconds 400
    }
}

function Measure-UiElement {
    <#  .SYNOPSIS Đếm phần tử khớp — dùng để đếm số dòng/thẻ trong danh sách.
        .DESCRIPTION Đếm theo một control CÓ peer và xuất hiện đúng một lần mỗi
        dòng (ví dụ nút "Xoá" của từng dòng). ĐỪNG đếm theo TextBlock đường dẫn:
        TextTrimming=CharacterEllipsis làm UIA trả về chuỗi ĐÃ BỊ CẮT. #>
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$Name,
        [string]$Type = 'Button'
    )
    $ct = ConvertTo-UiControlType $Type
    $root = Get-UiRoot -ProcessId $ProcessId
    $n = 0
    foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($e.Current.Name -eq $Name -and $e.Current.ControlType -eq $ct) { $n++ }
    }
    $n
}

function Invoke-UiElement {
    <#  .SYNOPSIS Bấm qua InvokePattern. Trả về $false nếu phần tử không hỗ trợ. #>
    param([Parameter(Mandatory)]$Element)
    $pat = $null
    if (-not $Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) { return $false }
    $pat.Invoke()
    $true
}

function Set-UiValue {
    <#  .SYNOPSIS Đặt giá trị ô nhập qua ValuePattern, trong phạm vi -Scope.
        .DESCRIPTION LUÔN truyền -Scope là pane/cửa sổ của add-in. Lấy "ô Edit đầu
        tiên trong cả cửa sổ" sẽ gõ nhầm vào ô tên file của một hộp thoại đang mở —
        lỗi này đã từng ghi dữ liệu thật vào config người dùng. #>
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$Index = 0
    )
    $edits = $Scope.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)))
    if ($edits.Count -le $Index) { return $false }
    $edits[$Index].GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    $true
}

# ===========================================================================
# Tầng 2 — chuột thật, cho control không có peer UIA
# ===========================================================================

function Invoke-UiClick {
    <#  .SYNOPSIS Bấm chuột thật tại toạ độ màn hình, khôi phục vị trí con trỏ sau đó. #>
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [switch]$NoRestoreCursor
    )
    [HostNative]::ClickScreen($X, $Y, -not $NoRestoreCursor)
}

function Invoke-UiClickElement {
    <#  .SYNOPSIS Bấm chuột thật vào giữa một phần tử có peer UIA.
        .DESCRIPTION Dùng khi phần tử có peer nhưng không hỗ trợ InvokePattern. #>
    param([Parameter(Mandatory)]$Element, [switch]$NoRestoreCursor)
    $r = $Element.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    Invoke-UiClick -X ([int]($r.X + $r.Width / 2)) -Y ([int]($r.Y + $r.Height / 2)) -NoRestoreCursor:$NoRestoreCursor
    $true
}

function Invoke-UiClickOffset {
    <#  .SYNOPSIS Bấm chuột thật tại vị trí lệch so với một phần tử neo.
        .DESCRIPTION Dành cho control KHÔNG hề có peer UIA — ví dụ nút nằm trong
        DataTemplate của ItemsControl. Đo độ lệch một lần từ ảnh chụp, sau đó mỗi
        lần chạy đều tính lại từ neo.

        ĐỪNG hardcode toạ độ tuyệt đối: chỉ cần một dòng gợi ý hiện thêm là cả hàng
        nút tụt xuống vài chục pixel, và test sẽ bấm nhầm nút khác mà vẫn báo
        "thành công". Đây là lỗi thật, lệch 13 pixel. #>
    param(
        [Parameter(Mandatory)]$Anchor,
        [Parameter(Mandatory)][int]$Dx,
        [Parameter(Mandatory)][int]$Dy,
        [switch]$NoRestoreCursor
    )
    $r = $Anchor.Current.BoundingRectangle
    if ($r.Width -le 0) { return $false }
    Invoke-UiClick -X ([int]($r.X + $Dx)) -Y ([int]($r.Y + $Dy)) -NoRestoreCursor:$NoRestoreCursor
    $true
}

function Invoke-UiDragDrop {
    <#  .SYNOPSIS Kéo-thả THẬT giữa hai điểm trên màn hình, đi qua OLE của Windows.
        .DESCRIPTION Không mô phỏng được drag-drop bằng cách gọi API của app đích: WPF chỉ
        nhận drop khi có một OLE drag source thật đang chạy `DoDragDrop`.

        Mẹo: **Windows Explorer chính là một OLE drag source thật.** Mở Explorer ở thư mục
        chứa file, kéo bằng chuột thật từ item đó sang cửa sổ đích — đúng thao tác người
        dùng làm, và app đích không phân biệt được.

        Bốn chi tiết bắt buộc, thiếu cái nào cũng làm drag không khởi động — cả bốn đều
        rút ra từ một lần thất bại thật:
          - **Phải dùng `SendInput`.** Bản đầu dùng `mouse_event` + `SetCursorPos`: bấm thì
            chạy tốt (đã verify chọn được file trong Explorer), nhưng kéo thì Explorer coi
            cả thao tác là một cú click và không drop gì cả. Đổi sang `SendInput` là ăn
            ngay, không đổi gì khác.
          - Nhích vài pixel ngay sau khi nhấn, để vượt ngưỡng kéo của Windows
            (SM_CXDRAG/SM_CYDRAG, mặc định 4px).
          - Di chuyển theo NHIỀU bước nhỏ. OLE drag chạy trong message loop riêng của nguồn;
            một bước nhảy duy nhất không sinh đủ sự kiện DragOver.
          - Nhúc nhích tại đích rồi mới nhả, để đích kịp xử lý DragEnter/DragOver.

        AN TOÀN: thả trượt vào một thư mục khác sẽ DI CHUYỂN file (cùng ổ đĩa). Luôn kéo từ
        một BẢN SAO trong thư mục tạm, đừng kéo file gốc. #>
    param(
        [Parameter(Mandatory)][int]$FromX,
        [Parameter(Mandatory)][int]$FromY,
        [Parameter(Mandatory)][int]$ToX,
        [Parameter(Mandatory)][int]$ToY,
        [int]$Steps = 40,
        [int]$StepMs = 20,
        [int]$HoverMs = 500
    )
    [HostNative]::MoveTo($FromX, $FromY)
    Start-Sleep -Milliseconds 400
    [HostNative]::MouseDown()
    Start-Sleep -Milliseconds 200

    # Vượt ngưỡng kéo trước đã, chưa đi đâu cả.
    foreach ($d in 2, 4, 6, 9, 13, 18) {
        [HostNative]::MoveTo($FromX + $d, $FromY + $d)
        Start-Sleep -Milliseconds 70
    }

    for ($i = 1; $i -le $Steps; $i++) {
        [HostNative]::MoveTo([int]($FromX + ($ToX - $FromX) * $i / $Steps),
                             [int]($FromY + ($ToY - $FromY) * $i / $Steps))
        Start-Sleep -Milliseconds $StepMs
    }

    # Nhúc nhích trên đích để sinh thêm DragOver rồi mới nhả.
    foreach ($d in 0, 3, -3, 0) {
        [HostNative]::MoveTo($ToX + $d, $ToY + $d)
        Start-Sleep -Milliseconds 150
    }
    Start-Sleep -Milliseconds $HoverMs
    [HostNative]::MouseUp()
    Start-Sleep -Milliseconds 500
}

# ===========================================================================
# Tầng 3 — khẳng định dựa trên trạng thái app, không dựa vào chính UI vừa bấm
# ===========================================================================

function Wait-UiState {
    <#  .SYNOPSIS Chờ một phép đo trạng thái đạt giá trị mong đợi; trả về kết quả + thời gian.
        .DESCRIPTION -Probe nên đọc từ NGUỒN NGOÀI UI: file log, file config, marker
        do add-in ghi ra, hoặc COM của host. Bấm một nút rồi đọc lại chính cái nút
        đó không chứng minh được gì — nó chỉ chứng minh WPF đã vẽ lại.

        Sleep cố định cho kết quả chập chờn trông giống bug sản phẩm; poll cho tới
        khi đạt rồi báo thời gian thì phân biệt được "sai" với "chậm".

        .EXAMPLE
        Wait-UiState -Probe { $acad.ActiveDocument.ModelSpace.Count } -Expected 1 #>
    param(
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)]$Expected,
        [int]$TimeoutMs = 8000,
        [int]$PollMs = 400
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $v = & $Probe
        if ("$v" -eq "$Expected") {
            return [pscustomobject]@{ Ok = $true; Value = $v; ElapsedMs = $sw.ElapsedMilliseconds }
        }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) {
            return [pscustomobject]@{ Ok = $false; Value = $v; ElapsedMs = $sw.ElapsedMilliseconds }
        }
        Start-Sleep -Milliseconds $PollMs
    }
}

function Get-UiText {
    <#  .SYNOPSIS Dựng chuỗi có dấu từ code point.
        .DESCRIPTION Chỉ cần khi script GỌI module này lưu UTF-8 không BOM: PS 5.1
        đọc file đó theo ANSI và làm hỏng ký tự ngoài ASCII. Lưu ý '+' giữa hai
        [char] trong PowerShell là CỘNG SỐ NGUYÊN, không phải nối chuỗi.
        .EXAMPLE Get-UiText 0x4E,0x1EA1,0x70   # -> "Nạp" #>
    param([Parameter(Mandatory)][int[]]$CodePoint)
    -join ($CodePoint | ForEach-Object { [char]$_ })
}

# ===========================================================================
# Tầng 4 — vòng đời host
# ===========================================================================

function Stop-HostApp {
    <#  .SYNOPSIS Kill cứng host. Trả về số process đã kill. #>
    param([Parameter(Mandatory)][string]$Name, [int]$SettleSec = 4)
    $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) { $procs | Stop-Process -Force; Start-Sleep -Seconds $SettleSec }
    $procs.Count
}

function Start-RevitHost {
    <#  .SYNOPSIS Mở Revit, vượt qua dialog khởi động, mở project mới, chờ sẵn sàng.
        .DESCRIPTION Màn hình Home của Revit ẨN ribbon — phải mở một project thì mới
        test được nút nào.

        Mặc định bấm "Load Once" trên dialog add-in chưa ký, KHÔNG phải "Always Load":
        "Always Load" đổi thiết lập tin cậy vĩnh viễn trên máy người dùng. Chỉ dùng
        -AlwaysLoad khi người dùng đã đồng ý.

        -DismissExtra nhận thêm dialog riêng của máy, dạng @(@{Title='...'; Button='OK'}).
        -DiscoveryPath là file mà rvt-mcp (hoặc cơ chế tương đương) ghi ra khi đã
        đăng ký xong — đợi cả file đó mới thật sự là sẵn sàng. #>
    param(
        [Parameter(Mandatory)][string]$Year,
        [array]$DismissExtra = @(),
        [string]$DiscoveryPath,
        [switch]$AlwaysLoad,
        [int]$TimeoutSec = 240
    )
    $exe = "C:\Program Files\Autodesk\Revit $Year\Revit.exe"
    if (-not (Test-Path $exe)) { throw "Không thấy $exe" }
    if ($DiscoveryPath) { Remove-Item $DiscoveryPath -Force -ErrorAction SilentlyContinue }

    $loadButton = 'Load Once'
    if ($AlwaysLoad) { $loadButton = 'Always Load' }

    $proc = Start-Process -FilePath $exe -PassThru
    $newClicked = $false
    $notes = @()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if ($proc.HasExited) { throw "Revit $Year thoát sớm (exit=$($proc.ExitCode))." }

        foreach ($w in Get-HostWindow -ProcessId $proc.Id) {
            switch -Regex ($w.Title) {
                '^Security - Unsigned Add-In$' {
                    if (Invoke-HostNativeButton -Window $w.Handle -Label $loadButton) { $notes += "add-in chưa ký -> $loadButton" }
                }
                'External Tool Failure' {
                    $notes += '!! EXTERNAL TOOL FAILURE — add-in chết trong OnStartup, đọc log'
                    [void](Invoke-HostNativeButton -Window $w.Handle -Label 'Close')
                }
                '^New Project$' {
                    if (Invoke-HostNativeButton -Window $w.Handle -Label 'OK') { $notes += 'New Project -> OK' }
                }
            }
            foreach ($extra in $DismissExtra) {
                if ($w.Title -eq $extra.Title) {
                    if (Invoke-HostNativeButton -Window $w.Handle -Label $extra.Button) {
                        $notes += "dialog riêng '$($extra.Title)' -> $($extra.Button)"
                    }
                }
            }
        }

        $proc.Refresh()
        if (-not $newClicked -and $proc.MainWindowTitle -like '*Home*') {
            $btn = Find-UiElement -ProcessId $proc.Id -Name 'New ...' -Type Button -TimeoutMs 1500
            if ($btn -and (Invoke-UiElement $btn)) { $newClicked = $true; $notes += 'màn hình Home -> New' }
        }

        $ready = $proc.MainWindowTitle -like '*Project*'
        if ($ready -and $DiscoveryPath) { $ready = Test-Path $DiscoveryPath }
        if ($ready) {
            return [pscustomobject]@{ Process = $proc; Title = $proc.MainWindowTitle; Notes = $notes }
        }
    }
    throw "Revit $Year chưa sẵn sàng sau $TimeoutSec giây. Đã xử lý: $($notes -join '; ')"
}

function Get-AutoCadCom {
    <#  .SYNOPSIS Lấy COM của AutoCAD đang chạy, chờ tới khi THỰC SỰ dùng được.
        .DESCRIPTION Đây là kênh điều khiển/kiểm chứng chính cho CAD — tương đương
        revit_send_code_to_revit bên Revit. SendCommand để chạy, GetVariable và
        ModelSpace để đọc state thật.

        COM phản hồi KHÔNG có nghĩa là COM dùng được. Lỗi thật: GetActiveObject
        thành công từ rất sớm trong lúc AutoCAD còn đang nạp, nhưng lúc đó
        $acad.Documents vẫn là null, và $null.Count trong PowerShell trả về 0 chứ
        không ném lỗi — nên "đã có 0 document" trông hệt như "sẵn sàng, chưa mở
        bản vẽ nào", rồi .Add() mới nổ. Phải sờ vào một thành viên thật mới biết. #>
    param([int]$TimeoutMs = 120000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            $com = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application')
            if ($null -ne $com -and $null -ne $com.Documents) {
                [void]$com.Documents.Count      # ném nếu COM còn đang bận nạp
                return $com
            }
        } catch { }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { throw "AutoCAD COM chưa dùng được sau $([int]($TimeoutMs/1000))s." }
        Start-Sleep -Milliseconds 1500
    }
}

function Get-AcadDocument {
    <#  .SYNOPSIS Lấy ActiveDocument dùng được, phân giải lại tới khi có.
        .DESCRIPTION `$acad.ActiveDocument` CHẬP CHỜN null trong vài giây đầu sau
        khởi động: cùng một script, chỗ kiểm tra ngay sau `Start-AutoCadHost` báo
        có document, ba dòng sau thì chính property đó trả về null.

        Cùng nguyên tắc với UI Automation ở [07]: **phân giải lại, đừng tin một lần
        đọc**. Lấy đối tượng document MỘT lần qua hàm này rồi dùng suốt, thay vì
        gọi `$acad.ActiveDocument` ở mỗi chỗ. #>
    param(
        $Application,
        [int]$TimeoutMs = 30000
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            $app = $Application
            if ($null -eq $app) { $app = Get-AutoCadCom -TimeoutMs 5000 }
            $doc = $app.ActiveDocument
            if ($null -ne $doc -and -not [string]::IsNullOrEmpty($doc.Name)) { return $doc }
        } catch { }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { throw "Không lấy được ActiveDocument sau $([int]($TimeoutMs/1000))s." }
        Start-Sleep -Milliseconds 300
    }
}

function Invoke-AcadCommand {
    <#  .SYNOPSIS Gửi lệnh cho AutoCAD, chỉ khi dòng lệnh đang rảnh.
        .DESCRIPTION Hai hành vi của `SendCommand` đã đo được, và cả hai đều gây
        hỏng test theo kiểu khó lần:

        1. **`SendCommand` CHẶN cho tới khi lệnh chạy xong.** Gửi một chuỗi thiếu
           tham số (ví dụ `"._LINE`r0,0`r"` — mới một điểm) thì lệnh ngồi chờ điểm
           tiếp theo và lời gọi **không bao giờ trả về**. Đo thật: treo hết 300
           giây rồi phải kill AutoCAD. → Chuỗi lệnh phải **tự kết thúc**: trả lời
           đủ mọi prompt, kết bằng `` `r ``.

        2. **Gửi khi còn lệnh đang dở thì trượt im lặng.** Cùng một script, hai lần
           đầu pass, lần thứ ba `._UNDO` không có tác dụng — model vẫn giữ nguyên
           đối tượng vừa tạo, không lỗi nào được ném ra. Khác biệt duy nhất: trước
           đó có thao tác chuột lên ribbon.

        AutoCAD chỉ có MỘT dòng lệnh, và sysvar `CMDACTIVE` cho biết nó có rảnh
        không (0 = rảnh — đã verify). Hàm này **chờ rảnh rồi mới gửi, không tự
        huỷ**: huỷ từ COM không làm được (`SendCommand` với ESC bị trả
        `COMException: Invalid input` — đã thử), và âm thầm huỷ lệnh của người dùng
        cũng không phải việc của test harness.

        Hết thời gian chờ thì **ném lỗi**, biến một lần trượt im lặng thành một
        lần fail nhìn thấy được. #>
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Command,
        [int]$IdleTimeoutMs = 15000
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $active = 1
        try { $active = $Document.GetVariable('CMDACTIVE') } catch { }
        if ($active -eq 0) { break }
        if ($sw.ElapsedMilliseconds -ge $IdleTimeoutMs) {
            throw "AutoCAD còn lệnh đang chạy (CMDACTIVE=$active) sau $([int]($IdleTimeoutMs/1000))s — không gửi '$Command' để khỏi trượt im lặng."
        }
        Start-Sleep -Milliseconds 250
    }
    $Document.SendCommand($Command)
}

function Start-AutoCadHost {
    <#  .SYNOPSIS Mở AutoCAD và chờ tới khi THẬT SỰ sẵn sàng, trả về process + COM.
        .DESCRIPTION Đừng dùng tiêu đề cửa sổ làm tín hiệu sẵn sàng. Đo thật trên
        AutoCAD 2027: cửa sổ chính hiện ở giây thứ 3, nhưng tiêu đề còn đổi 3 lần
        nữa tới giây 18 ("AutoCAD 2027" -> "[Drawing1.dwg]" -> "[Start]" -> thêm
        banner licence). Tiêu đề còn chứa banner khác nhau tuỳ máy.

        Tín hiệu thật là COM phản hồi VÀ Documents.Count > 0. AutoCAD dừng ở tab
        Start với 0 document — giống màn hình Home của Revit, chưa test được gì. #>
    param(
        [string]$Version = '2027',
        [switch]$NoNewDrawing,
        [int]$TimeoutSec = 180
    )
    $exe = "C:\Program Files\Autodesk\AutoCAD $Version\acad.exe"
    if (-not (Test-Path $exe)) { throw "Không thấy $exe" }

    $proc = Start-Process -FilePath $exe -PassThru
    $acad = Get-AutoCadCom -TimeoutMs ($TimeoutSec * 1000)
    $notes = @('COM dùng được')

    if (-not $NoNewDrawing -and $acad.Documents.Count -eq 0) {
        [void]$acad.Documents.Add()
        $notes += 'tab Start, 0 document -> Documents.Add()'
    }

    # Documents.Add() TRẢ VỀ TRƯỚC khi ActiveDocument sẵn sàng — lỗi thật: ngay
    # sau Add(), $acad.ActiveDocument vẫn null và SendCommand nổ. Phải chờ đúng
    # thứ mình sắp dùng, và phân giải lại COM mỗi vòng: proxy lấy lúc app còn
    # đang nạp có thể trỏ vào một instance chưa dựng xong.
    $r = Wait-UiState -PollMs 1000 -TimeoutMs 90000 -Expected $true -Probe {
        try {
            $c = Get-AutoCadCom -TimeoutMs 3000
            ($null -ne $c.ActiveDocument) -and -not [string]::IsNullOrEmpty($c.ActiveDocument.Name)
        } catch { $false }
    }
    if (-not $r.Ok) { throw "AutoCAD có document nhưng ActiveDocument không dùng được sau 90s." }

    $acad = Get-AutoCadCom -TimeoutMs 10000
    $notes += "ActiveDocument sẵn sàng sau $($r.ElapsedMs)ms"

    $proc.Refresh()
    [pscustomobject]@{ Process = $proc; Com = $acad; Title = $proc.MainWindowTitle; Notes = $notes }
}

Export-ModuleMember -Function *-*
