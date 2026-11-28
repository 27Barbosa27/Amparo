# A app no Chrome, numa janela do tamanho de um telemóvel, com hot reload automático.
#   .\scripts\chrome.ps1                # abre no ecrã de Entrar e recarrega sozinho quando gravas um .dart
#   .\scripts\chrome.ps1 -Tela hoje     # abre direto num ecrã: entrar-erro | hoje | simples | sucesso | receitas | mais ...
#   .\scripts\chrome.ps1 -Api http://127.0.0.1:3000
#   .\scripts\chrome.ps1 -Parar         # fecha o servidor e a janela (se ficaram a correr)
#
# O script fica a correr neste terminal: ao gravar um ficheiro em lib\ envia o "r" (hot reload) ao Flutter,
# e a janela atualiza em 1 a 2 segundos, sem perder o ecrã onde estás. Nas mudanças que o hot reload não
# apanha (assets, pubspec, main.dart) escreve "R" aqui no terminal para reiniciar, e "q" ou Ctrl+C para sair.
# Tem de haver UMA só página ligada ao servidor (esta janela): com outra aberta o Flutter não reinicia.
#
# Serve para ver o aspeto e os fluxos. NÃO testa alarmes, notificações push, permissões nem o que acontece
# com a app fechada: para isso usa o telemóvel virtual (scripts\emulador.ps1) ou um telemóvel a sério.
param([string]$Tela = '', [int]$Porta = 8099, [string]$Api = '', [switch]$Parar)

# O Flutter de cada máquina: o que está no PATH, senão os sítios habituais de quem trabalha no projeto.
$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) {
    $flutter = @("$env:USERPROFILE\flutter\bin\flutter.bat", 'D:\flutter\bin\flutter.bat', 'C:\flutter\bin\flutter.bat') |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $flutter) { throw 'Não encontrei o Flutter: ponha a pasta flutter\bin no PATH.' }
$projeto = Split-Path -Parent $PSScriptRoot

function Parar-Tudo {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "web-server.*--web-port $Porta|chrome.*amparo-perfil" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($Parar) { Parar-Tudo; 'Parado.'; return }

$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LocalAppData\Google\Chrome\Application\chrome.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome não encontrado.' }

Parar-Tudo   # sobras de uma execução anterior

$argumentos = "run -d web-server --web-port $Porta --web-hostname 127.0.0.1"
if ($Tela) { $argumentos += " --dart-define=TELA=$Tela" }
if ($Api) { $argumentos += " --dart-define=API_URL=$Api" }

# O ID de cliente web da Google vem do backend\.env (o primeiro de GOOGLE_CLIENT_IDS), para não o escrever em dois sítios.
$envBackend = Join-Path (Split-Path -Parent $projeto) 'backend\.env'
if (Test-Path $envBackend) {
    $linha = Get-Content $envBackend | Where-Object { $_ -match '^GOOGLE_CLIENT_IDS=\s*\S' } | Select-Object -First 1
    if ($linha) { $argumentos += " --dart-define=GOOGLE_CLIENT_ID=$((($linha -split '=', 2)[1] -split ',')[0].Trim())" }
}

# O Flutter corre com a entrada redirecionada, para eu lhe poder escrever "r" quando gravas um ficheiro.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $flutter
$psi.Arguments = $argumentos
$psi.WorkingDirectory = $projeto
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$flt = [System.Diagnostics.Process]::Start($psi)

$estado = [hashtable]::Synchronized(@{ Servido = $false; Mudou = $false; Ultima = [DateTime]::MinValue })
$aoSaida = {
    if ($EventArgs.Data) {
        Write-Host $EventArgs.Data
        if ($EventArgs.Data -match 'is being served') { $Event.MessageData.Servido = $true }
    }
}
$null = Register-ObjectEvent -InputObject $flt -EventName OutputDataReceived -Action $aoSaida -MessageData $estado
$null = Register-ObjectEvent -InputObject $flt -EventName ErrorDataReceived -Action $aoSaida -MessageData $estado
$flt.BeginOutputReadLine()
$flt.BeginErrorReadLine()

# Vigia os .dart de lib\ (e os ficheiros de assets, que pedem reinício).
$vigia = New-Object System.IO.FileSystemWatcher (Join-Path $projeto 'lib'), '*.dart'
$vigia.IncludeSubdirectories = $true
$vigia.EnableRaisingEvents = $true
$aoMudar = { $Event.MessageData.Mudou = $true; $Event.MessageData.Ultima = [DateTime]::Now }
foreach ($ev in 'Changed', 'Created', 'Renamed') {
    $null = Register-ObjectEvent -InputObject $vigia -EventName $ev -Action $aoMudar -MessageData $estado
}

'A compilar para a web (a primeira vez demora um pouco)...'
try {
    $aberta = $false
    while (-not $flt.HasExited) {
        if (-not $aberta -and $estado.Servido) {
            # Perfil separado: não mexe nas tuas janelas nem nos teus dados do Chrome.
            Start-Process -FilePath $chrome -ArgumentList @("--app=http://127.0.0.1:$Porta", '--window-size=412,915', '--window-position=60,20', "--user-data-dir=$env:TEMP\amparo-perfil")
            "Aberto em http://127.0.0.1:$Porta (janela de 412x915). Grava um ficheiro .dart e a janela atualiza."
            $aberta = $true
        }
        # Espera 400 ms depois da última gravação (os editores gravam em vários passos) e recarrega.
        if ($aberta -and $estado.Mudou -and ([DateTime]::Now - $estado.Ultima).TotalMilliseconds -gt 400) {
            $estado.Mudou = $false
            $flt.StandardInput.WriteLine('r')
        }
        # Teclas escritas neste terminal seguem para o Flutter (R = reiniciar, q = sair).
        $temTecla = try { [Console]::KeyAvailable } catch { $false }   # sem consola (ex.: corrido em segundo plano) não há teclas
        if ($temTecla) {
            $tecla = [Console]::ReadKey($true).KeyChar
            $flt.StandardInput.WriteLine($tecla)
            if ($tecla -eq 'q') { break }
        }
        Start-Sleep -Milliseconds 150
    }
} finally {
    Get-EventSubscriber | Unregister-Event -Force -ErrorAction SilentlyContinue
    $vigia.Dispose()
    if (-not $flt.HasExited) { Stop-Process -Id $flt.Id -Force -ErrorAction SilentlyContinue }
    Parar-Tudo
}
