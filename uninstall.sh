#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/deploy.conf"

echo "卸载 Minecraft 服务..."
echo "  部署目录：$BASE_DIR"

# 停止所有相关服务
for svc in "$SERVICE_NAME" "${BACKUP_SERVICE}.timer" "${BACKUP_SERVICE}.service" \
           "${LOG_CLEANUP_SERVICE}.timer" "${LOG_CLEANUP_SERVICE}.service"; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

# 卸载 cloudflared 服务
if [ "${1:-}" = "--with-cloudflared" ]; then
    systemctl stop cloudflared-mc 2>/dev/null || true
    systemctl disable cloudflared-mc 2>/dev/null || true
    rm -f /etc/systemd/system/cloudflared-mc.service
    rm -rf /etc/cloudflared
    echo "[OK] cloudflared 配置已删除"
fi

# 删除 systemd 单元
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "/etc/systemd/system/${BACKUP_SERVICE}.service"
rm -f "/etc/systemd/system/${BACKUP_SERVICE}.timer"
rm -f "/etc/systemd/system/${LOG_CLEANUP_SERVICE}.service"
rm -f "/etc/systemd/system/${LOG_CLEANUP_SERVICE}.timer"
systemctl daemon-reload

# 删除别名
rm -f /etc/profile.d/mc-alias.sh

# 询问是否删除数据目录
read -rp "是否删除 $BASE_DIR（含世界数据）？(y/N) " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    rm -rf "$BASE_DIR"
    echo "[OK] 已删除 $BASE_DIR"
else
    echo "[保留] $BASE_DIR 保留"
fi

echo "卸载完成。"
