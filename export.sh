#!/bin/bash
# ============================================================
# 从当前系统导出配置到 files/ 和 secrets.conf
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.conf"
FILES_DIR="$SCRIPT_DIR/files"
BASE_DIR="${MC_BASE_DIR:-/opt/minecraft}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;36m'; N='\033[0m'
info()  { echo -e "${B}[INFO]${N} $*"; }
ok()    { echo -e "${G}[OK]${N} $*"; }
warn()  { echo -e "${Y}[WARN]${N} $*"; }
fail()  { echo -e "${R}[FAIL]${N} $*"; exit 1; }

# ---------- 权限检查 ----------
if [ "$(id -u)" -ne 0 ]; then
    if [ -t 0 ]; then
        info "需要读取 /etc/cloudflared/（root 权限），将以 sudo 重新运行..."
        exec sudo bash "$0" "$@"
    else
        fail "请用 sudo 运行：sudo $0"
    fi
fi

REAL_USER="${SUDO_USER:-root}"

# ---------- 确保 secrets.conf 存在 ----------
if [ ! -f "$SECRETS_FILE" ]; then
    if [ -f "$SCRIPT_DIR/secrets.conf.example" ]; then
        cp "$SCRIPT_DIR/secrets.conf.example" "$SECRETS_FILE"
        chown "$REAL_USER" "$SECRETS_FILE" 2>/dev/null || true
        info "从 example 创建了 secrets.conf"
    else
        fail "找不到 $SECRETS_FILE 和 secrets.conf.example"
    fi
fi

# ---------- 确保 python3-yaml ----------
if ! python3 -c "import yaml" 2>/dev/null; then
    info "安装 python3-yaml..."
    apt-get update -qq && apt-get install -y python3-yaml
fi

mkdir -p "$FILES_DIR"

# ---------- Python 改写 secrets.conf ----------
secrets_set() {
    local key="$1" value="$2"
    [ -z "$value" ] && return 1

    python3 - "$SECRETS_FILE" "$key" "$value" <<'PYEOF'
import sys, re
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
except FileNotFoundError:
    content = ""

pattern = re.compile(rf'^{re.escape(key)}\s*=\s*"(.*?)"\s*$', re.MULTILINE)
match = pattern.search(content)

PLACEHOLDERS = {
    'example.com', 'yourname', 'your@example.com',
    'CHANGE_ME_STRONG_PASSWORD', 'My MC Server',
    'mcserver.example.com', 'A private survival server',
}

is_placeholder = False
current = ""
if match:
    current = match.group(1)
    if not current or current in PLACEHOLDERS:
        is_placeholder = True
else:
    is_placeholder = True

if is_placeholder:
    new_line = f'{key}="{value}"'
    if match:
        content = pattern.sub(new_line, content, count=1)
    else:
        if content and not content.endswith('\n'):
            content += '\n'
        content += new_line + '\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  [填充] {key} = {value}")
    sys.exit(0)
else:
    print(f"  [跳过] {key}（已存在：{current[:30]}）")
    sys.exit(1)
PYEOF
}

FILLED=()
SKIPPED=()
MISSING=()

fill() {
    local key="$1" value="$2"
    if [ -z "$value" ]; then
        MISSING+=("$key")
        return 0
    fi
    if secrets_set "$key" "$value"; then
        FILLED+=("$key=$value")
    else
        SKIPPED+=("$key=$value")
    fi
}

echo "============================================================"
echo "  从当前系统导出配置"
echo "============================================================"
echo

# ============================================================
# 1. Cloudflare config.yml
# ============================================================
CFG_HOSTNAME=""
if [ -f /etc/cloudflared/config.yml ]; then
    cp /etc/cloudflared/config.yml "$FILES_DIR/cloudflared-config.yml.source"
    ok "复制 /etc/cloudflared/config.yml"

    eval "$(python3 - <<'PYEOF'
import sys
try:
    import yaml
    with open('/etc/cloudflared/config.yml') as f:
        cfg = yaml.safe_load(f)
    hostname = ""
    service = ""
    for rule in cfg.get('ingress', []):
        if isinstance(rule, dict) and 'hostname' in rule:
            hostname = rule['hostname']
            service = rule.get('service', '')
            break
    print(f'CFG_HOSTNAME={hostname!r}')
    print(f'CFG_SERVICE={service!r}')
    print(f'CFG_TUNNEL_ID={cfg.get("tunnel", "")!r}')
except Exception as e:
    sys.stderr.write(f"[WARN] 解析失败: {e}\n")
    print('CFG_HOSTNAME=""')
    print('CFG_SERVICE=""')
    print('CFG_TUNNEL_ID=""')
PYEOF
)"
    fill "CF_HOSTNAME" "$CFG_HOSTNAME"
    fill "CF_LOCAL_SERVICE" "$CFG_SERVICE"
    fill "CF_TUNNEL_ID" "$CFG_TUNNEL_ID"
else
    warn "未找到 /etc/cloudflared/config.yml"
fi

