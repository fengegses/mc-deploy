#!/bin/bash
# Minecraft 世界备份（热备份 + pigz 多核压缩 + 自动清理）
set -u

BASE_DIR="{{BASE_DIR}}"
BACKUP_DIR="${BASE_DIR}/backups"
DATA_DIR="${BASE_DIR}/data"
CONTAINER="{{CONTAINER_NAME}}"
KEEP={{BACKUP_KEEP}}
MIN_SPACE_MB={{BACKUP_MIN_SPACE_MB}}
PIGZ_THREADS={{BACKUP_PIGZ_THREADS}}
LOG=/var/log/mc-backup.log
LOCK=/var/lock/mc-backup.lock

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

exec 9>"$LOCK"
if ! flock -n 9; then
    log "上一次备份还在运行，跳过本次"
    exit 0
fi

mkdir -p "$BACKUP_DIR"
DATE=$(date +%F_%H%M%S)
TARGET="$BACKUP_DIR/world-$DATE.tar.gz"

AVAIL_MB=$(df -m "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAIL_MB" -lt "$MIN_SPACE_MB" ]; then
    log "剩余空间不足 (${AVAIL_MB}MB < ${MIN_SPACE_MB}MB)，跳过备份"
    exit 1
fi

RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")

SAVE_OFF_DONE=false
cleanup() {
    if [ "$SAVE_OFF_DONE" = "true" ]; then
        docker exec -i "$CONTAINER" rcon-cli save-on >/dev/null 2>&1
        log "已恢复 save-on"
    fi
    if [ -f "$TARGET" ] && [ "${PACK_OK:-false}" != "true" ]; then
        rm -f "$TARGET"
        log "打包失败，已删除半成品"
    fi
}
trap cleanup EXIT

if [ "$RUNNING" = "true" ]; then
    log "容器运行中，执行热备份"
    if docker exec -i "$CONTAINER" rcon-cli save-off >/dev/null 2>&1; then
        SAVE_OFF_DONE=true
        docker exec -i "$CONTAINER" rcon-cli save-all flush >/dev/null 2>&1
        sleep 3
    else
        log "警告：save-off 失败，RCON 可能未就绪，继续备份"
    fi
else
    log "容器未运行，执行冷备份"
fi

cd "$BASE_DIR"
PACK_OK=false

EXCLUDES=(
    --exclude='data/logs'
    --exclude='data/cache'
    --exclude='data/crash-reports'
    --exclude='data/libraries'
    --exclude='data/versions'
)

if command -v pigz >/dev/null 2>&1; then
    tar "${EXCLUDES[@]}" -cf - data 2>/dev/null | pigz -p "$PIGZ_THREADS" > "$TARGET"
    PIPE_RC=("${PIPESTATUS[@]}")
    if [ "${PIPE_RC[0]}" -eq 0 ] && [ "${PIPE_RC[1]}" -eq 0 ]; then
        PACK_OK=true
    fi
else
    tar "${EXCLUDES[@]}" -czf "$TARGET" data 2>/dev/null
    [ $? -eq 0 ] && PACK_OK=true
fi

ls -t "$BACKUP_DIR"/world-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm

if [ "$PACK_OK" = "true" ]; then
    SIZE=$(du -h "$TARGET" | cut -f1)
    log "备份完成: $(basename "$TARGET") ($SIZE)"
else
    log "备份失败"
    exit 1
fi
