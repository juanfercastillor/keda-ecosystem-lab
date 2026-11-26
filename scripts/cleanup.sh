#!/usr/bin/env bash
# Limpia el entorno creado por setup.sh (Linux / macOS / WSL).
#
# Borra SOLO lo que setup.sh creó, según ~/.keda-lab-state:
#   - clúster kind 'keda-lab' (incluye KEDA, metrics-server y la app), o
#   - en Docker Desktop: namespace elasticity-lab y, si lo instaló setup, KEDA y metrics-server
#   - imagen local elasticity-api
#   - restaura el contexto de kubectl que tenías antes
# Con --todo borra además las herramientas que setup instaló (kubectl/helm/kind).
#
# Uso:
#   ./scripts/cleanup.sh            # pide confirmación
#   ./scripts/cleanup.sh --yes      # sin preguntas
#   ./scripts/cleanup.sh --todo     # también quita herramientas instaladas por setup

set -u
CLUSTER="keda-lab"
IMAGE="elasticity-api:0.0.1"
STATE="$HOME/.keda-lab-state"
YES=0; TODO=0
for a in "$@"; do
    case "$a" in
        --yes|-y) YES=1 ;;
        --todo)   TODO=1 ;;
        -h|--help) sed -n 2,15p "$0"; exit 0 ;;
        *) echo "Opción desconocida: $a (usa --help)"; exit 2 ;;
    esac
done

info() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
state_get() { grep "^$1=" "$STATE" 2>/dev/null | head -1 | cut -d= -f2-; }

BIN="$(state_get BIN)"; BIN="${BIN:-$HOME/.local/bin}"
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac

MODE="$(state_get MODE)"; RUNTIME="$(state_get RUNTIME)"; PREV="$(state_get PREV_CONTEXT)"
if [ -z "$MODE" ]; then
    echo "No hay estado de setup ($STATE). Se intentará detectar lo creado por el laboratorio."
    if have kind && KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters 2>/dev/null | grep -qx "$CLUSTER" \
       || { have kind && kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }; then MODE=kind
    elif have kubectl && kubectl --context docker-desktop get ns elasticity-lab >/dev/null 2>&1; then MODE=docker-desktop
    else echo "No se encontró nada que limpiar."; exit 0; fi
fi
[ -z "$RUNTIME" ] && { have podman && ! (have docker && docker info >/dev/null 2>&1) && RUNTIME=podman || RUNTIME=docker; }
[ "$RUNTIME" = podman ] && export KIND_EXPERIMENTAL_PROVIDER=podman

echo "Se va a limpiar (modo: $MODE):"
[ "$MODE" = kind ] && echo "  - clúster kind '$CLUSTER'" || echo "  - namespace elasticity-lab (y KEDA/metrics-server solo si los instaló setup)"
echo "  - imagen local $IMAGE"
[ -n "$PREV" ] && echo "  - restaurar contexto de kubectl: $PREV"
[ "$TODO" = 1 ] && echo "  - herramientas instaladas por setup: $(for t in KUBECTL HELM KIND; do [ "$(state_get INSTALLED_$t)" = 1 ] && printf '%s ' "$t" | tr A-Z a-z; done)"
if [ "$YES" = 0 ]; then
    printf "¿Continuar? [s/N] "; read -r r || r=n
    case "$r" in s|S|si|SI|y|Y) ;; *) echo "Cancelado."; exit 1 ;; esac
fi

if [ "$MODE" = kind ]; then
    info "Borrando clúster kind $CLUSTER"
    kind delete cluster --name "$CLUSTER"
else
    C="docker-desktop"
    info "Borrando namespace elasticity-lab"
    kubectl --context "$C" delete namespace elasticity-lab --ignore-not-found
    if [ "$(state_get INSTALLED_KEDA)" = 1 ]; then
        info "Desinstalando KEDA (instalado por setup)"
        helm --kube-context "$C" uninstall keda -n keda; kubectl --context "$C" delete namespace keda --ignore-not-found
    fi
    if [ "$(state_get INSTALLED_METRICS)" = 1 ]; then
        info "Borrando metrics-server (instalado por setup)"
        kubectl --context "$C" delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
    fi
fi

info "Borrando imagen local"
if [ "$RUNTIME" = podman ]; then
    podman rmi -f "localhost/$IMAGE" "docker.io/library/$IMAGE" >/dev/null 2>&1
else
    docker rmi -f "$IMAGE" >/dev/null 2>&1
fi
rm -f "${TMPDIR:-/tmp}/elasticity-api.tar"

if [ -n "$PREV" ] && kubectl config get-contexts -o name 2>/dev/null | grep -qx "$PREV"; then
    info "Restaurando contexto de kubectl: $PREV"
    kubectl config use-context "$PREV" >/dev/null
fi

if [ "$TODO" = 1 ]; then
    for t in kubectl helm kind; do
        if [ "$(state_get INSTALLED_$(echo $t | tr a-z A-Z))" = 1 ]; then
            info "Quitando $t instalado por setup"; rm -f "$BIN/$t"
        fi
    done
    rm -f "$STATE"
    echo "Estado eliminado."
else
    for k in MODE CONTEXT RUNTIME PREV_CONTEXT CLUSTER_CREATED INSTALLED_KEDA INSTALLED_METRICS; do
        grep -v "^$k=" "$STATE" > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE"
    done
    echo "Herramientas conservadas (usa --todo para quitar las instaladas por setup)."
fi
echo "Limpieza terminada."
