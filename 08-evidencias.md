# Paso 8 — Evidencias del laboratorio (capturas de pantalla)

Para demostrar que completaste el laboratorio, cada participante debe
**generar un único documento PDF con las capturas de pantalla** descritas
abajo y **subirlo al enlace de SharePoint/OneDrive** que se compartirá
durante la sesión.

## Resumen del proceso

1. Ejecuta el laboratorio y toma las capturas a medida que avanzas
   (no esperes al final: el clúster se borra al terminar).
2. Pega las capturas en un documento (Word, Google Docs, PowerPoint, etc.),
   en orden, con el número y título de cada una.
3. Exporta el documento a **PDF**.
4. Nómbralo `evidencias-keda-<tu-nombre>.pdf`.
5. Súbelo al enlace de SharePoint/OneDrive compartido en la sesión.

## Reglas generales

- En Windows puedes usar `Win + Shift + S` (Recortes); en macOS `Cmd + Shift + 4`;
  en Linux la herramienta de capturas de tu escritorio. En Windows,
  sustituye `grep` por `Select-String` o `findstr`.
- Cada captura debe mostrar **el comando y su salida completa**.
- Debe verse la **hora** (reloj del sistema, o usa `date +%T` antes del comando)
  para poder calcular los tiempos de escalado.
- No recortes la terminal: se debe ver el contexto/namespace.
- No incluyas tokens, contraseñas ni credenciales.

## Capturas obligatorias

| # | Qué demuestra | Comando | Debe verse |
|---|---|---|---|
| 1 | Contexto seguro | `kubectl config current-context` | `kind-keda-lab` o `docker-desktop` (nunca un clúster real) |
| 2 | metrics-server | `kubectl top nodes` | CPU/memoria del nodo |
| 3 | KEDA instalado | `kubectl -n keda get pods` | 3 pods `Running` |
| 4 | CRDs de KEDA | `kubectl get crd \| grep keda` | `scaledobjects.keda.sh`, etc. |
| 5 | App desplegada | `kubectl -n elasticity-lab get pods` y `curl localhost:8080/api/hello` | `READY 1/1` y JSON con el nombre del pod |
| 6 | ScaledObject + HPA | `kubectl -n elasticity-lab get scaledobject,hpa` | `READY True`, HPA `keda-hpa-elasticity-api-scaler` |
| 7 | Línea base | `kubectl -n elasticity-lab get hpa` | `cpu: ~1%/50%`, 1 réplica |
| 8 | **Scale-up (clave)** | `kubectl -n elasticity-lab get hpa -w` durante la carga | `TARGETS` sobre 50 % y `REPLICAS` de 1 a 8 |
| 9 | Pods nuevos | `kubectl -n elasticity-lab get pods -w` durante la carga | Pods `Pending → ContainerCreating → Running` |
| 10 | Balanceo | 10 × `curl localhost:8080/api/hello` | Nombres de pod distintos |
| 11 | **Scale-down** | `get hpa -w` tras detener la carga | `cpu: 1%` y réplicas bajando hasta 1, con hora |
| 12 | Decisiones de KEDA | `kubectl -n elasticity-lab describe hpa keda-hpa-elasticity-api-scaler` | Sección *Events* con `SuccessfulRescale` |

## Captura del experimento propio (obligatoria)

Elige **un** experimento del paso 8 del README (por ejemplo `value: "25"`) y
entrega: el cambio aplicado (diff o YAML), el HPA antes y después, y 2-3
líneas explicando qué cambió y por qué.

## Capturas opcionales (anexo Prometheus)

- Query PromQL con su resultado en Prometheus.
- `get hpa` con el trigger `prometheus` escalando.

## Tiempos de referencia

Medidos con 20 peticiones concurrentes a `/api/work?ms=300`, un nodo kind:

| Momento | Esperado |
|---|---|
| HPA con `cpu: <unknown>` tras crear el ScaledObject | ~20 s (normal) |
| Inicio de carga → primer escalado | ~30–60 s |
| Llegar a 8 réplicas | ~1–2 min desde el inicio de la carga |
| Detener carga → 1 réplica | **~5–6 min** |

La bajada es lenta por diseño: la gobierna la ventana de estabilización
(`stabilizationWindowSeconds: 120`) y la política de reducir 50 % por minuto
del bloque `behavior.scaleDown`. Con scaler `cpu` y `minReplicaCount: 1`,
`cooldownPeriod` **no aplica**; KEDA lo avisa con un warning al crear el
ScaledObject. Es inofensivo.

## Criterios de aprobación

- [ ] Un único PDF con las 12 capturas obligatorias, con hora visible.
- [ ] El scale-up llega a más de 1 réplica y el scale-down regresa a 1.
- [ ] Contexto de kubectl de laboratorio en la captura 1.
- [ ] Experimento propio documentado.
- [ ] PDF subido al enlace de SharePoint/OneDrive de la sesión.

## Cómo armar el PDF

Estructura sugerida del documento:

1. **Portada:** tu nombre, fecha, sistema operativo y clúster usado
   (kind / Docker Desktop / otro).
2. **Capturas 1 a 12**, cada una con su número y título (ver tabla), en
   orden.
3. **Experimento propio:** cambio aplicado, HPA antes y después, y tu
   explicación.
4. **(Opcional)** capturas del anexo de Prometheus.

Exportar a PDF:

| Herramienta | Cómo |
|---|---|
| Word | *Archivo → Exportar → Crear documento PDF/XPS* |
| Google Docs | *Archivo → Descargar → Documento PDF (.pdf)* |
| PowerPoint | *Archivo → Exportar → Crear documento PDF/XPS* |
| LibreOffice | *Archivo → Exportar como → Exportar como PDF* |

Antes de subirlo, revisa que las capturas se lean bien y que no muestren
credenciales.

## Cómo entregarlo

Sube el PDF (`evidencias-keda-<tu-nombre>.pdf`) al enlace de
**SharePoint/OneDrive** que se compartirá durante la sesión. Si el enlace
pide iniciar sesión, usa tu cuenta corporativa. No envíes el PDF por otros
medios ni lo subas a este repositorio.

## Navegación

- ← [07-entorno-kind-podman.md](07-entorno-kind-podman.md)
- [README](README.md)
