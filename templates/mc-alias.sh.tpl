# Minecraft 管理别名（系统级，/etc/profile.d/mc-alias.sh）
alias mcc='sudo docker exec -u {{MC_UID}} {{CONTAINER_NAME}} mc-send-to-console'
alias mclog='sudo docker logs -f {{CONTAINER_NAME}}'
alias mcstatus='sudo systemctl status {{SERVICE_NAME}} --no-pager'
alias mctps='sudo docker exec -u {{MC_UID}} {{CONTAINER_NAME}} mc-send-to-console tps'
alias mcbackup='sudo {{BASE_DIR}}/backup.sh'
