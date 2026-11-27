# Imagen del cliente web de RPG Mapping (ADR 016).
# Se construye desde la raíz del repositorio, con la exportación Web hecha:
#   pwsh tools/build_docker.ps1
FROM caddy:2.10-alpine

COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY build/web/ /srv/

# Los certificados internos de Caddy viven en /data: monta un volumen para
# que no cambien en cada arranque (los jugadores aceptarían uno nuevo).
VOLUME /data
EXPOSE 443
