# Paso 2 — Despliegue del microservicio `elasticity-api`

Despliega el microservicio Spring Boot en el namespace `elasticity-lab`.
Aún **sin escalado**: con 1 réplica fija, para observar después el efecto
del `ScaledObject` (siguiente paso).

> **Nota multiplataforma**: los comandos `docker`, `kubectl` y `helm` son
> idénticos en Linux, macOS y Windows. Solo cambia el filtrado de texto:
>
> | Linux / macOS | Windows (PowerShell o cmd) |
> |---|---|
> | `\| grep texto` | `\| Select-String texto` o `\| findstr texto` |
>
> `curl` funciona igual en los tres (Windows 10+ lo incluye como `curl.exe`;
> en PowerShell evita el alias `curl`→`Invoke-WebRequest` usando `curl.exe`).

## 1. Compilar la imagen Docker

Docker Desktop comparte su daemon con el clúster, así que la imagen
construida localmente queda disponible para Kubernetes:

```bash
cd elasticity-api
docker build -t elasticity-api:0.0.1 .
cd ..
```

Verifica que la imagen existe (el filtro por nombre es nativo de `docker`,
funciona igual en los tres sistemas):

```bash
docker images elasticity-api
```

> **Si los pods quedan en `ImagePullBackOff`** (Docker Desktop sin
> *containerd image store*): el kubelet no ve la imagen del store de Docker.
> Impórtala a containerd:
>
> ```bash
> docker save elasticity-api:0.0.1 | kubectl debug node/desktop-control-plane \
>   -i --image=busybox:1.36 --profile=sysadmin -- chroot /host ctr -n k8s.io images import -
> ```
>
> O habilita *Settings → General → Use containerd for pulling and storing
> images* y reconstruye.

## 2. Aplicar los manifiestos

```bash
kubectl apply -f k8s/10-deployment.yaml -f k8s/11-service.yaml
```

Recursos creados en `elasticity-lab`:

| Recurso | Detalle |
|---|---|
| `deployment/elasticity-api` | 1 réplica, `requests.cpu: 250m`, `limits.cpu: 1`, probes de salud |
| `service/elasticity-api` | `NodePort :30080` → `:8080` |

## 3. Verificar el despliegue

```bash
kubectl -n elasticity-lab rollout status deployment/elasticity-api
kubectl -n elasticity-lab get pods -l app=elasticity-api
```

El pod debe llegar a `Running` y `READY 1/1`.

## 4. Exponer y probar los endpoints

Abre una terminal dedicada para el port-forward (el NodePort :30080 no
siempre se publica en `localhost` de Windows):

```bash
kubectl -n elasticity-lab port-forward svc/elasticity-api 8080:8080
```

En **otra** terminal, prueba los endpoints:

```bash
curl http://localhost:8080/api/hello
curl "http://localhost:8080/api/work?ms=300"
curl http://localhost:8080/actuator/prometheus
```

| Endpoint | Respuesta esperada |
|---|---|
| `GET /api/hello` | `{"message":"Hola desde elasticity-api","pod":"elasticity-api-..."}` |
| `GET /api/work?ms=N` | JSON con `pod`, `elapsedMs` y `operations` — consume CPU durante `N` ms (máx. 10 s) |
| `GET /actuator/prometheus` | Métricas Micrometer: `http_server_requests_*`, `jvm_*`, `system_cpu_*` |

> `/api/work` realiza trabajo *CPU-bound* (hashes SHA-256), no un `sleep`:
> es lo que convierte las peticiones en utilización de CPU medible por
> metrics-server.

## 5. Comprobar el consumo base (opcional)

```bash
kubectl -n elasticity-lab top pods
```

Con el pod en reposo verás unos ~10-20m de CPU — la línea base desde la que
partirá el escalado.

## Siguiente paso

Continúa con `03-scaledobject-y-carga.md`: creación del `ScaledObject`
y la prueba de elasticidad.

## Deshacer el despliegue (limpieza)

```bash
kubectl delete -f k8s/10-deployment.yaml -f k8s/11-service.yaml
```

## Navegación

- ← [01-instalacion-cluster.md](01-instalacion-cluster.md)
- → [03-scaledobject-y-carga.md](03-scaledobject-y-carga.md) — ScaledObject y prueba de carga
- [05-solucion-de-problemas.md](05-solucion-de-problemas.md) — si algo falla
