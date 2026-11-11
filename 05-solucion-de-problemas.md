# Paso 5 — Resolución de problemas

Problemas encontrados durante la construcción y ejecución del laboratorio
en Docker Desktop, con su causa y solución.

## Despliegue e imagen

| Síntoma | Causa probable | Acción |
|---|---|---|
| Pods `ImagePullBackOff` | Docker Desktop sin *containerd image store*: `docker build` guarda en el store de Docker y el kubelet (containerd) no la ve | Importa la imagen a containerd: `docker save elasticity-api:0.0.1 \| kubectl debug node/desktop-control-plane -i --image=busybox:1.36 --profile=sysadmin -- chroot /host ctr -n k8s.io images import -`, habilita *Settings → General → Use containerd for pulling and storing images*, o usa un registro remoto (ver abajo) |
| `localhost:30080` no responde | Docker Desktop no publica el NodePort en el host con ciertas configuraciones de red | Usa `kubectl -n elasticity-lab port-forward svc/elasticity-api 8080:8080` y `curl http://localhost:8080/api/hello` |
| Port-forward falla con "unable to listen" | El puerto 8080 está ocupado (otro port-forward vivo o socket `TIME_WAIT`) | Espera unos segundos y reintenta, o usa otro puerto: `port-forward svc/elasticity-api 8081:8080` y ajusta la URL |

### Alternativa: publicar la imagen en Docker Hub (registro público)

Si ninguna de las opciones locales funciona, publica la imagen en
**Docker Hub** y deja que el clúster la descargue del registro. Requiere
una **cuenta de Docker Hub** y sesión iniciada (`docker login`).

```bash
# 1. Iniciar sesión (pide usuario y contraseña / token de acceso)
docker login

# 2. Etiquetar la imagen con tu usuario de Docker Hub
docker tag elasticity-api:0.0.1 <tu-usuario>/elasticity-api:0.0.1

# 3. Subirla al registro
docker push <tu-usuario>/elasticity-api:0.0.1
```

Luego apunta el Deployment a la imagen remota — editando
`k8s/10-deployment.yaml`:

```yaml
containers:
  - name: elasticity-api
    image: <tu-usuario>/elasticity-api:0.0.1   # antes: elasticity-api:0.0.1
    imagePullPolicy: IfNotPresent
```

y reaplicando:

```bash
kubectl apply -f k8s/10-deployment.yaml
kubectl -n elasticity-lab rollout status deployment/elasticity-api
```

Notas:

- **Repositorio público** en Docker Hub → el cluster descarga sin
  credenciales, no hace falta nada más.
- **Repositorio privado** → además hay que crear un `imagePullSecret` y
  referenciarlo en el Deployment:

  ```bash
  kubectl -n elasticity-lab create secret docker-registry dockerhub-creds \
    --docker-username=<tu-usuario> --docker-password=<token> \
    --docker-server=https://index.docker.io/v1/
  ```

  ```yaml
  spec:
    imagePullSecrets:
      - name: dockerhub-creds
    containers: ...
  ```

> Usa un **access token** de Docker Hub (*Account Settings → Security*)
> en lugar de tu contraseña, tanto en `docker login` como en el secret.

## Métricas y escalado

| Síntoma | Causa probable | Acción |
|---|---|---|
| `kubectl top` devuelve `Metrics API not available` | metrics-server no instalado | Instálalo según `01-instalacion-cluster.md` |
| HPA muestra `unknown` en targets | metrics-server sin `--kubelet-insecure-tls`, o métricas aún no pobladas | Aplica el parche del paso 1; espera ~30 s |
| No escala pese a la carga | Umbral alto, peticiones muy cortas o carga insuficiente | Sube `ms` en la URL, sube la concurrencia, o baja `value` del trigger |
| ScaledObject `Ready: False` | Error en triggers (nombre, tipo, metadatos) | `kubectl -n elasticity-lab describe scaledobject elasticity-api-scaler` y `kubectl -n keda logs deploy/keda-operator` |
| Pods con `RESTARTS > 0` bajo carga | Liveness probe expira con el pod saturado de CPU | Esperado bajo estrés extremo; en producción ajusta `timeoutSeconds`/`failureThreshold` o los límites |

## KEDA (instalación y migración)

| Síntoma | Causa probable | Acción |
|---|---|---|
| `helm install` → "cannot reuse a name" | Ya existe un release `keda` en otro namespace | Reutilízalo (es cluster-wide) o `helm uninstall keda -n <ns-anterior>` |
| `helm install` → CRD "cannot be imported into the current release" | Los CRDs quedaron anotados a un release Helm previo | Re-anota: `kubectl annotate crd scaledobjects.keda.sh meta.helm.sh/release-namespace=keda --overwrite` y reinstala |
| ScaledObjects desaparecen tras tocar la instalación | Borrar un CRD elimina todos sus objetos del clúster | Prevención: `kubectl get scaledobject -A -o yaml > backup.yaml` antes de desinstalar/migrar KEDA |

## Scripts de carga

| Síntoma | Causa probable | Acción |
|---|---|---|
| Respuestas `000` en `carga.sh`/`carga.ps1` | Port-forward caído o URL equivocada | `curl http://localhost:8080/api/hello` para verificar antes de lanzar |
| `TypeNotFound: System.Net.Http.HttpClient` en PowerShell 5.1 | El ensamblado no se carga solo en PS 5.1 | Ya corregido con `Add-Type -AssemblyName System.Net.Http` en el script |
| PowerShell no ejecuta el `.ps1` | Política de ejecución restrictiva | Usa `carga.cmd` (lleva `-ExecutionPolicy Bypass`) o `powershell -ExecutionPolicy Bypass -File .\scripts\carga.ps1` |

## Anterior / índice

- ← [04-escalado-prometheus.md](04-escalado-prometheus.md)
- [README.md](README.md) — guía principal
