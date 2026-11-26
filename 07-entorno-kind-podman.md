# Paso 7 — Entorno alternativo: kind + podman (WSL / Linux sin Docker Desktop)

> 💡 **Atajo**: `scripts/setup.sh` (`setup.ps1` / `setup.cmd` en Windows)
> automatiza todo lo de esta guía. Esta página es el paso a paso manual.

Las guías 00–06 asumen **Docker Desktop con Kubernetes**. Si trabajas en
WSL/Linux sin Docker, usa **kind** (Kubernetes en contenedores) con
**podman**. Probado con kind 0.24, podman 5.7, helm 3.16 y KEDA 2.21.0.

## ⚠️ Seguridad: verifica tu contexto de kubectl

`kubectl` ejecuta contra el **contexto activo**. Si tienes clústeres reales
configurados (AKS, EKS, GKE...) podrías aplicar el laboratorio ahí.

```bash
kubectl config current-context     # debe decir kind-keda-lab (o docker-desktop)
```

Y ejecuta el script de verificación (según tu sistema):

```bash
# Linux / macOS / WSL / Git Bash
./scripts/verificar-prerrequisitos.sh
```

```powershell
# Windows (PowerShell)
.\scripts\verificar-prerrequisitos.ps1
```

```bat
REM Windows (cmd.exe)
scripts\verificar-prerrequisitos.cmd
```

Para mayor seguridad, añade `--context kind-keda-lab` a cada comando
(`kubectl`, `helm --kube-context`), como se hace abajo con `$C`.

## 0. Herramientas

Ejecuta el script de verificación del apartado anterior (`.sh`, `.ps1` o `.cmd`).

Si falta **helm** (sin sudo):

```bash
mkdir -p ~/.local/bin
curl -fsSL https://get.helm.sh/helm-v3.16.4-linux-amd64.tar.gz | tar -xz -C /tmp
cp /tmp/linux-amd64/helm ~/.local/bin/helm      # ~/.local/bin debe estar en el PATH
```

kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation

## 1. podman: nombres de imagen

Los `FROM` del Dockerfile ya usan nombres completos (`docker.io/library/...`),
así que **no hace falta configurar `registries.conf`**. (Versiones anteriores
fallaban con `short-name ... did not resolve to an alias`.)

## 2. Crear el clúster

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
C=kind-keda-lab
kind create cluster --name keda-lab --config k8s/kind-config.yaml
kubectl config current-context        # kind-keda-lab
```

## 3. Seguir las guías 00 y 01 con `--context`

```bash
kubectl --context $C apply -f k8s/00-namespace.yaml

# metrics-server (kind no lo trae) + parche TLS
kubectl --context $C apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl --context $C patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl --context $C -n kube-system rollout status deploy/metrics-server
kubectl --context $C top nodes

# KEDA
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm --kube-context $C install keda kedacore/keda -n keda --create-namespace --version 2.21.0
kubectl --context $C -n keda get pods       # 3 pods Running (1-2 min)
```

## 4. Construir y cargar la imagen (reemplaza al paso de la guía 02)

El clúster kind **no ve** las imágenes de tu máquina: hay que cargarlas. Además
el Deployment usa `elasticity-api:0.0.1`, que Kubernetes resuelve como
`docker.io/library/elasticity-api:0.0.1`; por eso se etiqueta con ese nombre.

```bash
cd elasticity-api
podman build -t localhost/elasticity-api:0.0.1 .      # 2-3 min la primera vez
cd ..
podman tag localhost/elasticity-api:0.0.1 docker.io/library/elasticity-api:0.0.1
podman save docker.io/library/elasticity-api:0.0.1 -o /tmp/elasticity-api.tar
kind load image-archive /tmp/elasticity-api.tar --name keda-lab
```

## 5. Desplegar y continuar

```bash
kubectl --context $C apply -f k8s/10-deployment.yaml -f k8s/11-service.yaml
kubectl --context $C -n elasticity-lab rollout status deploy/elasticity-api
kubectl --context $C apply -f k8s/20-scaledobject-cpu.yaml
```

Continúa con [03-scaledobject-y-carga.md](03-scaledobject-y-carga.md)
(añadiendo `--context $C` a los comandos). `k8s/kind-config.yaml` publica el NodePort **30080** del Service en
`localhost:30080`: úsalo para probar y para generar carga, porque balancea
entre **todas** las réplicas. `kubectl port-forward` se ata a **un solo pod**
(la carga nunca llegaría a las réplicas nuevas).

```bash
curl http://localhost:30080/api/hello
URL="http://localhost:30080/api/work?ms=300" CONCURRENCIA=20 DURACION=120 ./scripts/carga.sh
```

## Problemas frecuentes

| Síntoma | Causa | Acción |
|---|---|---|
| `short-name ... did not resolve` | Dockerfile antiguo con nombres cortos | Actualiza el repo (los `FROM` ya son `docker.io/library/...`) |
| Pod en `ImagePullBackOff` / `ErrImagePull` | Imagen no cargada en kind o con otro nombre | Repite el paso 4 (tag `docker.io/library/...`) |
| `"/" is not a shared mount` (warning de podman) | Rootless en WSL | Inofensivo |
| `kind` pide el provider | Falta la variable | `export KIND_EXPERIMENTAL_PROVIDER=podman` |
| `running kind with rootless provider requires setting systemd property "Delegate=yes"` | podman rootless sin cgroups delegados a tu sesión | Usa una sesión normal de WSL/terminal; o ejecuta `systemd-run --user --scope -p Delegate=yes ./scripts/setup.sh` (ver https://kind.sigs.k8s.io/docs/user/rootless/) |

## Limpieza

```bash
kind delete cluster --name keda-lab
```

## Navegación

- ← [06-ingenieria-de-capacidad.md](06-ingenieria-de-capacidad.md)
- → [08-evidencias.md](08-evidencias.md) — qué capturas entregar
