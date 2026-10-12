#!/bin/bash
# ============================================================
# Minecraft 服务端一键部署
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/deploy.conf" ]; then
    echo "[错误] 找不到 $SCRIPT_DIR/deploy.conf"
    exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/deploy.conf"

# ---------- 检查 secrets.conf ----------
if [ "$SECRETS_LOADED" -ne 1 ]; then
    cat <<EOF
[错误] 缺少 secrets.conf

首次部署请执行：
  cd $SCRIPT_DIR
  cp secrets.conf.example secrets.conf
  nano secrets.conf      # 填入域名、Token、密码

如果从 U 盘恢复，把 U 盘上的 secrets.conf 拷回 $SCRIPT_DIR/
EOF
    exit 1
fi

# ---------- 检查关键字段 ----------
check_secrets() {
    local missing=()
    [ -z "${CF_DOMAIN:-}" ]     && missing+=(CF_DOMAIN)
    [ -z "${CF_HOSTNAME:-}" ]   && missing+=(CF_HOSTNAME)
    [ -z "${RCON_PASSWORD:-}" ] && missing+=(RCON_PASSWORD)

    # 隧道：token 或凭证文件至少一个
    if [ -z "${CF_TUNNEL_TOKEN:-}" ] && \
       [ ! -f "$SCRIPT_DIR/files/cloudflared-credentials.json" ]; then
        missing+=(CF_TUNNEL_TOKEN_or_credentials)
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "[错误] secrets.conf 缺少关键字段：${missing[*]}"
        echo "请编辑 $SCRIPT_DIR/secrets.conf 补充后重试"
        exit 1
    fi
}

# ============================================================
# 工具函数
# ============================================================
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;36m'; N='\033[0m'
info()  { echo -e "${B}[INFO]${N} $*"; }
ok()    { echo -e "${G}[OK]${N} $*"; }
warn()  { echo -e "${Y}[WARN]${N} $*"; }
fail()  { echo -e "${R}[FAIL]${N} $*"; exit 1; }

# sed 替换的转义函数
esc_sed() {
    printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

render_tpl() {
    local src="$1" dst="$2"

    # 收集所有替换对，做转义
    local args=()
    local k v
    for k in BASE_DIR CONTAINER_NAME MC_PORT RCON_PORT RCON_PASSWORD \
             MC_TYPE MC_VERSION JAVA_VERSION MC_MEMORY MC_UID MC_GID TZ \
             BACKUP_KEEP BACKUP_MIN_SPACE_MB BACKUP_PIGZ_THREADS \
             SERVICE_NAME BACKUP_SERVICE LOG_CLEANUP_SERVICE \
             CF_HOSTNAME CF_LOCAL_SERVICE CF_TUNNEL_ID CF_ACCOUNT_TAG \
             CF_TUNNEL_SECRET; do
        v="$(eval "printf '%s' \"\${$k:-}\"")"
        args+=(-e "s|{{${k}}}|$(esc_sed "$v")|g")
    done

    sed "${args[@]}" "$src" > "$dst"
}

# ============================================================
# 1. 环境检测
# ============================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "请用 root 或 sudo 运行：sudo ./install.sh"
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        info "系统：$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    fi
}

