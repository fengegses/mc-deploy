tunnel: {{CF_TUNNEL_ID}}
credentials-file: /etc/cloudflared/{{CF_TUNNEL_ID}}.json
ingress:
  - hostname: {{CF_HOSTNAME}}
    service: {{CF_LOCAL_SERVICE}}
  - service: http_status:404
