#!/usr/bin/env bash
# Verifica que el entorno esté listo para el laboratorio KEDA.
# Uso: ./scripts/verificar-prerrequisitos.sh
# No modifica nada: solo comprueba herramientas y el contexto de kubectl.

ok=0; fail=0
check() { # nombre comando-de-versión
    if out=$(eval "$2" 2>&1 | head -1); then
        echo "  [OK]    $1: $out"; ok=$((ok + 1))
    else
        echo "  [FALTA] $1"; fail=$((fail + 1))
    fi
}

echo "Herramientas:"
check "kubectl" "kubectl version --client"
check "helm" "helm version --short"
check "curl" "curl --version"

echo
echo "Runtime de contenedores (necesitas UNO):"
if command -v docker >/dev/null 2>&1; then
    echo "  [OK]    docker: $(docker --version)"
elif command -v podman >/dev/null 2>&1; then
    echo "  [OK]    podman: $(podman --version) (usa 07-entorno-kind-podman.md)"
else
    echo "  [FALTA] docker o podman"; fail=$((fail + 1))
fi

echo
echo "Clúster local (opcional si usas Docker Desktop con Kubernetes):"
command -v kind >/dev/null 2>&1 && echo "  [OK]    kind: $(kind version)" || echo "  [INFO]  kind no instalado (solo necesario con podman)"

echo
ctx=$(kubectl config current-context 2>/dev/null)
echo "Contexto actual de kubectl: ${ctx:-<ninguno>}"
case "$ctx" in
    docker-desktop|kind-*|minikube|rancher-desktop)
        echo "  [OK]    parece un clúster local de laboratorio" ;;
    "")
        echo "  [AVISO] sin contexto: crea el clúster (07-entorno-kind-podman.md) o activa Kubernetes en Docker Desktop" ;;
    *)
        echo "  [PELIGRO] '$ctx' NO parece un clúster local."
        echo "            No ejecutes el laboratorio ahí. Cambia de contexto o usa --context en cada comando."
        fail=$((fail + 1)) ;;
esac

echo
echo "Resultado: ${ok} OK, ${fail} problema(s)."
[ "$fail" -eq 0 ]
