# Paso 0 — Crear el namespace `elasticity-lab`

La carga de trabajo del laboratorio (microservicio y ScaledObject) vivirá en
el namespace **`elasticity-lab`**, aislada de otros recursos del clúster.

> KEDA se instala aparte, en su propio namespace dedicado `keda`
> (ver `01-instalacion-cluster.md`): es un operador *cluster-wide* que observa
> los `ScaledObject` de **todos** los namespaces, así que se gestiona como
> infraestructura, no como parte del laboratorio.

## Prerrequisito

El clúster de Kubernetes de Docker Desktop debe estar activo:

```bash
kubectl get nodes
```

Debe mostrar los nodos esxistentes en el namespace actual.

## Crear el namespace

### Opción A — comando imperativo

```bash
kubectl create namespace elasticity-lab
```

### Opción B — manifiesto declarativo (recomendada)

Crea un archivo `namespace.yaml` con este contenido:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: elasticity-lab
  labels:
    app.kubernetes.io/name: elasticity-lab
```

Y aplícalo:

```bash
kubectl apply -f k8s/00-namespace.yaml
```

> La forma declarativa es idempotente: se puede volver a aplicar sin errores.

## Verificar la creación

```bash
kubectl get namespaces elasticity-lab
```

Salida esperada:

```
NAME              STATUS   AGE
elasticity-lab    Active   5s
```

## (Opcional) Establecer `elasticity-lab` como namespace por defecto

Para no tener que escribir `-n elasticity-lab` en cada comando:

```bash
kubectl config set-context --current --namespace=elasticity-lab
```

Verifica el contexto:

```bash
kubectl config get-contexts
```

Para volver al namespace por defecto al terminar el laboratorio:

```bash
kubectl config set-context --current --namespace=default
```

## Eliminar el namespace (limpieza)

> ⚠️ Esto borra **todos** los recursos dentro de `elasticity-lab`.

```bash
kubectl delete namespace elasticity-lab
```

## Siguiente paso

- → [01-instalacion-cluster.md](01-instalacion-cluster.md) — instalar metrics-server y KEDA
- [05-solucion-de-problemas.md](05-solucion-de-problemas.md) — si algo falla
