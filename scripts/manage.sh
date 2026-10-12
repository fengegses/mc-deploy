#!/bin/bash
# Minecraft 服务器管理脚本
set -u

MC_DIR="{{BASE_DIR}}"
COMPOSE_FILE="${MC_DIR}/docker-compose.yml"
CONTAINER="{{CONTAINER_NAME}}"
SERVICE="{{SERVICE_NAME}}"
MC_UID="{{MC_UID}}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;36m'; N='\033[0m'
info()  { echo -e "${B}[INFO]${N} $*"; }
ok()    { echo -e "${G}[OK]${N} $*"; }
warn()  { echo -e "${Y}[WARN]${N} $*"; }
fail()  { echo -e "${R}[FAIL]${N} $*"; }

preflight() {
    local need_install=()

    if ! command -v docker >/dev/null 2>&1; then
        fail "未安装 Docker"; need_install+=(docker)
    else
        ok "Docker: $(docker --version | awk '{print $3}' | tr -d ',')"
    fi

    if ! docker compose version >/dev/null 2>&1; then
        fail "未安装 docker compose 插件"; need_install+=(docker-compose-plugin)
    else
        ok "docker compose 已就绪"
    fi

    if command -v docker >/dev/null 2>&1 && ! systemctl is-active --quiet docker; then
        warn "Docker 服务未运行，尝试启动..."
        sudo systemctl start docker || fail "Docker 启动失败"
    fi

    [ -d "$MC_DIR" ] || { fail "目录 $MC_DIR 不存在"; need_install+=(mc-dir); }
    [ -f "$COMPOSE_FILE" ] || { fail "找不到 $COMPOSE_FILE"; need_install+=(compose-file); }
    [ -x "$MC_DIR/backup.sh" ] || { warn "backup.sh 不可执行"; need_install+=(backup-script); }

    if [ ${#need_install[@]} -gt 0 ]; then
        echo; fail "检测到 ${#need_install[@]} 项缺失：${need_install[*]}"
        read -rp "是否自动安装？(y/N) " ans
        [[ "$ans" =~ ^[Yy]$ ]] && auto_install "${need_install[@]}" || exit 1
    else
        echo; ok "环境自检通过"
    fi
}

auto_install() {
    for item in "$@"; do
        case "$item" in
            docker)
                curl -fsSL https://get.docker.com | sudo bash -s docker --mirror Aliyun
                sudo systemctl enable --now docker
                sudo usermod -aG docker "$USER" || true
                ok "Docker 安装完成"
                ;;
            docker-compose-plugin)
                sudo apt update && sudo apt install -y docker-compose-plugin
                ;;
            mc-dir)
                sudo mkdir -p "$MC_DIR"; ok "已创建 $MC_DIR"
                ;;
            compose-file)
                warn "请重新运行 install.sh 生成 docker-compose.yml"
                ;;
            backup-script)
                warn "backup.sh 缺失，请重新运行 install.sh"
                ;;
        esac
    done
}

cmd="${1:-help}"
case "$cmd" in
    start)     preflight; sudo systemctl start "$SERVICE" && ok "已启动" ;;
    stop)      preflight; sudo systemctl stop "$SERVICE" && ok "已停止（已触发备份）" ;;
    restart)   preflight; sudo systemctl restart "$SERVICE" && ok "已重启" ;;
    status)
        preflight
        echo "=== systemd ==="; sudo systemctl status "$SERVICE" --no-pager
        echo; echo "=== 容器 ==="; sudo docker ps --filter name=$CONTAINER
        echo; echo "=== 端口 ==="; ss -tlnp 2>/dev/null | grep -E '(25565|25575)' || warn "端口未监听"
        ;;
    log)       sudo docker logs -f "$CONTAINER" ;;
    rcon)      sudo docker exec -it "$CONTAINER" rcon-cli ;;
    cmd)
        shift
        [ $# -eq 0 ] && { echo "用法: $0 cmd \"命令\""; exit 1; }
        sudo docker exec -u "$MC_UID" "$CONTAINER" mc-send-to-console "$*"
        ;;
    backup)    preflight; sudo "$MC_DIR/backup.sh" ;;
    whitelist-add)
        [ -z "${2:-}" ] && { echo "用法: $0 whitelist-add <ID>"; exit 1; }
        sudo docker exec -i "$CONTAINER" rcon-cli "whitelist add $2" ;;
    whitelist-remove)
        [ -z "${2:-}" ] && { echo "用法: $0 whitelist-remove <ID>"; exit 1; }
        sudo docker exec -i "$CONTAINER" rcon-cli "whitelist remove $2" ;;
    whitelist-list) sudo docker exec -i "$CONTAINER" rcon-cli "whitelist list" ;;
    players)   sudo docker exec -i "$CONTAINER" rcon-cli "list" ;;
    tps)       sudo docker exec -i "$CONTAINER" rcon-cli "tps" ;;
    check)     preflight ;;
    help|*)
        cat <<EOF
用法: $0 <命令> [参数]

服务：
  start | stop | restart | status
日志与命令：
  log                     实时日志
  rcon                    进入 RCON
  cmd "命令"              发送命令到控制台
  players                 在线玩家
  tps                     TPS 状态
备份：
  backup                  手动备份
白名单：
  whitelist-add <ID>
  whitelist-remove <ID>
  whitelist-list
自检：
  check

示例：
  $0 check
  $0 cmd "lp listgroups"
  $0 whitelist-add Steve
EOF
        ;;
esac
