# Paso 1 — Instalaciones necesarias en el clúster

> **Nota multiplataforma**: los comandos `kubectl`, `helm` y `docker` son
> idénticos en Linux, macOS y Windows. Solo cambia el filtrado de texto:
>
> | Linux / macOS | Windows (PowerShell o cmd) |
> |---|---|
> | `\| grep texto` | `\| Select-String texto` o `\| findstr texto` |
>
> En Windows también puedes usar **Git Bash** o **WSL**, donde `grep` existe.

Para que la práctica funcione, el clúster necesita dos componentes:

| Componente | Para qué | Instalación |
|---|---|---|
| **metrics-server** | Expone la Metrics API (`metrics.k8s.io`) con el uso de CPU/memoria de los pods. Es la fuente de métricas del scaler de CPU de KEDA | Manifiestos YAML |
| **KEDA 2.21.0** | Operador que observa los `ScaledObject` y gobierna el escalado (crea un HPA por cada uno) | Helm chart |

> **Topología**: KEDA es un operador *cluster-wide*: observa los
> `ScaledObject` de **todos** los namespaces. Por eso se instala en su propio
> namespace dedicado (`keda`), separado de la carga de trabajo — igual que
> `kube-system` o `ingress-nginx`. Una sola instalación sirve para todos los
> laboratorios del clúster.

## 1. metrics-server

### Comprobar si ya está instalado

```bash
kubectl top nodes
```

- **Si responde con una tabla de CPU/memoria** → ya está instalado, pasa a KEDA.
- **Si responde `error: Metrics API not available`** → instálalo:

### Instalar metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Parchear el kubelet TLS (necesario en Docker Desktop)

metrics-server no puede validar los certificados autofirmados del kubelet de
Docker Desktop; añade el flag `--kubelet-insecure-tls`:

```bash
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

> Aceptable en un clúster local de laboratorio; en producción se configuran
> certificados firmados.

### Verificar

```bash
kubectl -n kube-system rollout status deployment/metrics-server
kubectl top nodes
```

Debe devolver el uso de CPU/memoria del nodo.

## 2. KEDA

Se instala en su **namespace dedicado `keda`** (no en `elasticity-lab`) con Helm.

### Añadir el repositorio

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

### Instalar el chart

```bash
helm install keda kedacore/keda --namespace keda --create-namespace --version 2.21.0
```

> Si el release `keda` ya existe en el namespace `keda`, usa:
> `helm upgrade keda kedacore/keda -n keda --version 2.21.0`

> ⚠️ **Solo puede haber una instalación de KEDA por clúster.** Si ya tienes
> KEDA en otro namespace (`helm list -A --filter keda` — el filtro es nativo
> de helm, igual en todos los SO), elige una:
>
> - Reutilizarla: los `ScaledObject` de `elasticity-lab` funcionarán igual
>   aunque el operador viva en otro namespace → **salta este paso**.
> - Moverla al namespace estándar: `helm uninstall keda -n <namespace-anterior>`
>   y vuelve a ejecutar el `helm install` de arriba.

### Verificar la instalación

```bash
kubectl -n keda get pods
kubectl -n keda rollout status deployment/keda-operator
```

Debes ver tres componentes en `Running`:

```
keda-operator-...
keda-operator-metrics-apiserver-...
keda-admission-webhooks-...
```

Y comprobar que los CRDs de KEDA existen:

```bash
# Linux / macOS
kubectl get crd | grep keda

# Windows (PowerShell o cmd)
kubectl get crd | Select-String keda    # o bien: kubectl get crd | findstr keda
```

Debe listar `scaledobjects.keda.sh`, `scaledjobs.keda.sh`,
`triggerauthentications.keda.sh`, etc.

## Resumen de verificación

```bash
kubectl top nodes            # metrics-server OK
kubectl -n keda get pods     # 3 pods de KEDA Running
kubectl get scaledobject -A  # API de KEDA disponible (aunque no haya objetos aún)
```

## Desinstalación (limpieza)

> ⚠️ **Cuidado**: desinstalar KEDA puede eliminar sus CRDs, y borrar un CRD
> elimina **todos sus objetos del clúster** (p. ej. todos los `ScaledObject`
> de todos los namespaces, junto con los HPAs que generaban). Antes de
> desinstalar, exporta lo que quieras conservar:
> `kubectl get scaledobject -A -o yaml > scaledobjects-backup.yaml`

```bash
helm uninstall keda -n keda
kubectl delete namespace keda
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
