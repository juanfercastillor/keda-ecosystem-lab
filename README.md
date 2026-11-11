# Laboratorio: Elasticidad en Kubernetes con KEDA

Guía práctica para demostrar el concepto de **elasticidad**: un microservicio
Spring Boot se despliega en Kubernetes y **KEDA** ajusta automáticamente el
número de réplicas en función de la demanda.

- **Escenario principal**: la carga de peticiones HTTP eleva la utilización de
  CPU de los pods → KEDA (scaler `cpu`, alimentado por Metrics API /
  metrics-server) escala el deployment.
- **Anexo opcional**: escalado literal por *peticiones promedio por pod*
  usando el scaler de Prometheus de KEDA.

## Arquitectura del laboratorio

```
                 ┌─────────────── namespace: elasticity-lab ───────────────┐
                 │                                                         │
 carga.ps1/sh ──►│  Service (port-forward :8080 / NodePort :30080)          │
                 │        │                                                │
                 │        ▼                                                │
                 │  Deployment: elasticity-api (1 → 8 pods)                │
                 │        ▲                                                │
                 │        │ observa                                        │
                 │  ScaledObject ──► HPA (creado por KEDA)                 │
                 └─────────┬───────────────────────────────────────────────┘
                           │ consulta métricas de TODOS los namespaces
   ┌─── namespace: keda ───┼──────────────────────────┐
   │  KEDA Operator ──────►│ Metrics API (metrics-server, kube-system)      │
   └───────────────────────┴──────────────────────────┘
```

> KEDA es un operador *cluster-wide*: aunque se instala en su propio namespace
> (`keda`), observa los `ScaledObject` de todos los namespaces. Por eso el
> laboratorio separa **infraestructura** (`keda`, `kube-system`) de **carga de
> trabajo** (`elasticity-lab`).

## Prerrequisitos

| Herramienta | Versión recomendada | Verificación |
|---|---|---|
| Docker Desktop con Kubernetes habilitado | actual | `kubectl get nodes` |
| kubectl | 1.30+ | `kubectl version --client` |
| Helm | 3.x | `helm version` |
| Java (solo para compilación local, opcional) | 25 | `java -version` |

> **Docker Desktop**: habilita Kubernetes en *Settings → Kubernetes → Enable
> Kubernetes* y espera a que el nodo esté `Ready`.

> **Java no es obligatorio en local**: la imagen se compila dentro de Docker
> (multi-stage build). El toolchain de Gradle descarga automáticamente el
> JDK 25 si compilas en local y no lo tienes instalado.

> **Multiplataforma**: los comandos `kubectl`, `helm` y `docker` son
> idénticos en Linux, macOS y Windows. Para filtrar texto usa
> `| grep texto` (Linux/macOS/Git Bash) o `| Select-String texto` /
> `| findstr texto` (Windows PowerShell/cmd). Muchas herramientas tienen
> filtros nativos equivalentes: `helm list --filter`, `docker images <nombre>`,
> `kubectl get <recurso> <nombre>`.

## Guías del laboratorio

| Archivo | Contenido |
|---|---|
| [00-crear-namespace.md](00-crear-namespace.md) | Creación del namespace `elasticity-lab` |
| [01-instalacion-cluster.md](01-instalacion-cluster.md) | Instalar metrics-server y KEDA (namespace `keda`) |
| [02-despliegue-microservicio.md](02-despliegue-microservicio.md) | Build de la imagen y despliegue del servicio |
| [03-scaledobject-y-carga.md](03-scaledobject-y-carga.md) | ScaledObject por CPU + prueba de carga + observabilidad |
| [04-escalado-prometheus.md](04-escalado-prometheus.md) | (Opcional) Escalado por req/s promedio con Prometheus |
| [05-solucion-de-problemas.md](05-solucion-de-problemas.md) | Resolución de problemas |

Este README es la versión monolítica de la misma práctica; las guías
numeradas la desglosan paso a paso.

## Estructura del repositorio

