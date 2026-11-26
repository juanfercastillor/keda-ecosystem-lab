<#
.SYNOPSIS
    Instala y prepara TODO el entorno del laboratorio KEDA (Windows PowerShell).

.DESCRIPTION
    Verifica prerrequisitos, instala lo que falte SIN permisos de administrador
    (kubectl, helm, kind en %LOCALAPPDATA%\keda-lab\bin, con checksum), crea el
    clúster, instala metrics-server y KEDA, construye la imagen y despliega la
    app + ScaledObject.

    Es idempotente: lo que ya existe se omite. Registra lo que instaló en
    %USERPROFILE%\.keda-lab-state para que cleanup.ps1 borre SOLO eso.

    Requisito que NO instala: Docker Desktop o podman (necesitan privilegios).

.PARAMETER SoloVerificar
    Solo comprueba prerrequisitos; no cambia nada.
.PARAMETER SinScaledObject
    Deja todo listo menos el ScaledObject (para aplicarlo en vivo).
.PARAMETER Yes
    No pregunta confirmación.
.PARAMETER Kind
    Fuerza kind aunque exista el Kubernetes de Docker Desktop.

.EXAMPLE
    .\scripts\setup.ps1
    .\scripts\setup.ps1 -Yes
    .\scripts\setup.ps1 -SoloVerificar
#>
param(
    [switch]$SoloVerificar,
    [switch]$SinScaledObject,
    [switch]$Yes,
    [switch]$Kind
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$HelmVersion = '3.16.4'
$KindVersion = '0.24.0'
$KedaVersion = '2.21.0'
$Cluster = 'keda-lab'
$Image = 'elasticity-api:0.0.1'
$Bin = Join-Path $env:LOCALAPPDATA 'keda-lab\bin'
$State = Join-Path $env:USERPROFILE '.keda-lab-state'
$Root = Split-Path -Parent $PSScriptRoot

function Info($m) { Write-Host "==> $m" }
function Fail($m) { Write-Host "[ERROR] $m" -ForegroundColor Red; exit 1 }
function Have($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Test-Runtime($n) { if (-not (Have $n)) { return $false }; & $n info *> $null; return ($LASTEXITCODE -eq 0) }
function Check($m) { if ($LASTEXITCODE -ne 0) { Fail $m } }

function Get-State($k) {
    if (-not (Test-Path $State)) { return '' }
    $l = Get-Content $State | Where-Object { $_ -like "$k=*" } | Select-Object -First 1
    if ($l) { return $l.Substring($k.Length + 1) } else { return '' }
}
function Test-StateKey($k) { (Test-Path $State) -and [bool](Get-Content $State | Where-Object { $_ -like "$k=*" }) }
function Set-State($k, $v) {
    $lines = @()
    if (Test-Path $State) { $lines = @(Get-Content $State | Where-Object { $_ -notlike "$k=*" }) }
    $lines += "$k=$v"
    [IO.File]::WriteAllLines($State, $lines)
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }

# Descarga con 4 reintentos; muestra la causa real si falla
function Get-Download($url, $dest, $msg) {
    $ultimo = ''
    foreach ($i in 1..4) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -ErrorAction Stop; return }
        catch { $ultimo = $_.Exception.Message; Start-Sleep -Seconds (2 * $i) }
    }
    Fail "$msg`n        Causa: $ultimo"
}

