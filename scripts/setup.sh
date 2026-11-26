#!/usr/bin/env bash
# Instala y prepara TODO el entorno del laboratorio KEDA (Linux / macOS / WSL).
#
# Verifica prerrequisitos, instala lo que falte SIN sudo (kubectl, helm, kind
# en ~/.local/bin, con checksum), crea el clúster, instala metrics-server y
# KEDA, construye la imagen y despliega la app + ScaledObject.
#
# Es idempotente: lo que ya existe se omite. Registra lo que instaló en
# ~/.keda-lab-state para que cleanup.sh borre SOLO eso.
#
# Uso:
#   ./scripts/setup.sh                    # preguntas de confirmación
#   ./scripts/setup.sh --yes              # sin preguntas
#   ./scripts/setup.sh --solo-verificar   # solo comprueba, no cambia nada
#   ./scripts/setup.sh --sin-scaledobject # deja todo listo menos el ScaledObject
#   ./scripts/setup.sh --kind             # fuerza kind aunque haya Docker Desktop k8s
#
# Requisito que NO instala: Docker o podman (necesitan privilegios).

set -u

HELM_VERSION="3.16.4"
KIND_VERSION="0.24.0"
KEDA_VERSION="2.21.0"
CLUSTER="keda-lab"
IMAGE="elasticity-api:0.0.1"
BIN="$HOME/.local/bin"
STATE="$HOME/.keda-lab-state"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SOLO_VERIFICAR=0; SIN_SO=0; YES=0; FORCE_KIND=0
for a in "$@"; do
    case "$a" in
        --solo-verificar)   SOLO_VERIFICAR=1 ;;
        --sin-scaledobject) SIN_SO=1 ;;
        --yes|-y)           YES=1 ;;
        --kind)             FORCE_KIND=1 ;;
        -h|--help)          sed -n 2,20p "$0"; exit 0 ;;
        *) echo "Opción desconocida: $a (usa --help)"; exit 2 ;;
    esac
done

info() { echo "==> $*"; }
warn() { echo "[AVISO] $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

state_set() { # clave valor
    touch "$STATE"
    grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null
    echo "$1=$2" >> "$STATE.tmp"
    mv "$STATE.tmp" "$STATE"
}
state_get() { grep "^$1=" "$STATE" 2>/dev/null | head -1 | cut -d= -f2-; }

case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) fail "Sistema no soportado: $(uname -s). En Windows usa scripts\\setup.ps1 o setup.cmd" ;;
esac
case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) fail "Arquitectura no soportada: $(uname -m)" ;;
esac
have curl || fail "Falta curl."

