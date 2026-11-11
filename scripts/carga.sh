#!/usr/bin/env bash
# Generador de carga HTTP para el laboratorio de elasticidad con KEDA.
#
# Lanza rondas de peticiones concurrentes contra /api/work. Cada petición
# consume CPU durante `ms` milisegundos, elevando la utilización de CPU
# del pod y disparando el escalado gestionado por KEDA.
#
# Uso:
#   ./carga.sh
#   CONCURRENCIA=40 DURACION=600 ./carga.sh
#   URL="http://localhost:8080/api/work?ms=500" ./carga.sh

set -u

URL="${URL:-http://localhost:8080/api/work?ms=300}"
CONCURRENCIA="${CONCURRENCIA:-20}"
DURACION="${DURACION:-300}"

fin=$((SECONDS + DURACION))
ronda=0

echo "Generando carga: ${CONCURRENCIA} req concurrentes durante ${DURACION} s"
echo "URL: ${URL}"
echo "Pulsa Ctrl+C para detener."
echo

while [ $SECONDS -lt $fin ]; do
    ronda=$((ronda + 1))
    seq "$CONCURRENCIA" | xargs -P "$CONCURRENCIA" -I{} \
        curl -s -o /dev/null -w "%{http_code} " "$URL"
    echo " [$(date +%H:%M:%S)] ronda ${ronda} completada"
done

echo
echo "Carga finalizada."
