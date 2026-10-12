[Unit]
Description=Backup Minecraft every 3 hours

[Timer]
OnBootSec=15min
OnUnitActiveSec=3h
Persistent=true
Unit={{BACKUP_SERVICE}}.service

[Install]
WantedBy=timers.target