sha256() { if have sha256sum; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

# descargar <url> <url-checksum> <destino>  (verifica SHA-256)
download_verify() {
    curl -fsSL --retry 4 --retry-all-errors --retry-delay 2 "$1" -o "$3" || fail "No se pudo descargar $1 (¿proxy o sin conexión? Descárgalo manualmente)."
    local esperado actual
    esperado=$(curl -fsSL --retry 4 --retry-all-errors --retry-delay 2 "$2" | awk '{print $1}')
    actual=$(sha256 "$3")
    [ -n "$esperado" ] || fail "No se pudo descargar el checksum de $1"
    [ "$esperado" = "$actual" ] || fail "Checksum inválido para $1"
}

install_kubectl() {
    local v tmp; v=$(curl -fsSL --retry 4 --retry-all-errors https://dl.k8s.io/release/stable.txt) || fail "No se pudo consultar la versión de kubectl."
    tmp=$(mktemp)
    download_verify "https://dl.k8s.io/release/$v/bin/$OS/$ARCH/kubectl" "https://dl.k8s.io/release/$v/bin/$OS/$ARCH/kubectl.sha256" "$tmp"
    install -m 0755 "$tmp" "$BIN/kubectl" && rm -f "$tmp"
}
install_helm() {
    local d f; d=$(mktemp -d); f="helm-v$HELM_VERSION-$OS-$ARCH.tar.gz"
    download_verify "https://get.helm.sh/$f" "https://get.helm.sh/$f.sha256sum" "$d/$f"
    tar -xzf "$d/$f" -C "$d" && install -m 0755 "$d/$OS-$ARCH/helm" "$BIN/helm"; rm -rf "$d"
}
install_kind() {
    local tmp; tmp=$(mktemp)
    download_verify "https://kind.sigs.k8s.io/dl/v$KIND_VERSION/kind-$OS-$ARCH" "https://kind.sigs.k8s.io/dl/v$KIND_VERSION/kind-$OS-$ARCH.sha256sum" "$tmp"
    install -m 0755 "$tmp" "$BIN/kind" && rm -f "$tmp"
}

# ---------------------------------------------------------------- 1. verificación
info "1/8 Verificando prerrequisitos"
mkdir -p "$BIN"; case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac

RUNTIME=""
if have docker && docker info >/dev/null 2>&1; then RUNTIME=docker
elif have podman; then RUNTIME=podman
elif have docker; then fail "Docker está instalado pero el daemon no responde. Inicia Docker (o Docker Desktop) y reintenta."
else fail "Falta un runtime de contenedores. Instala Docker Desktop o podman (requiere privilegios, el script no lo hace) y reintenta."
fi
echo "  runtime: $RUNTIME"

FALTAN=()
have kubectl || FALTAN+=(kubectl)
have helm    || FALTAN+=(helm)
# kind solo hace falta si no se usa el Kubernetes de Docker Desktop (se decide abajo)

MODE=kind
if [ "$RUNTIME" = docker ] && [ "$FORCE_KIND" = 0 ] && have kubectl \
   && kubectl config get-contexts -o name 2>/dev/null | grep -qx docker-desktop; then
    MODE=docker-desktop
fi
[ "$MODE" = kind ] && ! have kind && FALTAN+=(kind)

if [ "$MODE" = docker-desktop ]; then C="docker-desktop"; else C="kind-$CLUSTER"; fi
echo "  modo: $MODE (contexto de trabajo: $C)"
echo "  contexto actual de kubectl: $(kubectl config current-context 2>/dev/null || echo '<ninguno>')"
echo "  herramientas a instalar en $BIN: ${FALTAN[*]:-ninguna}"

if [ "$SOLO_VERIFICAR" = 1 ]; then info "--solo-verificar: no se cambia nada."; exit 0; fi

if [ "$YES" = 0 ]; then
    echo
    echo "Se instalarán las herramientas faltantes, se creará/usará el clúster '$C',"
    echo "y se desplegarán KEDA $KEDA_VERSION, metrics-server y elasticity-api."
    printf "¿Continuar? [s/N] "; read -r r || r=n
    case "$r" in s|S|si|SI|y|Y) ;; *) echo "Cancelado."; exit 1 ;; esac
fi

# ---------------------------------------------------------------- 2. herramientas
info "2/8 Instalando herramientas faltantes"
for t in "${FALTAN[@]:-}"; do
    [ -z "$t" ] && continue
    echo "  instalando $t..."
    "install_$t"; have "$t" || fail "No se pudo instalar $t"
    state_set "INSTALLED_$(echo "$t" | tr a-z A-Z)" 1
done
state_set MODE "$MODE"; state_set CONTEXT "$C"; state_set RUNTIME "$RUNTIME"; state_set BIN "$BIN"
if ! grep -q "^PREV_CONTEXT=" "$STATE" 2>/dev/null; then   # solo la primera vez
    prev="$(kubectl config current-context 2>/dev/null)"
    [ "$prev" = "$C" ] && prev=""
    state_set PREV_CONTEXT "$prev"
fi

# ---------------------------------------------------------------- 3. clúster
info "3/8 Preparando clúster ($MODE)"
[ "$RUNTIME" = podman ] && export KIND_EXPERIMENTAL_PROVIDER=podman
if [ "$MODE" = kind ]; then
    if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
        echo "  clúster $CLUSTER ya existe: se reutiliza"
    else
        kind create cluster --name "$CLUSTER" || fail "No se pudo crear el clúster kind."
        state_set CLUSTER_CREATED 1
    fi
fi
kubectl --context "$C" wait --for=condition=Ready node --all --timeout=180s || fail "El nodo no llegó a Ready."

