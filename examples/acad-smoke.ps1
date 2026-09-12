<#
    Mẫu smoke test cho add-in AutoCAD — copy file này rồi đổi phần "add-in của bạn".

    Minh hoạ đủ 3 tầng và, quan trọng hơn, minh hoạ KỶ LUẬT: mỗi lần bấm đều được
    kiểm chứng bằng trạng thái thật của app (COM), không bằng chính UI vừa bấm.

    File này lưu UTF-8 CÓ BOM. Xem references/04-powershell-traps.md.
#>
param([string]$Version = '2027')

Import-Module (Join-Path $PSScriptRoot '..\scripts\HostUiTest.psm1') -Force

$fail = 0
function Check($label, $ok, $detail) {
    $mark = 'OK  '
    if (-not $ok) { $mark = 'FAIL'; $script:fail++ }
    "{0} {1,-42} {2}" -f $mark, $label, $detail
}

# --- 0. Khởi động sạch -----------------------------------------------------
[void](Stop-HostApp -Name 'acad')
$host0 = Start-AutoCadHost -Version $Version
$acad = $host0.Com
# Lay document MOT lan roi dung suot: $acad.ActiveDocument chap chon null
# trong vai giay dau sau khoi dong.
$doc  = Get-AcadDocument -Application $acad
$pid0 = $host0.Process.Id
Check 'AutoCAD sẵn sàng' ($null -ne $doc) "$($host0.Notes -join '; ')"

# Không có modal nào sót lại thì UIA mới nhìn thấy nội dung cửa sổ.
$closed = Close-StrayWindow -ProcessId $pid0 -KeepPattern 'AutoCAD'
Check 'không còn cửa sổ lạ' ($closed.Count -eq 0) "đã đóng: $($closed.Count)"
Set-HostForeground -ProcessId $pid0

# --- 1. Chạy qua COM, kiểm chứng bằng model thật ---------------------------
# Với add-in của bạn: đổi SendCommand thành tên lệnh add-in đăng ký,
# đổi Probe thành thứ add-in ĐÁNG LẼ phải thay đổi.
$before = $doc.ModelSpace.Count
Invoke-AcadCommand -Document $doc -Command "._LINE`r0,0`r100,100`r`r"
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected ($before + 1)
Check 'lệnh chạy -> model đổi thật' $r.Ok "ModelSpace $before -> $($r.Value) sau $($r.ElapsedMs)ms"

# --- 2. Tìm phần tử UIA theo AutomationId (đường nhanh) --------------------
$sw = [Diagnostics.Stopwatch]::StartNew()
$tab = Find-UiElement -ProcessId $pid0 -AutomationId 'ACAD.ID_TabInsert' -Type Button
Check 'tìm tab ribbon theo AutomationId' ($null -ne $tab) "$($sw.ElapsedMilliseconds)ms"

# --- 3. Bấm qua InvokePattern ---------------------------------------------
if ($tab) {
    $invoked = Invoke-UiElement $tab
    Start-Sleep -Milliseconds 1200
    # Panel "Block Definition" chỉ có trên tab Insert -> tab đã thật sự chuyển.
    $panel = Find-UiElement -ProcessId $pid0 -Name 'Block Definition' -Match -TimeoutMs 4000
    Check 'bấm tab -> nội dung tab Insert hiện' ($invoked -and $null -ne $panel) "invoke=$invoked"
}

# --- 4. Bấm bằng chuột THẬT vào giữa phần tử -------------------------------
$tabHome = Find-UiElement -ProcessId $pid0 -AutomationId 'ACAD.ID_TabHome' -Type Button
if ($tabHome) {
    [void](Invoke-UiClickElement -Element $tabHome)
    Start-Sleep -Milliseconds 1200
    $draw = Find-UiElement -ProcessId $pid0 -Name 'Draw' -Match -TimeoutMs 4000
    Check 'chuột thật -> quay lại tab Home' ($null -ne $draw) 'panel Draw xuất hiện'
}

# --- 5. Phục hồi, rồi ĐỌC LẠI xác nhận đã phục hồi -------------------------
Invoke-AcadCommand -Document $doc -Command "._UNDO`r1`r"
$r = Wait-UiState -Probe { $doc.ModelSpace.Count } -Expected $before
Check 'undo -> model về nguyên trạng' $r.Ok "ModelSpace về $($r.Value) sau $($r.ElapsedMs)ms"

# --- 6. Đóng sạch qua COM, không kill cứng ---------------------------------
try {
    if ($acad.Documents.Count -gt 0) { $doc.Close($false) }
    $acad.Quit()
    Start-Sleep -Seconds 3
} catch { }
$left = Stop-HostApp -Name 'acad' -SettleSec 2
Check 'đóng sạch qua COM' ($left -eq 0) "phải kill cứng: $left"

""
if ($fail -eq 0) { "TAT CA PASS" } else { "$fail BUOC FAIL" }
exit $fail
