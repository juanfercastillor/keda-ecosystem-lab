# Paso 3 — ScaledObject y prueba de carga (elasticidad)

Crea el `ScaledObject` que gobierna el escalado del microservicio y genera
carga HTTP para observar el ciclo completo de elasticidad:
**crecer con la demanda y decrecer al cesarla**.

> **Nota multiplataforma**: `kubectl` funciona igual en Linux, macOS y
> Windows. Para la carga hay dos scripts equivalentes:
>
> | Sistema | Script | Base |
> |---|---|---|
> | Windows | `scripts\carga.ps1` | `HttpClient` + tareas concurrentes (PowerShell 5.1+) |
> | Linux / macOS / Git Bash | `scripts/carga.sh` | `xargs -P` + `curl` |

## 1. Crear el ScaledObject

```bash
kubectl apply -f k8s/20-scaledobject-cpu.yaml
```

Al aplicarlo, KEDA (en el namespace `keda`) crea automáticamente un **HPA**
que gobierna las réplicas del Deployment:

```bash
kubectl -n elasticity-lab get scaledobject
kubectl -n elasticity-lab get hpa          # keda-hpa-elasticity-api-scaler
kubectl -n elasticity-lab describe scaledobject elasticity-api-scaler
```

Debe mostrar `READY: True` y `ACTIVE: True`, y el HPA con el target
`cpu: <actual>/50%`.

### Configuración clave (`k8s/20-scaledobject-cpu.yaml`)

| Campo | Valor | Efecto |
|---|---|---|
| `triggers[0].type` | `cpu` | Fuente: Metrics API (metrics-server) |
| `metricType` / `value` | `Utilization` / `50` | Escala cuando el uso medio supera el 50 % del `requests.cpu` (250m) |
| `minReplicaCount` / `maxReplicaCount` | `1` / `8` | Rango de elasticidad |
| `pollingInterval` | `15` | Cada 15 s se consulta la métrica |
| `cooldownPeriod` | `120` | Pausa mínima antes de reducir a 1 réplica |
| `behavior.scaleUp` / `scaleDown` | — | Escala rápido hacia arriba, lento hacia abajo |

## 2. Preparar la observación (terminal A)

Deja corriendo la observación del escalado. `-w` (watch) es nativo de
kubectl en los tres sistemas:

```bash
kubectl -n elasticity-lab get hpa -w
```

Y/o en otra pestaña:

```bash
kubectl -n elasticity-lab get pods -l app=elasticity-api -w
kubectl -n elasticity-lab top pods
```

## 3. Exponer el servicio (terminal B)

Si no lo tienes ya corriendo desde el paso anterior:

```bash
kubectl -n elasticity-lab port-forward svc/elasticity-api 8080:8080
```

## 4. Generar carga (terminal C)

### Windows (PowerShell)

```powershell
.\scripts\carga.ps1 -Concurrencia 20 -DuracionSegundos 300
```

> Si PowerShell bloquea la ejecución de scripts (*execution policy*):
> `powershell -ExecutionPolicy Bypass -File .\scripts\carga.ps1`

### Linux / macOS / Git Bash

```bash
chmod +x scripts/carga.sh        # solo la primera vez
CONCURRENCIA=20 DURACION=300 ./scripts/carga.sh
```

### Sin scripts (una sola línea, si prefieres)

```bash
# Linux / macOS / Git Bash — 20 peticiones concurrentes en bucle
while true; do seq 20 | xargs -P 20 -I{} curl -s -o /dev/null "http://localhost:8080/api/work?ms=300"; done
```

```powershell
# PowerShell — una ráfaga de 20 peticiones concurrentes por iteración
$c = [System.Net.Http.HttpClient]::new()
while ($true) { [System.Threading.Tasks.Task]::WaitAll(1..20 | % { $c.GetAsync("http://localhost:8080/api/work?ms=300") }) }
```

## 5. Qué observar

1. **Scale-up**: en ~30-60 s la utilización supera el 50 % y el HPA empieza
   a crear pods hasta `maxReplicaCount: 8` si la carga se sostiene.
2. **Balanceo**: el Service reparte las peticiones entre las nuevas
   réplicas. Compruébalo consultando varias veces `/api/hello` — el `pod`
   de la respuesta rota:

   ```bash
   # Linux / macOS / Git Bash
   for i in {1..10}; do curl -s http://localhost:8080/api/hello; echo; sleep 1; done
   ```

   ```powershell
   # Windows (PowerShell)
   1..10 | ForEach-Object { curl.exe -s http://localhost:8080/api/hello; Start-Sleep 1 }
   ```

3. **Scale-down**: detén la carga (Ctrl+C o deja que termine). Tras el
   `cooldownPeriod` (~2 min) más la ventana de estabilización, el
   deployment vuelve a **1 réplica**.

> **Observación real**: con los pods saturados de CPU (límite 1 core), el
> liveness probe puede expirar y algún pod reiniciarse (`RESTARTS > 0`).
> Es el comportamiento esperado bajo estrés extremo.

## 6. Experimentos sugeridos

- Baja el umbral a `value: "25"` y observa que escala antes.
- Aumenta `ms` en la URL (`?ms=800`) y baja la concurrencia.
- Cambia `metricType` a `AverageValue` (milicores absolutos, p. ej. `300m`).
- Reduce `cooldownPeriod` a `30` y compara el tiempo de scale-down.
- Logs del operador: `kubectl -n keda logs deploy/keda-operator`.

## Deshacer (limpieza)

```bash
kubectl -n elasticity-lab delete scaledobject elasticity-api-scaler
# KEDA elimina también el HPA; el deployment queda con sus réplicas actuales
kubectl -n elasticity-lab scale deployment/elasticity-api --replicas=1
```
