## 敏感信息管理

所有敏感数据集中在 `secrets.conf`，它**永不提交到 Git**。

### 首次部署

1. `cp secrets.conf.example secrets.conf`
2. `nano secrets.conf`，填入：
   - `CF_DOMAIN`、`CF_HOSTNAME`
   - `CF_TUNNEL_TOKEN`（推荐）或保留空用文件模式
   - `RCON_PASSWORD`
3. `sudo ./install.sh`

### 迁移已有系统

1. 在旧机器上：`sudo ./export.sh`
2. 检查 `secrets.conf` 是否正确填充
3. 打包：`./pack-to-usb.sh /media/USB`
4. 新机器：解压后 `sudo ./install.sh`

### 三种文件的区别

| 文件 | 用途 | 是否入库 | 是否含敏感 |
|---|---|---|---|
| `deploy.conf` | 公共配置 | ✅ | ❌ |
| `secrets.conf` | 敏感配置 | ❌ | ✅ |
| `files/cloudflared-credentials.json` | 隧道凭证 | ❌ | ✅ |
| `files/cloudflared-config.yml.source` | 参考副本 | ❌ | ❌ |
| `templates/cloudflared-config.yml.tpl` | 模板 | ✅ | ❌ |