[Unit]
Description=Minecraft Server (docker compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={{BASE_DIR}}
ExecStart=/usr/bin/docker compose up -d --wait
ExecStop=/usr/bin/docker compose stop
ExecStopPost={{BASE_DIR}}/backup.sh
TimeoutStartSec=300
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