# ============================================================
# 2. Cloudflare credentials.json
# ============================================================
CF_CRED=$(ls /etc/cloudflared/*.json 2>/dev/null | grep -v 'config' | head -1 || true)
if [ -n "$CF_CRED" ] && [ -f "$CF_CRED" ]; then
    cp "$CF_CRED" "$FILES_DIR/cloudflared-credentials.json"
    chmod 0600 "$FILES_DIR/cloudflared-credentials.json" 2>/dev/null || true
    chown "$REAL_USER" "$FILES_DIR/cloudflared-credentials.json" 2>/dev/null || true
    ok "复制凭证到 files/cloudflared-credentials.json"

    eval "$(python3 - "$CF_CRED" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(f'CRED_ACCOUNT={data.get("AccountTag", "")!r}')
    print(f'CRED_SECRET={data.get("TunnelSecret", "")!r}')
    print(f'CRED_TUNNEL_ID={data.get("TunnelID", "")!r}')
except Exception as e:
    sys.stderr.write(f"[WARN] 解析凭证失败: {e}\n")
    print('CRED_ACCOUNT=""')
    print('CRED_SECRET=""')
    print('CRED_TUNNEL_ID=""')
PYEOF
)"
    fill "CF_ACCOUNT_TAG" "$CRED_ACCOUNT"
    fill "CF_TUNNEL_SECRET" "$CRED_SECRET"
    fill "CF_TUNNEL_ID" "$CRED_TUNNEL_ID"

    if [ -n "$CFG_HOSTNAME" ]; then
        ROOT_DOMAIN=$(echo "$CFG_HOSTNAME" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF}')
        fill "CF_DOMAIN" "$ROOT_DOMAIN"
    fi
else
    warn "未找到 /etc/cloudflared/*.json"
fi

# ============================================================
# 3. RCON 密码（两级回退）
# ============================================================
RCON_PW=""

# 优先：docker-compose.yml
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    RCON_PW=$(grep -oP 'RCON_PASSWORD:\s*"?\K[^"]+' "$COMPOSE_FILE" 2>/dev/null | head -1 || true)
    [ -n "$RCON_PW" ] && info "从 docker-compose.yml 读到 RCON_PASSWORD"
fi

# 回退：容器内 server.properties
if [ -z "$RCON_PW" ]; then
    RCON_PW=$(docker exec mc-server grep '^rcon.password=' /data/server.properties 2>/dev/null \
              | cut -d= -f2 | tr -d '\r' || true)
    [ -n "$RCON_PW" ] && info "从容器内 server.properties 读到 rcon.password"
fi

# 回退：容器内 .rcon-cli.yaml
if [ -z "$RCON_PW" ]; then
    RCON_PW=$(docker exec mc-server sh -c 'cat /data/.rcon-cli.yaml 2>/dev/null' \
              | grep -oP 'password:\s*\K.*' | tr -d '"' | tr -d '\r' | head -1 || true)
    [ -n "$RCON_PW" ] && info "从容器内 .rcon-cli.yaml 读到 password"
fi

if [ -n "$RCON_PW" ]; then
    fill "RCON_PASSWORD" "$RCON_PW"
else
    warn "无法读取 RCON 密码"
    MISSING+=("RCON_PASSWORD")
fi

# ============================================================
# 4. 参考文件
# ============================================================
if [ -f "$BASE_DIR/data/server.properties" ]; then
    cp "$BASE_DIR/data/server.properties" \
       "$SCRIPT_DIR/configs/server.properties.reference"
    chown "$REAL_USER" "$SCRIPT_DIR/configs/server.properties.reference" 2>/dev/null || true
    ok "复制 server.properties 作为参考"
fi

chown "$REAL_USER" "$SECRETS_FILE" 2>/dev/null || true

# ============================================================
# 5. 报告
# ============================================================
echo
echo "============================================================"
echo "  导出结果"
echo "============================================================"

for item in "${FILLED[@]:-}"; do
    [ -z "$item" ] && continue
    k="${item%%=*}"; v="${item#*=}"
    printf "  ${G}✓${N} %-22s %s\n" "$k" "$v"
done

for item in "${SKIPPED[@]:-}"; do
    [ -z "$item" ] && continue
    k="${item%%=*}"; v="${item#*=}"
    printf "  ${B}·${N} %-22s %s ${B}(已存在)${N}\n" "$k" "$v"
done

for k in "${MISSING[@]:-}"; do
    [ -z "$k" ] && continue
    printf "  ${Y}?${N} %-22s ${Y}未找到，需手动填${N}\n" "$k"
done

if grep -qE '^CF_TUNNEL_TOKEN=""' "$SECRETS_FILE" 2>/dev/null; then
    printf "  ${B}i${N} %-22s ${B}为空（文件模式无需填）${N}\n" "CF_TUNNEL_TOKEN"
fi

echo
echo "生成的文件："
echo "  → files/cloudflared-config.yml.source"
echo "  → files/cloudflared-credentials.json"
echo "  → secrets.conf"
echo
echo "下一步："
echo "  sudo ./install.sh"
