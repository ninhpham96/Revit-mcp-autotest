<#
    Mẫu smoke test cho add-in Revit — copy rồi đổi -RibbonTab và phần Probe.

    Trả lời đúng một câu hỏi mà "build sạch" không trả lời được: add-in có thật sự
    sống qua OnStartup trong Revit thật và dựng được ribbon không.

    File này lưu UTF-8 CÓ BOM. Xem references/04-powershell-traps.md.
#>
param(
    [string]$Year = '2026',
    [string]$RibbonTab = 'MiniApps',
    [string]$LogGlob = "$env:LOCALAPPDATA\MiniAppLoader\logs\*.log",
    [string]$DiscoveryPath
)

Import-Module (Join-Path $PSScriptRoot '..\scripts\HostUiTest.psm1') -Force

$fail = 0
function Check($label, $ok, $detail) {
    $mark = 'OK  '
    if (-not $ok) { $mark = 'FAIL'; $script:fail++ }
    "{0} {1,-42} {2}" -f $mark, $label, $detail
}

# --- 0. Khởi động sạch -----------------------------------------------------
# Mốc thời gian LẤY TRƯỚC khi mở host: log của add-in được ghi nối tiếp qua
# nhiều phiên, nên "log có dòng ERR" mà không chặn mốc sẽ fail vì lỗi của lần
# chạy tuần trước. Đây là lỗi thật đã gặp: 10 dòng lỗi, không dòng nào của
# lần chạy này.
$t0 = Get-Date
[void](Stop-HostApp -Name 'Revit')

# -DismissExtra: dialog riêng của máy này. Khớp theo code point vì tiêu đề có
# thể là tiếng Nhật/Trung và script không BOM sẽ đọc sai (xem 04-powershell-traps).
$extra = @(
    @{ Title = (Get-UiText 0x30A2,0x30C9,0x30A4,0x30F3,0x5229,0x7528); Button = 'OK' }
)

$h = Start-RevitHost -Year $Year -DismissExtra $extra -DiscoveryPath $DiscoveryPath
$rpid = $h.Process.Id
Check "Revit $Year sẵn sàng" $true "$($h.Title)"
"     đã xử lý lúc khởi động: $($h.Notes -join '; ')"

$hadFailure = @($h.Notes | Where-Object { $_ -match 'EXTERNAL TOOL FAILURE' }).Count
Check 'add-in sống qua OnStartup' ($hadFailure -eq 0) 'không có External Tool Failure'

"     cửa sổ host đang mở:"
Get-HostWindow -ProcessId $rpid | ForEach-Object { "       class='{0}' title='{1}'" -f $_.Class, $_.Title }

$closed = Close-StrayWindow -ProcessId $rpid -KeepPattern 'Autodesk Revit'
Check 'không còn modal chặn cây UIA' ($closed.Count -eq 0) "đã đóng: $($closed -join ', ')"
Set-HostForeground -ProcessId $rpid

# --- 1. Ribbon của add-in có thật sự dựng được không ------------------------
$sw = [Diagnostics.Stopwatch]::StartNew()
$tab = Find-UiElement -ProcessId $rpid -Name $RibbonTab -Match -TimeoutMs 15000
Check "thấy tab ribbon '$RibbonTab'" ($null -ne $tab) "$($sw.ElapsedMilliseconds)ms, type=$(if ($tab) { $tab.Current.ControlType.ProgrammaticName -replace 'ControlType\.','' })"

# --- 2. Khẳng định bằng NGUỒN NGOÀI UI -------------------------------------
# Log của add-in là nguồn độc lập: nó chứng minh code đã chạy, còn UI thì chỉ
# chứng minh WPF đã vẽ. Đổi đoạn này sang marker/config của add-in bạn.
if (Test-Path (Split-Path $LogGlob)) {
    $r = Wait-UiState -TimeoutMs 20000 -Expected $true -Probe {
        @(Get-Content $LogGlob -Encoding UTF8 -ErrorAction SilentlyContinue).Count -gt 0
    }
    Check 'add-in ghi được log riêng' $r.Ok "sau $($r.ElapsedMs)ms"

    # Chỉ xét dòng của LẦN CHẠY NÀY, so theo mốc $t0 lấy trước khi mở host.
    $errors = @(
        Get-Content $LogGlob -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object {
            if ($_ -notmatch '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { return $false }
            if ([datetime]$Matches[1] -lt $t0) { return $false }
            $_ -match '\[(ERR|FTL)\]'
        })
    Check 'lần chạy này không có ERR/FTL' ($errors.Count -eq 0) "$($errors.Count) dòng lỗi mới"
    if ($errors.Count -gt 0) { $errors | Select-Object -First 5 | ForEach-Object { "       $_" } }
}
else {
    "SKIP thư mục log không tồn tại: $(Split-Path $LogGlob)"
}

# --- 3. Đóng lại -----------------------------------------------------------
[void](Stop-HostApp -Name 'Revit' -SettleSec 3)
Check 'đã đóng Revit' (@(Get-Process Revit -ErrorAction SilentlyContinue).Count -eq 0) ''

""
if ($fail -eq 0) { "TAT CA PASS" } else { "$fail BUOC FAIL" }
exit $fail
