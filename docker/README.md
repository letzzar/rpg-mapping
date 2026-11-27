# Imagen Docker del cliente web (ADR 016)

Lo normal es que la app del DM sirva ella misma la página de los jugadores
(no hace falta nada más). Esta imagen es la **alternativa para quien tiene un
NAS o un servidor siempre encendido**: sirve el cliente web estático y hace de
proxy inverso del WebSocket hacia la app del DM.

```
móvil del jugador ──HTTPS/WSS──▶ contenedor (Caddy) ──WSS /ws──▶ app del DM
                     (certificado del contenedor)       (autofirmado, no se verifica)
```

Página y WebSocket salen del mismo origen (el contenedor), así que el jugador
solo acepta un certificado y no hay contenido mixto. El DM sigue siendo la
autoridad: el contenedor no guarda partida ni filtra nada, solo reenvía.

## Construir

Desde la raíz del repositorio (exporta el cliente Web y construye):

```powershell
pwsh tools/build_docker.ps1
```

Para llevarla al NAS sin registro: `docker save rpg-mapping-web:latest -o rpg-mapping-web.tar`
y en el NAS `docker load -i rpg-mapping-web.tar`.

## Arrancar

```powershell
docker run -d --name rpg-mapping-web -p 8443:443 -v rpg-mapping-data:/data -e DM_ADDR=192.168.1.20:47830 rpg-mapping-web:latest
```

o con el `docker-compose.yml` de esta carpeta (`docker compose up -d`).

| Variable | Por defecto | Qué es |
|---|---|---|
| `DM_ADDR` | `host.docker.internal:47830` | IP:puerto de la app del DM ("Partida en red"). |
| `SITE_ADDRESS` | cualquiera | Nombre o IP con que se abre la página (p. ej. `nas.local`). |
| `TLS` | `internal` | Certificado interno de Caddy, o `"/certs/cert.pem /certs/key.pem"` montando `/certs`. |

El volumen `/data` guarda el certificado interno: sin él, cambia en cada
arranque y los jugadores tendrían que aceptarlo otra vez.

## En la app del DM

1. Abre **Partida en red** y pulsa **Abrir partida** (el puerto debe coincidir con `DM_ADDR`).
2. En **Pública:** escribe la dirección del contenedor, p. ej. `https://nas.local:8443`.
   Los enlaces y el QR de los jugadores usan entonces esa dirección. Se recuerda.
3. La primera vez cada jugador acepta el certificado del contenedor en su navegador.

Si el cortafuegos del equipo del DM pregunta, permite la conexión entrante de
RPG Mapping en la red privada: el contenedor necesita llegar a su puerto.

## Probado

- Página y `.wasm` servidos por HTTPS con certificado interno, por nombre y por IP.
- Certificado montado (`TLS`): el contenedor sirve exactamente ese certificado.
- Partida real: Chrome abre el enlace de invitación del contenedor y el DM ve
  al jugador conectado a través del proxy (`/ws`).
