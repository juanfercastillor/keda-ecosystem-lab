<#
.SYNOPSIS
    Generador de carga HTTP para el laboratorio de elasticidad con KEDA.

.DESCRIPTION
    Lanza rondas de peticiones HTTP concurrentes contra el endpoint /api/work
    del microservicio elasticity-api. Cada petición consume CPU durante `ms`
    milisegundos, lo que eleva la utilización de CPU del pod y dispara el
    escalado horizontal gestionado por KEDA.

.PARAMETER Url
    URL del endpoint de trabajo. Por defecto apunta al port-forward (8080).
    Alternativa si el NodePort está publicado: http://localhost:30080/api/work?ms=300

.PARAMETER Concurrencia
    Número de peticiones simultáneas por ronda.

.PARAMETER DuracionSegundos
    Duración total de la prueba de carga.

.EXAMPLE
    .\carga.ps1
    .\carga.ps1 -Concurrencia 40 -DuracionSegundos 600
    .\carga.ps1 -Url "http://localhost:8080/api/work?ms=500" -Concurrencia 10
#>
param(
    [string]$Url = "http://localhost:8080/api/work?ms=300",
    [int]$Concurrencia = 20,
    [int]$DuracionSegundos = 300
)

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(60)

$fin = (Get-Date).AddSeconds($DuracionSegundos)
$ronda = 0

Write-Host "Generando carga: $Concurrencia req concurrentes durante $DuracionSegundos s"
Write-Host "URL: $Url"
Write-Host "Pulsa Ctrl+C para detener.`n"

try {
    while ((Get-Date) -lt $fin) {
        $ronda++
        $tareas = 1..$Concurrencia | ForEach-Object { $client.GetAsync($Url) }

        try { [System.Threading.Tasks.Task]::WaitAll($tareas) } catch { }

        $ok = ($tareas | Where-Object { $_.Status -eq 'RanToCompletion' -and $_.Result.IsSuccessStatusCode }).Count
        Write-Host ("[{0}] ronda {1,4}: {2}/{3} OK" -f (Get-Date -Format "HH:mm:ss"), $ronda, $ok, $Concurrencia)
    }
}
finally {
    $client.Dispose()
}

Write-Host "`nCarga finalizada."