# ---------------------------------------------------------------- 4. metrics-server
info "4/8 metrics-server"
if kubectl --context "$C" -n kube-system get deploy metrics-server >/dev/null 2>&1; then
    echo "  ya existe: se omite"
else
    kubectl --context "$C" apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null || fail "No se pudo aplicar metrics-server."
    kubectl --context "$C" patch deployment metrics-server -n kube-system --type=json \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
    state_set INSTALLED_METRICS 1
fi
kubectl --context "$C" -n kube-system rollout status deploy/metrics-server --timeout=180s || fail "metrics-server no quedó listo."

# ---------------------------------------------------------------- 5. KEDA
info "5/8 KEDA $KEDA_VERSION"
if [ -n "$(helm --kube-context "$C" list -A -q --filter '^keda$' 2>/dev/null)" ]; then
    echo "  KEDA ya instalado en el clúster: se reutiliza"
else
    ok=0
    for i in 1 2 3 4; do
        if helm repo add kedacore https://kedacore.github.io/charts --force-update >/dev/null 2>&1 && helm repo update kedacore >/dev/null 2>&1; then ok=1; break; fi
        sleep $((2 * i))
    done
    [ "$ok" = 1 ] || fail "No se pudo añadir el repositorio de KEDA (¿red/proxy?)."
    helm --kube-context "$C" install keda kedacore/keda -n keda --create-namespace --version "$KEDA_VERSION" >/dev/null || fail "Falló helm install keda."
    state_set INSTALLED_KEDA 1
fi
for d in keda-operator keda-operator-metrics-apiserver keda-admission-webhooks; do
    kubectl --context "$C" -n keda rollout status "deploy/$d" --timeout=240s || fail "$d no quedó listo."
done

# ---------------------------------------------------------------- 6. imagen
info "6/8 Construyendo imagen $IMAGE"
cd "$ROOT/elasticity-api" || fail "No existe elasticity-api/"
if [ "$RUNTIME" = docker ]; then
    docker build -t "$IMAGE" . || fail "Falló docker build."
    [ "$MODE" = kind ] && { kind load docker-image "$IMAGE" --name "$CLUSTER" || fail "Falló kind load."; }
else
    TAR="${TMPDIR:-/tmp}/elasticity-api.tar"
    podman build -t "localhost/$IMAGE" . || fail "Falló podman build."
    podman tag "localhost/$IMAGE" "docker.io/library/$IMAGE"
    podman save "docker.io/library/$IMAGE" -o "$TAR" && kind load image-archive "$TAR" --name "$CLUSTER" || fail "Falló kind load."
    rm -f "$TAR"
fi
cd "$ROOT" || exit 1

# ---------------------------------------------------------------- 7. despliegue
info "7/8 Desplegando elasticity-api"
kubectl --context "$C" apply -f k8s/00-namespace.yaml -f k8s/10-deployment.yaml -f k8s/11-service.yaml || fail "Falló el despliegue."
kubectl --context "$C" -n elasticity-lab rollout status deploy/elasticity-api --timeout=300s || fail "elasticity-api no quedó listo (¿ImagePullBackOff? ver 05-solucion-de-problemas.md)."

if [ "$SIN_SO" = 1 ]; then
    info "8/8 --sin-scaledobject: se omite el ScaledObject"
else
    info "8/8 ScaledObject"
    kubectl --context "$C" apply -f k8s/20-scaledobject-cpu.yaml 2>&1 | grep -v "^Warning" || true
fi

echo
echo "Listo. Contexto: $C"
echo "Siguiente:"
echo "  kubectl --context $C -n elasticity-lab get scaledobject,hpa"
echo "  kubectl --context $C -n elasticity-lab port-forward svc/elasticity-api 8080:8080   # otra terminal"
echo "  CONCURRENCIA=20 DURACION=120 ./scripts/carga.sh"
echo "Limpieza: ./scripts/cleanup.sh   (o --todo para quitar también las herramientas instaladas)"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Nota: añade $BIN a tu PATH para usar kubectl/helm/kind en nuevas terminales." ;; esac
