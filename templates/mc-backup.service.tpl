[Unit]
Description=Minecraft backup (one-shot)
After={{SERVICE_NAME}}.service

[Service]
Type=oneshot
ExecStart={{BASE_DIR}}/backup.sh