```
keda-ecosystem-lab/
├── README.md
├── 00-crear-namespace.md      # Guías numeradas del laboratorio
├── 01-instalacion-cluster.md
├── 02-despliegue-microservicio.md
├── 03-scaledobject-y-carga.md
├── 04-escalado-prometheus.md  # (opcional)
├── 05-solucion-de-problemas.md
├── elasticity-api/            # Microservicio Spring Boot 4.1 + Java 25 + Gradle 9.9
│   ├── Dockerfile             # Build multi-etapa (gradle → temurin-jre)
│   ├── build.gradle.kts
│   └── src/...
├── k8s/
│   ├── 00-namespace.yaml      # Namespace elasticity-lab
│   ├── 10-deployment.yaml     # Deployment del microservicio
│   ├── 11-service.yaml        # Service NodePort :30080
│   ├── 20-scaledobject-cpu.yaml        # ScaledObject (escenario principal)
│   └── 30-scaledobject-prometheus.yaml # ScaledObject por req/s (paso 4)
└── scripts/
    ├── carga.ps1              # Generador de carga (PowerShell)
    ├── carga.cmd              # Generador de carga (cmd.exe)
    └── carga.sh               # Generador de carga (bash)
```

---

## Paso 1 — Crear el namespace

La carga de trabajo del laboratorio (microservicio + ScaledObject) vive en
`elasticity-lab` (KEDA va aparte, en `keda`):

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl get namespaces elasticity-lab
```

## Paso 2 — Instalar KEDA

KEDA se instala en su **namespace dedicado `keda`** (infraestructura del
clúster, separada del laboratorio):

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace --version 2.21.0
```

> Si el release `keda` ya existe en `keda`, actualiza en lugar de instalar:
> `helm upgrade keda kedacore/keda -n keda --version 2.21.0`.
>
> ⚠️ **Solo una instalación de KEDA por clúster**: el operador observa los
> `ScaledObject` de todos los namespaces. Si ya tienes KEDA en otro
> namespace (`helm list -A --filter keda`), reutilízala (los ScaledObject de
> `elasticity-lab` funcionarán igual) o muévela al namespace estándar con
> `helm uninstall keda -n <namespace-anterior>` + el `helm install` de arriba.

Verifica que los componentes de KEDA estén en ejecución:

```bash
kubectl -n keda get pods
kubectl -n keda rollout status deployment/keda-operator
```

Deberías ver `keda-operator`, `keda-metrics-apiserver` y
`keda-admission-webhooks` en estado `Running`.

## Paso 3 — Verificar metrics-server

El scaler de CPU de KEDA obtiene las métricas de la **Metrics API**
(`metrics.k8s.io`), servida por *metrics-server*:

```bash
kubectl top nodes
```

