<#
.SYNOPSIS
    Limpia el entorno creado por setup.ps1 (Windows PowerShell).

.DESCRIPTION
    Borra SOLO lo que setup creó, según %USERPROFILE%\.keda-lab-state:
      - clúster kind 'keda-lab' (incluye KEDA, metrics-server y la app), o
      - en Docker Desktop: namespace elasticity-lab y, si lo instaló setup,
        KEDA y metrics-server
      - imagen local elasticity-api
      - restaura el contexto de kubectl que tenías antes
    Con -Todo borra además las herramientas que setup instaló
    (kubectl/helm/kind).

.PARAMETER Yes
    No pregunta confirmación.
.PARAMETER Todo
    También quita las herramientas instaladas por setup.

.EXAMPLE
    .\scripts\cleanup.ps1
    .\scripts\cleanup.ps1 -Yes -Todo
#>
param(
    [switch]$Yes,
    [switch]$Todo
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = 'Continue'

$Cluster = 'keda-lab'
$Image = 'elasticity-api:0.0.1'
$State = Join-Path $env:USERPROFILE '.keda-lab-state'

function Info($m) { Write-Host "==> $m" }
function Have($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Get-State($k) {
    if (-not (Test-Path $State)) { return '' }
    $l = Get-Content $State | Where-Object { $_ -like "$k=*" } | Select-Object -First 1
    if ($l) { return $l.Substring($k.Length + 1) } else { return '' }
}

$Bin = Get-State BIN
if (-not $Bin) { $Bin = Join-Path $env:LOCALAPPDATA 'keda-lab\bin' }
if (($env:PATH -split ';') -notcontains $Bin) { $env:PATH = "$Bin;$env:PATH" }

$Mode = Get-State MODE
$Runtime = Get-State RUNTIME
$Prev = Get-State PREV_CONTEXT

if (-not $Mode) {
    Write-Host "No hay estado de setup ($State). Se intentará detectar lo creado por el laboratorio."
    $env:KIND_EXPERIMENTAL_PROVIDER = if (Have podman) { 'podman' } else { '' }
    if ((Have kind) -and ((kind get clusters 2>$null) -contains $Cluster)) { $Mode = 'kind' }
    elseif ((Have kubectl) -and ((kubectl --context docker-desktop get ns elasticity-lab 2>$null | Out-String).Trim())) { $Mode = 'docker-desktop' }
    else { Write-Host 'No se encontró nada que limpiar.'; exit 0 }
}
if (-not $Runtime) { $Runtime = if ((Have docker) -and -not (Have podman)) { 'docker' } elseif (Have podman) { 'podman' } else { 'docker' } }
if ($Runtime -eq 'podman') { $env:KIND_EXPERIMENTAL_PROVIDER = 'podman' }

Write-Host "Se va a limpiar (modo: $Mode):"
if ($Mode -eq 'kind') { Write-Host "  - clúster kind '$Cluster'" }
else { Write-Host '  - namespace elasticity-lab (y KEDA/metrics-server solo si los instaló setup)' }
Write-Host "  - imagen local $Image"
if ($Prev) { Write-Host "  - restaurar contexto de kubectl: $Prev" }
if ($Todo) {
    $tools = @('KUBECTL', 'HELM', 'KIND') | Where-Object { (Get-State "INSTALLED_$_") -eq '1' } | ForEach-Object { $_.ToLower() }
    Write-Host "  - herramientas instaladas por setup: $($tools -join ' ')"
}
if (-not $Yes) {
    $r = Read-Host '¿Continuar? [s/N]'
    if ($r -notmatch '^(s|si|y|yes)$') { Write-Host 'Cancelado.'; exit 1 }
}

if ($Mode -eq 'kind') {
    if (Have kind) { Info "Borrando clúster kind $Cluster"; kind delete cluster --name $Cluster }
    else { Write-Host '[AVISO] kind no está disponible: no se puede borrar el clúster.' }
} else {
    $C = 'docker-desktop'
    Info 'Borrando namespace elasticity-lab'
    kubectl --context $C delete namespace elasticity-lab --ignore-not-found
    if ((Get-State INSTALLED_KEDA) -eq '1') {
        Info 'Desinstalando KEDA (instalado por setup)'
        helm --kube-context $C uninstall keda -n keda
        kubectl --context $C delete namespace keda --ignore-not-found
    }
    if ((Get-State INSTALLED_METRICS) -eq '1') {
        Info 'Borrando metrics-server (instalado por setup)'
        kubectl --context $C delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
    }
}

Info 'Borrando imagen local'
if ($Runtime -eq 'podman' -and (Have podman)) {
    podman rmi -f "localhost/$Image" "docker.io/library/$Image" 2>&1 | Out-Null
} elseif (Have docker) {
    docker rmi -f $Image 2>&1 | Out-Null
}
Remove-Item (Join-Path ([IO.Path]::GetTempPath()) 'elasticity-api.tar') -Force -ErrorAction SilentlyContinue

if ($Prev -and (Have kubectl) -and ((kubectl config get-contexts -o name 2>$null) -contains $Prev)) {
    Info "Restaurando contexto de kubectl: $Prev"
    kubectl config use-context $Prev | Out-Null
}

if ($Todo) {
    foreach ($t in 'kubectl', 'helm', 'kind') {
        if ((Get-State "INSTALLED_$($t.ToUpper())") -eq '1') {
            Info "Quitando $t instalado por setup"
            Remove-Item (Join-Path $Bin "$t.exe") -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item $State -Force -ErrorAction SilentlyContinue
    if ((Test-Path $Bin) -and -not (Get-ChildItem $Bin)) { Remove-Item $Bin -Force; Remove-Item (Split-Path $Bin) -Force -ErrorAction SilentlyContinue }
    Write-Host 'Estado eliminado.'
} elseif (Test-Path $State) {
    $keep = Get-Content $State | Where-Object { $_ -match '^(INSTALLED_KUBECTL|INSTALLED_HELM|INSTALLED_KIND|BIN)=' }
    [IO.File]::WriteAllLines($State, @($keep))
    Write-Host 'Herramientas conservadas (usa -Todo para quitar las instaladas por setup).'
}
Write-Host 'Limpieza terminada.'
