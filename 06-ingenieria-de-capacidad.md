# Ingeniería de capacidad: cómo se determinan los valores de escalado

Documento teórico de apoyo del laboratorio. Responde a la pregunta:
**¿qué proceso sigue la ingeniería para decidir umbrales, réplicas,
intervalos y políticas de un sistema elástico?**

Los valores de un `ScaledObject` (o un HPA) no se eligen por intuición:
salen de un proceso iterativo de medición, siempre anclado a objetivos
de servicio medibles.

## 1. Definir los SLO primero

Antes de configurar nada hay que definir qué significa *"funciona bien"*:

- Latencia: p95 / p99 objetivo (p. ej. p99 < 500 ms)
- Tasa de error aceptable
- Disponibilidad objetivo

Toda decisión de escalado existe para proteger ese objetivo. Sin SLO,
un umbral de "50 % de CPU" es un número arbitrario.

## 2. Caracterizar la unidad de capacidad

Medir lo que puede hacer **una sola réplica** en aislamiento (benchmark):

| Pregunta | Resultado en este lab |
|---|---|
| ¿Cuánto recurso consume cada petición? | ~300 ms de CPU (`/api/work`) |
| ¿Dónde satura? | ~3 req/s con `limits.cpu: 1` |
| ¿Cuánto tarda en estar lista? | ~10-20 s (JVM + readiness probe) |

De estas medidas salen los `resources`:

- `requests` ≈ consumo típico medido + margen
- `limits` ≈ techo razonable sin comprometer al vecino

## 3. Elegir la señal de escalado

La métrica debe **correlacionarse con la demanda real** y reaccionar
antes de que se incumpla el SLO:

- **Recursos (CPU/memoria)**: proxy simple; peticiones → CPU → réplicas.
- **Métricas de aplicación** (req/s por pod, latencia, tamaño de cola):
  más directas, pero requieren pipeline de métricas (Prometheus…).
- **Regla práctica**: escalar al ~60-75 % de la capacidad saturada,
  nunca al 100 % — hay que dejar margen para el tiempo de reacción.

## 4. Calibrar el umbral con el margen de reacción

El umbral no es la capacidad máxima: es *capacidad menos la demanda que
puede llegar mientras el sistema reacciona*:

```
tiempo_reaccion = scrape_interval + polling KEDA + decisión HPA
                + scheduling + pull de imagen + startup del pod

demanda_reaccion = tasa_de_llegada × tiempo_reaccion

umbral ≈ capacidad_por_pod − demanda_reaccion
```

Ejemplo del lab: un pod completa ~3 req/s de `/api/work`; con
`threshold: 2` se deja ~33 % de margen para esa ventana de reacción.
Un `threshold: 5` *sonaba* razonable pero era imposible de alcanzar
midiendo — solo el benchmark lo revela.

## 5. Diseñar el comportamiento (behavior)

- **Scale-up agresivo** (duplicar rápido, `stabilizationWindowSeconds: 0`):
  la sobrecarga cuesta más que sobreaprovisionar un rato.
- **Scale-down conservador** (`stabilizationWindow`, `cooldownPeriod`,
  % por periodo): evita *flapping* — crear y destruir pods en ciclo ante
  tráfico ruidoso.
- **`minReplicaCount`**: capacidad para el piso de tráfico + tolerancia
  a fallos.
- **`maxReplicaCount`**: límite de coste y *blast radius* (un bug o un
  ataque no debe escalar sin techo).

## 6. Validar con pruebas de carga representativas

Patrones de prueba y qué revelan:

| Patrón | Qué valida |
|---|---|
| **Ramp** (subida gradual) | El autoscaler sigue el ritmo sin saturar |
| **Step** (saltos de carga) | Tiempo de reacción vs. llegada de carga |
| **Spike** (pico repentino) | Resiliencia: ¿sobrevive el SLO? |
| **Soak** (sostenida) | Deriva, fugas de memoria, estabilidad del scale-down |

Se observa: ¿reacciona a tiempo? ¿oscila? ¿se mantuvo el SLO? Se ajusta
y se repite. **Es un bucle, no un cálculo único.**

## 7. Operar y reajustar

- Dashboards del autoscaler y de la métrica de disparo.
- Alertas útiles: *maxReplicas tocado con frecuencia* (capacidad
  insuficiente) y *umbral nunca superado* (sobreaprovisionado = gasto
  innecesario).
- Los valores **caducan**: cada cambio de código, de tráfico o de
  infraestructura reabre la calibración.

## La regla mental

> **Medir → configurar → probar bajo carga → observar → ajustar.**

Los valores correctos son los que cumplen el SLO con el mínimo coste,
verificados empíricamente — nunca los que "suenan razonables".

## Referencias

- [README.md](README.md) — guía principal del laboratorio
- [03-scaledobject-y-carga.md](03-scaledobject-y-carga.md) — aplicación práctica (scaler CPU)
- [04-escalado-prometheus.md](04-escalado-prometheus.md) — calibración de `threshold` en el scaler Prometheus