- **Si responde con métricas** → continúa al paso 4.
- **Si falla** (`Metrics API not available`), instálalo:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server
```

> El flag `--kubelet-insecure-tls` es aceptable para un clúster local de
> laboratorio; en producción se configuran certificados adecuados.

## Paso 4 — Compilar el microservicio

### Opción A (recomendada): imagen Docker

Docker Desktop comparte su daemon con el clúster, así que la imagen queda
disponible directamente para Kubernetes:

```bash
cd elasticity-api
docker build -t elasticity-api:0.0.1 .
cd ..
```

### Opción B: compilación local (verificación)

```bash
cd elasticity-api
./gradlew build        # en Windows: gradlew.bat build
cd ..
```

Genera `elasticity-api/build/libs/elasticity-api-0.0.1.jar`.

## Paso 5 — Desplegar el microservicio

```bash
kubectl apply -f k8s/10-deployment.yaml -f k8s/11-service.yaml
kubectl -n elasticity-lab rollout status deployment/elasticity-api
```

Expón el servicio en tu máquina (déjalo corriendo en su propia terminal):

```bash
kubectl -n elasticity-lab port-forward svc/elasticity-api 8080:8080
```

> El Service también es `NodePort :30080`, pero en Docker Desktop ese puerto
> no siempre se publica en `localhost` de Windows (depende del modo de red).
> El `port-forward` funciona en todos los casos.

Prueba los endpoints (en otra terminal):

```bash
curl http://localhost:8080/api/hello
curl "http://localhost:8080/api/work?ms=300"
curl http://localhost:8080/actuator/prometheus
```

| Endpoint | Descripción |
|---|---|
| `GET /api/hello` | Devuelve el hostname del pod (observa el balanceo al escalar) |
| `GET /api/work?ms=N` | Consume CPU durante `N` ms (máx. 10 s) y devuelve métricas de la operación |
| `GET /actuator/prometheus` | Métricas Micrometer en formato Prometheus |

> **Nota**: `/api/work` realiza trabajo *CPU-bound* (hashes SHA-256), no un
> `sleep`. Esto es lo que convierte las peticiones en utilización de CPU
> medible por metrics-server.

## Paso 6 — Crear el ScaledObject

```bash
kubectl apply -f k8s/20-scaledobject-cpu.yaml
```

Al aplicarlo, KEDA crea automáticamente un **HPA** que gobierna las réplicas
del deployment:

```bash
kubectl -n elasticity-lab get scaledobject
kubectl -n elasticity-lab get hpa          # keda-hpa-elasticity-api-scaler
kubectl -n elasticity-lab describe scaledobject elasticity-api-scaler
```

Configuración clave del ScaledObject (`k8s/20-scaledobject-cpu.yaml`):

| Campo | Valor | Efecto |
|---|---|---|
| `triggers[0].type` | `cpu` | Fuente: Metrics API |
| `metricType` / `value` | `Utilization` / `50` | Escala cuando el uso medio supera el 50 % del `requests.cpu` (250m) |
| `minReplicaCount` / `maxReplicaCount` | `1` / `8` | Rango de elasticidad |
| `pollingInterval` | `15` | Cada 15 s KEDA consulta la métrica |
| `cooldownPeriod` | `120` | Espera 120 s sin superar el umbral antes de reducir a 1 réplica |
| `advanced.hpa...behavior` | — | Escala rápido hacia arriba, lento hacia abajo |

## Paso 7 — Generar carga y observar la elasticidad

Abre **dos terminales**.

**Terminal 1** — observa pods y HPA:

```bash
kubectl -n elasticity-lab get hpa -w
# y/o:
kubectl -n elasticity-lab get pods -l app=elasticity-api -w
kubectl -n elasticity-lab top pods
```

**Terminal 2** — lanza la carga:

```powershell
# PowerShell (Windows)
.\scripts\carga.ps1 -Concurrencia 20 -DuracionSegundos 300
```

```bash
# bash / Git Bash
CONCURRENCIA=20 DURACION=300 ./scripts/carga.sh
```

### Qué deberías observar

1. La utilización de CPU supera el 50 % del request → el HPA incrementa
   `TARGETS` y nacen pods nuevos (`elasticity-api-xxx`).
2. Con carga sostenida el deployment llega hasta `maxReplicaCount: 8`.
3. Mientras escala, las respuestas de `/api/hello` rotan entre varios
   hostnames: el Service balancea entre todas las réplicas.
4. **Detén la carga** (Ctrl+C o espera a que termine) → tras el
   `cooldownPeriod` (~2 min) el deployment vuelve a **1 réplica**.

Ese ciclo *crecer con la demanda y decrecer al cesarla* es la elasticidad.

> **Observación real**: con los pods saturados de CPU (límite de 1 core), el
> liveness probe puede expirar y el kubelet reinicia esos pods
> (`RESTARTS` > 0). Es el comportamiento esperado bajo estrés extremo; en
> producción se ajustarían `timeoutSeconds`/`failureThreshold` o los límites.

## Paso 8 — Experimentos sugeridos

- Baja el umbral a `value: "25"` y observa que escala antes.
- Aumenta `ms` en la URL del script (`?ms=800`) con menos concurrencia.
- Cambia `metricType` a `AverageValue` (milicores absolutos, p. ej. `300m`).
- Añade un trigger de memoria (`type: memory`).
- Reduce `cooldownPeriod` a `30` y compara el tiempo de scale-down.
- Inspecciona los logs del operador: `kubectl -n keda logs deploy/keda-operator`.

---

## Escalado por peticiones promedio con Prometheus (opcional)

El escenario principal usa CPU como señal (peticiones → CPU → réplicas).
Para escalar sobre la métrica literal *peticiones/segundo promedio por pod*
sigue la guía dedicada: **[04-escalado-prometheus.md](04-escalado-prometheus.md)**
(instalación de Prometheus, `ScaledObject` con scaler `prometheus` y la
query PromQL explicada).

## Resolución de problemas

Errores frecuentes del laboratorio y su solución, agrupados por área:
**[05-solucion-de-problemas.md](05-solucion-de-problemas.md)**.

## Limpieza

```bash
kubectl delete namespace elasticity-lab           # borra app, service y ScaledObject
helm uninstall prometheus -n elasticity-lab       # solo si instalaste el paso 4
helm uninstall keda -n keda                       # opcional: deja KEDA instalado para otras prácticas
kubectl delete namespace keda                     # solo tras desinstalar KEDA
docker rmi elasticity-api:0.0.1                   # opcional
```

## Referencias

- Documentación KEDA: https://keda.sh/docs/
- KEDA scalers (CPU, memory, Prometheus): https://keda.sh/docs/scalers/
- Spring Boot 4: https://docs.spring.io/spring-boot/
- metrics-server: https://github.com/kubernetes-sigs/metrics-server