# ============================================================
# 2. 依赖安装
# ============================================================
install_deps() {
    info "检查依赖..."
    local pkgs=()

    command -v curl  >/dev/null 2>&1 || pkgs+=(curl)
    command -v wget  >/dev/null 2>&1 || pkgs+=(wget)
    command -v pigz  >/dev/null 2>&1 || pkgs+=(pigz)
    command -v tar   >/dev/null 2>&1 || pkgs+=(tar)
    command -v flock >/dev/null 2>&1 || pkgs+=(util-linux)
    python3 -c "import yaml" 2>/dev/null || pkgs+=(python3-yaml)

    if [ ${#pkgs[@]} -gt 0 ]; then
        info "安装包：${pkgs[*]}"
        apt-get update
        apt-get install -y "${pkgs[@]}"
    fi

    if ! command -v docker >/dev/null 2>&1; then
        info "安装 Docker..."
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        systemctl enable --now docker
    else
        ok "Docker: $(docker --version | awk '{print $3}' | tr -d ',')"
    fi

    if ! docker compose version >/dev/null 2>&1; then
        info "安装 docker compose 插件..."
        apt-get install -y docker-compose-plugin
    fi
}

# ============================================================
# 3. 目录
# ============================================================
create_dirs() {
    info "创建目录 $BASE_DIR ..."
    mkdir -p "$BASE_DIR" "$BASE_DIR/data" "$BASE_DIR/backups"
    chown -R "${MC_UID}:${MC_GID}" "$BASE_DIR/data" 2>/dev/null || true
    ok "目录就绪"
}

# ============================================================
# 4. 渲染模板
# ============================================================
render_templates() {
    info "生成配置文件..."

    render_tpl "$SCRIPT_DIR/templates/docker-compose.yml.tpl" \
               "$BASE_DIR/docker-compose.yml"

    install -m 0755 "$SCRIPT_DIR/scripts/backup.sh" "$BASE_DIR/backup.sh"
    install -m 0755 "$SCRIPT_DIR/scripts/manage.sh" "$BASE_DIR/manage.sh"
    render_tpl "$BASE_DIR/backup.sh" "$BASE_DIR/backup.sh"
    render_tpl "$BASE_DIR/manage.sh" "$BASE_DIR/manage.sh"

    render_tpl "$SCRIPT_DIR/templates/mc-server.service.tpl" \
               "/etc/systemd/system/${SERVICE_NAME}.service"
    render_tpl "$SCRIPT_DIR/templates/mc-backup.service.tpl" \
               "/etc/systemd/system/${BACKUP_SERVICE}.service"
    render_tpl "$SCRIPT_DIR/templates/mc-backup.timer.tpl" \
               "/etc/systemd/system/${BACKUP_SERVICE}.timer"
    render_tpl "$SCRIPT_DIR/templates/mc-log-cleanup.service.tpl" \
               "/etc/systemd/system/${LOG_CLEANUP_SERVICE}.service"
    render_tpl "$SCRIPT_DIR/templates/mc-log-cleanup.timer.tpl" \
               "/etc/systemd/system/${LOG_CLEANUP_SERVICE}.timer"

    render_tpl "$SCRIPT_DIR/templates/mc-alias.sh.tpl" \
               "/etc/profile.d/mc-alias.sh"
    chmod 0755 /etc/profile.d/mc-alias.sh

    if [ ! -f "$BASE_DIR/data/eula.txt" ]; then
        cp "$SCRIPT_DIR/configs/eula.txt" "$BASE_DIR/data/eula.txt"
    fi

    ok "配置生成完毕"
}

# ============================================================
# 5. Cloudflare Tunnel
# ============================================================
setup_cloudflared() {
    if ! command -v cloudflared >/dev/null 2>&1; then
        info "安装 cloudflared..."
        mkdir -p --mode=0755 /usr/share/keyrings
        curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
            | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
            > /etc/apt/sources.list.d/cloudflared.list
        apt-get update
        apt-get install -y cloudflared
    else
        ok "cloudflared 已安装"
    fi

    # 方式一：Token 模式
    if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
        info "使用 Token 模式配置隧道..."
        cloudflared service uninstall 2>/dev/null || true
        cloudflared service install "$CF_TUNNEL_TOKEN"
        ok "隧道已配置（token 模式）"
        return 0
    fi

    # 方式二：文件模式
    local cred="$SCRIPT_DIR/files/cloudflared-credentials.json"
    if [ ! -f "$cred" ]; then
        warn "未配置 CF_TUNNEL_TOKEN，且 $cred 不存在，跳过隧道设置"
        warn "如需启用隧道：在 secrets.conf 填 token，或先运行 ./export.sh"
        return 0
    fi

    info "使用文件模式配置隧道..."
    mkdir -p /etc/cloudflared

    # 用 secrets.conf 里的 CF_TUNNEL_ID，或从凭证里读
    local uuid="${CF_TUNNEL_ID:-}"
    if [ -z "$uuid" ]; then
        uuid=$(python3 -c "import json,sys;print(json.load(open('$cred')).get('TunnelID',''))" 2>/dev/null || true)
    fi
    if [ -z "$uuid" ]; then
        fail "无法确定隧道 UUID（检查 secrets.conf 的 CF_TUNNEL_ID 或 files/credentials）"
    fi

    # 拷凭证
    install -m 0600 "$cred" "/etc/cloudflared/${uuid}.json"
    ok "凭证已安装：/etc/cloudflared/${uuid}.json"

    # 从模板生成 config.yml
    render_tpl "$SCRIPT_DIR/templates/cloudflared-config.yml.tpl" \
               /etc/cloudflared/config.yml
    chmod 0644 /etc/cloudflared/config.yml

    # systemd 服务
    render_tpl "$SCRIPT_DIR/templates/cloudflared-mc.service.tpl" \
               "/etc/systemd/system/cloudflared-mc.service"

    systemctl daemon-reload
    systemctl enable cloudflared-mc
    systemctl restart cloudflared-mc
    ok "隧道服务已启动：cloudflared-mc"
}

# ============================================================
# 6. 启动服务
# ============================================================
enable_services() {
    info "启用 systemd 服务..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl enable "${BACKUP_SERVICE}.timer"
    systemctl enable "${LOG_CLEANUP_SERVICE}.timer"

    systemctl start "$SERVICE_NAME"
    systemctl start "${BACKUP_SERVICE}.timer"
    systemctl start "${LOG_CLEANUP_SERVICE}.timer"
    ok "服务已启动"
}

# ============================================================
# 主流程
# ============================================================
main() {
    cat <<EOF
============================================================
  Minecraft 服务端部署
------------------------------------------------------------
  部署目录：$BASE_DIR
  服务名：$SERVICE_NAME
  版本：$MC_VERSION ($MC_TYPE) / Java $JAVA_VERSION
  端口：$MC_PORT
============================================================
EOF

    check_root
    check_secrets
    check_os
    install_deps
    create_dirs
    render_templates
    setup_cloudflared
    enable_services

    cat <<EOF

============================================================
  部署完成
------------------------------------------------------------
  状态：systemctl status $SERVICE_NAME
  日志：journalctl -u $SERVICE_NAME -f
  容器日志：docker logs -f $CONTAINER_NAME
  管理：$BASE_DIR/manage.sh
  备份：$BASE_DIR/backup.sh

  别名（重新登录后生效）：
    mcc "list"            # 发送命令到控制台
    mclog                 # 实时日志
    mcstatus              # 服务状态
============================================================
EOF
}

main "$@"
