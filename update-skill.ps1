<#
.SYNOPSIS
    Cập nhật skill revit-cad-addin-autotest lên bản mới nhất từ GitHub, và build lại
    UiAutomationToolkit nếu source của nó thay đổi.

.EXAMPLE
    .\update-skill.ps1
#>

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
Set-Location $ScriptDir

if (-not (Test-Path (Join-Path $ScriptDir ".git"))) {
    Write-Error @"
'$ScriptDir' không phải git repo — skill này có vẻ được cài bằng cách copy tay
(.skill/zip) thay vì 'git clone'. Xoá thư mục này và clone lại:
  git clone https://github.com/ninhpham96/Revit-mcp-autotest.git "$ScriptDir"
"@
}

Write-Host "==> Kiểm tra thay đổi chưa commit trong '$ScriptDir'..."
$status = git status --porcelain
if ($status) {
    Write-Error "Có thay đổi local chưa commit — dừng lại để tránh mất dữ liệu. Xem 'git status', commit/stash rồi chạy lại."
}

# BOM guard: PS 5.1 doc file UTF-8 khong BOM theo ANSI va lam hong AM THAM moi ky
# tu ngoai ASCII. Loi nay khong bao gi ca, phep so khop chi lang le truot.
function Test-ScriptBom {
    $bad = @()
    foreach ($f in (Get-ChildItem -Path "scripts\*.psm1", "examples\*.ps1" -ErrorAction SilentlyContinue)) {
        $b = [IO.File]::ReadAllBytes($f.FullName)
        if ($b.Length -lt 3 -or $b[0] -ne 239 -or $b[1] -ne 187 -or $b[2] -ne 191) { $bad += $f.Name }
    }
    if ($bad.Count -gt 0) {
        Write-Warning "Thieu UTF-8 BOM: $($bad -join ', ') - PowerShell 5.1 se doc sai ky tu co dau."
    } else {
        Write-Host "==> BOM cua script PowerShell: OK."
    }
}

$beforeHash = git rev-parse HEAD

Write-Host "==> git pull..."
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw "git pull thất bại." }

$afterHash = git rev-parse HEAD

if ($beforeHash -eq $afterHash) {
    Write-Host "==> Đã ở bản mới nhất, không có gì để cập nhật."
    Test-ScriptBom
    exit 0
}

Write-Host "==> Có bản mới ($beforeHash -> $afterHash)."

$changedFiles = git diff --name-only $beforeHash $afterHash -- assets/UiAutomationToolkit
if ($changedFiles) {
    Write-Host "==> assets/UiAutomationToolkit có thay đổi — build lại..."
    Push-Location (Join-Path $ScriptDir "assets\UiAutomationToolkit")
    try { dotnet build } finally { Pop-Location }
} else {
    Write-Host "==> assets/UiAutomationToolkit không đổi, không cần build lại."
}

Test-ScriptBom

Write-Host "==> Xong. Mở phiên Claude Code mới để dùng bản skill mới nhất."
