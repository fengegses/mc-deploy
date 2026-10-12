services:
  mc:
    image: itzg/minecraft-server
    container_name: {{CONTAINER_NAME}}
    ports:
      - "127.0.0.1:{{MC_PORT}}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "{{MC_TYPE}}"
      VERSION: "{{MC_VERSION}}"
      JAVA_VERSION: "{{JAVA_VERSION}}"
      MEMORY: "{{MC_MEMORY}}"
      CREATE_CONSOLE_IN_PIPE: "true"
      ENABLE_RCON: "true"
      RCON_PASSWORD: "{{RCON_PASSWORD}}"
      TZ: "{{TZ}}"
      UID: "{{MC_UID}}"
      GID: "{{MC_GID}}"
    volumes:
      - ./data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mc-health"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 10m
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
