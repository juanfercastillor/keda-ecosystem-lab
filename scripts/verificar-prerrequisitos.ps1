<#
.SYNOPSIS
    Verifica que el entorno esté listo para el laboratorio KEDA (PowerShell).

.DESCRIPTION
    No modifica nada: solo comprueba herramientas y el contexto de kubectl.
    Equivalente a verificar-prerrequisitos.sh (Linux/macOS).

.EXAMPLE
    .\scripts\verificar-prerrequisitos.ps1
#>

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ok = 0
$fail = 0

function Test-Herramienta($nombre, $comando, $argumentos) {
    if (Get-Command $comando -ErrorAction SilentlyContinue) {
        $salida = (& $comando @argumentos 2>&1 | Select-Object -First 1)
        Write-Host "  [OK]    ${nombre}: $salida"
        $script:ok++
    } else {
        Write-Host "  [FALTA] $nombre"
        $script:fail++
    }
}

Write-Host "Herramientas:"
Test-Herramienta "kubectl" "kubectl" @("version", "--client")
Test-Herramienta "helm" "helm" @("version", "--short")
Test-Herramienta "curl" "curl.exe" @("--version")

Write-Host ""
Write-Host "Runtime de contenedores (necesitas UNO):"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "  [OK]    docker: $(docker --version)"
} elseif (Get-Command podman -ErrorAction SilentlyContinue) {
    Write-Host "  [OK]    podman: $(podman --version) (usa 07-entorno-kind-podman.md)"
} else {
    Write-Host "  [FALTA] docker o podman"
    $fail++
}

Write-Host ""
Write-Host "Clúster local (opcional si usas Docker Desktop con Kubernetes):"
if (Get-Command kind -ErrorAction SilentlyContinue) {
    Write-Host "  [OK]    kind: $(kind version)"
} else {
    Write-Host "  [INFO]  kind no instalado (solo necesario con podman)"
}

Write-Host ""
$ctx = ""
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    $ctx = (kubectl config current-context 2>$null)
}
Write-Host "Contexto actual de kubectl: $(if ($ctx) { $ctx } else { '<ninguno>' })"
if (-not $ctx) {
    Write-Host "  [AVISO] sin contexto: crea el clúster (07-entorno-kind-podman.md) o activa Kubernetes en Docker Desktop"
} elseif ($ctx -match '^(docker-desktop|minikube|rancher-desktop|kind-.*)$') {
    Write-Host "  [OK]    parece un clúster local de laboratorio"
} else {
    Write-Host "  [PELIGRO] '$ctx' NO parece un clúster local."
    Write-Host "            No ejecutes el laboratorio ahí. Cambia de contexto o usa --context en cada comando."
    $fail++
}

Write-Host ""
Write-Host "Resultado: $ok OK, $fail problema(s)."
exit $(if ($fail -eq 0) { 0 } else { 1 })
