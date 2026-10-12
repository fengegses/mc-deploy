#!/bin/bash
# 打包完整项目（含敏感文件）到 U 盘
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USB_DIR="${1:-/media/$USER/USB}"
if [ ! -d "$USB_DIR" ]; then
    echo "用法: $0 <U盘挂载路径>"
    echo "例如: $0 /media/fengsage/USB"
    exit 1
fi

DATE=$(date +%F_%H%M)
ARCHIVE="$USB_DIR/mc-deploy-full-$DATE.tar.gz"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROJ_NAME="$(basename "$SCRIPT_DIR")"

echo "打包完整项目到 $ARCHIVE ..."
cd "$PARENT_DIR"

tar -czf "$ARCHIVE" \
    --exclude="${PROJ_NAME}/data" \
    --exclude="${PROJ_NAME}/backups" \
    --exclude="${PROJ_NAME}/.git" \
    --exclude="${PROJ_NAME}/configs/server.properties.reference" \
    --exclude="${PROJ_NAME}/files/cloudflared-config.yml.source" \
    "$PROJ_NAME/"

SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "[OK] 已保存：$ARCHIVE ($SIZE)"
echo "     含 secrets.conf 和 files/cloudflared-credentials.json"
echo "     不含世界存档"