function Get-Verified($url, $shaUrl, $dest) {
    Get-Download $url $dest "No se pudo descargar $url (¿proxy o sin conexión? Descárgalo manualmente)."
    $shaFile = "$dest.sha"
    Get-Download $shaUrl $shaFile "No se pudo descargar el checksum de $url"
    $esperado = ((Get-Content $shaFile -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
    Remove-Item $shaFile -Force
    if ($esperado -ne $actual) { Fail "Checksum inválido para $url" }
}

function Install-Kubectl {
    $v = (Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.k8s.io/release/stable.txt').Content.ToString().Trim()
    Get-Verified "https://dl.k8s.io/release/$v/bin/windows/$arch/kubectl.exe" "https://dl.k8s.io/release/$v/bin/windows/$arch/kubectl.exe.sha256" (Join-Path $Bin 'kubectl.exe')
}
function Install-Helm {
    $f = "helm-v$HelmVersion-windows-$arch.zip"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "keda-helm-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Get-Verified "https://get.helm.sh/$f" "https://get.helm.sh/$f.sha256sum" (Join-Path $tmp $f)
    Expand-Archive -Path (Join-Path $tmp $f) -DestinationPath $tmp -Force
    Copy-Item (Join-Path $tmp "windows-$arch\helm.exe") (Join-Path $Bin 'helm.exe') -Force
    Remove-Item $tmp -Recurse -Force
}
function Install-Kind {
    Get-Verified "https://kind.sigs.k8s.io/dl/v$KindVersion/kind-windows-$arch" "https://kind.sigs.k8s.io/dl/v$KindVersion/kind-windows-$arch.sha256sum" (Join-Path $Bin 'kind.exe')
}

# ---------------------------------------------------------------- 1. verificación
Info '1/8 Verificando prerrequisitos'
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
if (($env:PATH -split ';') -notcontains $Bin) { $env:PATH = "$Bin;$env:PATH" }

$Runtime = ''
if (Test-Runtime docker) { $Runtime = 'docker' }
elseif (Test-Runtime podman) { $Runtime = 'podman' }
elseif (Have docker) { Fail 'Docker está instalado pero el daemon no responde. Inicia Docker Desktop y reintenta.' }
elseif (Have podman) { Fail 'podman está instalado pero no responde. Ejecuta: podman machine init; podman machine start' }
else { Fail 'Falta un runtime de contenedores. Instala Docker Desktop o podman (requiere privilegios, el script no lo hace) y reintenta.' }
Write-Host "  runtime: $Runtime"

$Faltan = @()
if (-not (Have kubectl)) { $Faltan += 'kubectl' }
if (-not (Have helm)) { $Faltan += 'helm' }

$Mode = 'kind'
if ($Runtime -eq 'docker' -and -not $Kind -and (Have kubectl) -and ((kubectl config get-contexts -o name 2>$null) -contains 'docker-desktop')) { $Mode = 'docker-desktop' }
if ($Mode -eq 'kind' -and -not (Have kind)) { $Faltan += 'kind' }

$C = if ($Mode -eq 'docker-desktop') { 'docker-desktop' } else { "kind-$Cluster" }
$actual = if (Have kubectl) { (kubectl config current-context 2>$null) } else { '' }
Write-Host "  modo: $Mode (contexto de trabajo: $C)"
Write-Host "  contexto actual de kubectl: $(if ($actual) { $actual } else { '<ninguno>' })"
Write-Host "  herramientas a instalar en ${Bin}: $(if ($Faltan) { $Faltan -join ' ' } else { 'ninguna' })"

if ($SoloVerificar) { Info '-SoloVerificar: no se cambia nada.'; exit 0 }

if (-not $Yes) {
    Write-Host ''
    Write-Host "Se instalarán las herramientas faltantes, se creará/usará el clúster '$C',"
    Write-Host "y se desplegarán KEDA $KedaVersion, metrics-server y elasticity-api."
    $r = Read-Host '¿Continuar? [s/N]'
    if ($r -notmatch '^(s|si|y|yes)$') { Write-Host 'Cancelado.'; exit 1 }
}

# ---------------------------------------------------------------- 2. herramientas
Info '2/8 Instalando herramientas faltantes'
foreach ($t in $Faltan) {
    Write-Host "  instalando $t..."
    switch ($t) { 'kubectl' { Install-Kubectl } 'helm' { Install-Helm } 'kind' { Install-Kind } }
    if (-not (Have $t)) { Fail "No se pudo instalar $t" }
    Set-State "INSTALLED_$($t.ToUpper())" 1
}
Set-State MODE $Mode; Set-State CONTEXT $C; Set-State RUNTIME $Runtime; Set-State BIN $Bin
if (-not (Test-StateKey PREV_CONTEXT)) {
    $prev = (kubectl config current-context 2>$null)
    if ($prev -eq $C) { $prev = '' }
    Set-State PREV_CONTEXT $prev
}

# ---------------------------------------------------------------- 3. clúster
Info "3/8 Preparando clúster ($Mode)"
if ($Runtime -eq 'podman') { $env:KIND_EXPERIMENTAL_PROVIDER = 'podman' }
if ($Mode -eq 'kind') {
    if ((kind get clusters 2>$null) -contains $Cluster) {
        Write-Host "  clúster $Cluster ya existe: se reutiliza"
    } else {
        kind create cluster --name $Cluster --config (Join-Path $Root 'k8s\kind-config.yaml')
        Check 'No se pudo crear el clúster kind.'
        Set-State CLUSTER_CREATED 1
    }
}
kubectl --context $C wait --for=condition=Ready node --all --timeout=180s
Check 'El nodo no llegó a Ready.'

# ---------------------------------------------------------------- 4. metrics-server
Info '4/8 metrics-server'
kubectl --context $C -n kube-system get deploy metrics-server 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  ya existe: se omite'
} else {
    kubectl --context $C apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml | Out-Null
    Check 'No se pudo aplicar metrics-server.'
    $patch = '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
    $patchFile = Join-Path ([IO.Path]::GetTempPath()) 'keda-ms-patch.json'
    [IO.File]::WriteAllText($patchFile, $patch)
    kubectl --context $C patch deployment metrics-server -n kube-system --type=json --patch-file $patchFile | Out-Null
    Remove-Item $patchFile -Force
    Set-State INSTALLED_METRICS 1
}
kubectl --context $C -n kube-system rollout status deploy/metrics-server --timeout=180s
Check 'metrics-server no quedó listo.'

# ---------------------------------------------------------------- 5. KEDA
Info "5/8 KEDA $KedaVersion"
$existente = helm --kube-context $C list -A -q --filter '^keda$' 2>$null
if ($existente) {
    Write-Host '  KEDA ya instalado en el clúster: se reutiliza'
} else {
    $ok = $false
    foreach ($i in 1..4) {
        $out = helm repo add kedacore https://kedacore.github.io/charts --force-update 2>&1
        if ($LASTEXITCODE -eq 0) { helm repo update kedacore 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $ok = $true; break } }
        Start-Sleep -Seconds (2 * $i)
    }
    if (-not $ok) { Fail "No se pudo añadir el repositorio de KEDA: $out" }
    helm --kube-context $C install keda kedacore/keda -n keda --create-namespace --version $KedaVersion | Out-Null
    Check 'Falló helm install keda.'
    Set-State INSTALLED_KEDA 1
}
foreach ($d in 'keda-operator', 'keda-operator-metrics-apiserver', 'keda-admission-webhooks') {
    kubectl --context $C -n keda rollout status "deploy/$d" --timeout=240s
    Check "$d no quedó listo."
}

# ---------------------------------------------------------------- 6. imagen
Info "6/8 Construyendo imagen $Image"
Push-Location (Join-Path $Root 'elasticity-api')
if ($Runtime -eq 'docker') {
    docker build -t $Image .
    Check 'Falló docker build.'
    if ($Mode -eq 'kind') { kind load docker-image $Image --name $Cluster; Check 'Falló kind load.' }
} else {
    $tar = Join-Path ([IO.Path]::GetTempPath()) 'elasticity-api.tar'
    podman build -t "localhost/$Image" .
    Check 'Falló podman build.'
    podman tag "localhost/$Image" "docker.io/library/$Image"
    if (Test-Path $tar) { Remove-Item $tar -Force }
    podman save "docker.io/library/$Image" -o $tar
    Check 'Falló podman save.'
    kind load image-archive $tar --name $Cluster
    Check 'Falló kind load.'
    Remove-Item $tar -Force -ErrorAction SilentlyContinue
}
Pop-Location

# ---------------------------------------------------------------- 7. despliegue
Info '7/8 Desplegando elasticity-api'
Push-Location $Root
kubectl --context $C apply -f k8s/00-namespace.yaml -f k8s/10-deployment.yaml -f k8s/11-service.yaml
Check 'Falló el despliegue.'
kubectl --context $C -n elasticity-lab rollout status deploy/elasticity-api --timeout=300s
Check 'elasticity-api no quedó listo (¿ImagePullBackOff? ver 05-solucion-de-problemas.md).'

if ($SinScaledObject) {
    Info '8/8 -SinScaledObject: se omite el ScaledObject'
} else {
    Info '8/8 ScaledObject'
    kubectl --context $C apply -f k8s/20-scaledobject-cpu.yaml 2>&1 | Where-Object { $_ -notmatch '^Warning' }
}
Pop-Location

Write-Host ''
Write-Host "Listo. Contexto: $C"
Write-Host 'Siguiente:'
Write-Host "  kubectl --context $C -n elasticity-lab get scaledobject,hpa"
if ($Mode -eq 'kind') {
    Write-Host '  curl.exe http://localhost:30080/api/hello        # NodePort: balancea entre todas las réplicas'
    Write-Host '  .\scripts\carga.ps1 -Concurrencia 20 -DuracionSegundos 120 -Url "http://localhost:30080/api/work?ms=300"'
} else {
    Write-Host "  kubectl --context $C -n elasticity-lab port-forward svc/elasticity-api 8080:8080   # otra terminal"
    Write-Host '  .\scripts\carga.ps1 -Concurrencia 20 -DuracionSegundos 120'
}
Write-Host 'Limpieza: .\scripts\cleanup.ps1   (o -Todo para quitar también las herramientas instaladas)'
Write-Host "Nota: para usar kubectl/helm/kind en nuevas terminales añade $Bin al PATH del usuario."
