# Paso 4 (opcional) — Escalado por peticiones promedio con Prometheus

El escenario principal usa **CPU** como señal de escalado (peticiones →
CPU → réplicas). Esta extensión escala sobre la métrica literal
**peticiones/segundo promedio por pod**, usando **Prometheus** como fuente
de métricas y el scaler `prometheus` de KEDA.

El microservicio ya expone las métricas HTTP de Micrometer en
`/actuator/prometheus` (`http_server_requests_seconds_count`), así que no
hace falta cambiar código.

## Prerrequisito

Laboratorio funcionando hasta el paso 3 (`elasticity-api` desplegado,
KEDA en el namespace `keda`, metrics-server activo).

## 1. Instalar Prometheus en `elasticity-lab`

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/prometheus -n elasticity-lab \
  --set server.global.scrape_interval=15s
kubectl -n elasticity-lab rollout status deployment/prometheus-server
```

> El `scrape_interval` por defecto del chart es **1 minuto**: `rate([1m])`
> necesitaría varios minutos para reaccionar. Con 15 s el escalado se
> comporta de forma comparable al scaler de CPU.

> El chart scrapea automáticamente los pods anotados con
> `prometheus.io/scrape: "true"` — ya incluido en `k8s/10-deployment.yaml`.

Verifica que Prometheus recolecta las métricas del servicio:

```bash
kubectl -n elasticity-lab port-forward svc/prometheus-server 9090:80 &
# abre http://localhost:9090 y ejecuta la query:
#   http_server_requests_seconds_count{namespace="elasticity-lab"}
```

## 2. Sustituir el ScaledObject

Solo puede haber un ScaledObject activo por deployment:

```bash
kubectl -n elasticity-lab delete scaledobject elasticity-api-scaler
kubectl apply -f k8s/30-scaledobject-prometheus.yaml
```

### La consulta PromQL

```promql
avg(rate(http_server_requests_seconds_count{namespace="elasticity-lab",
     pod=~"elasticity-api-.*", uri!~"/actuator.*"}[1m]))
```

- `rate(...[1m])` → peticiones por segundo completadas por cada pod.
- `uri!~"/actuator.*"` → excluye el tráfico sintético: los scrapes de
  `/actuator/prometheus` y los probes de salud (~0,2 req/s por pod que
  distorsionarían la medida).
- `avg(...)` → promedio entre todos los pods vivos: **req/s por pod**, la
  traducción exacta de "número de peticiones promedio".

### Por qué `threshold: "2"`

Un pod con `limits.cpu: 1` solo puede *completar* unas **3 req/s** de
`/api/work` (cada petición consume ~300 ms de CPU). Con un umbral más alto
(p. ej. 5), el rate medido nunca lo alcanzaría aunque el pod esté
saturado. Con `2` la separación es clara:

| Estado | req/s promedio por pod |
|---|---|
| Reposo (sin carga) | ≈ 0 (solo tráfico real; probes excluidos) |
| Bajo carga sostenida | ≥ 3 → escala hasta repartir la demanda |

## 3. Probar el escalado

Repite la prueba de carga del paso 3:

```powershell
# Windows (PowerShell o cmd)
.\scripts\carga.ps1 -Concurrencia 20 -DuracionSegundos 300
```

```bash
# Linux / macOS / Git Bash
CONCURRENCIA=20 DURACION=300 ./scripts/carga.sh
```

Observa el HPA — ahora la métrica es `http_requests_per_pod_avg`
en lugar de `cpu`:

```bash
kubectl -n elasticity-lab get hpa -w
# TARGETS:  <req/s promedio>/5
```

## 4. Volver al scaler de CPU

```bash
kubectl -n elasticity-lab delete scaledobject elasticity-api-scaler
kubectl apply -f k8s/20-scaledobject-cpu.yaml
```

## Limpieza de Prometheus (opcional)

```bash
helm uninstall prometheus -n elasticity-lab
```

## Siguiente / anterior

- ← [03-scaledobject-y-carga.md](03-scaledobject-y-carga.md)
- [05-solucion-de-problemas.md](05-solucion-de-problemas.md) — resolución de problemas
