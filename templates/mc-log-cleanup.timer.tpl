[Unit]
Description=Clean Minecraft logs daily

[Timer]
OnCalendar=daily
Persistent=true
Unit={{LOG_CLEANUP_SERVICE}}.service

[Install]
WantedBy=timers.target
