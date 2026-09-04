#!/usr/bin/env bash
# Cập nhật skill revit-addin-mcp-workflow lên bản mới nhất từ GitHub, và build lại
# UiAutomationToolkit nếu source của nó thay đổi.
#
# Dùng: ./update-skill.sh   (chạy từ bất kỳ đâu, script tự tìm đúng thư mục của nó)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d .git ]; then
  echo "LỖI: '$SCRIPT_DIR' không phải git repo — skill này có vẻ được cài bằng cách" >&2
  echo "copy tay (.skill/zip) thay vì 'git clone'. Xoá thư mục này và clone lại:" >&2
  echo "  git clone https://github.com/ninhpham96/Revit-mcp-autotest.git \"$SCRIPT_DIR\"" >&2
  exit 1
fi

echo "==> Kiểm tra thay đổi chưa commit trong '$SCRIPT_DIR'..."
if [ -n "$(git status --porcelain)" ]; then
  echo "LỖI: có thay đổi local chưa commit — dừng lại để tránh mất dữ liệu." >&2
  echo "Xem 'git status' trong '$SCRIPT_DIR', commit/stash rồi chạy lại." >&2
  exit 1
fi

BEFORE_HASH="$(git rev-parse HEAD)"

echo "==> git pull..."
git pull --ff-only

AFTER_HASH="$(git rev-parse HEAD)"

if [ "$BEFORE_HASH" = "$AFTER_HASH" ]; then
  echo "==> Đã ở bản mới nhất, không có gì để cập nhật."
  exit 0
fi

echo "==> Có bản mới ($BEFORE_HASH -> $AFTER_HASH)."

if git diff --name-only "$BEFORE_HASH" "$AFTER_HASH" -- assets/UiAutomationToolkit | grep -q .; then
  echo "==> assets/UiAutomationToolkit có thay đổi — build lại..."
  (cd assets/UiAutomationToolkit && dotnet build)
else
  echo "==> assets/UiAutomationToolkit không đổi, không cần build lại."
fi

echo "==> Xong. Mở phiên Claude Code mới để dùng bản skill mới nhất."
