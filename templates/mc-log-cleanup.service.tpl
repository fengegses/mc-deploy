[Unit]
Description=Minecraft log cleanup
After={{SERVICE_NAME}}.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'find {{BASE_DIR}}/data/logs -name "*.log.gz" -mtime +7 -delete; find {{BASE_DIR}}/data/logs -name "*.log" -mtime +3 -delete'
