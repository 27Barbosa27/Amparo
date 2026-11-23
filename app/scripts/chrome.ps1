# A app no Chrome, numa janela do tamanho de um telemóvel. Muito mais rápido e leve do que o emulador.
#   .\scripts\chrome.ps1            # abre no ecrã de Entrar
#   .\scripts\chrome.ps1 -Tela hoje # abre direto num ecrã: entrar-erro | hoje | simples | sucesso
#   .\scripts\chrome.ps1 -Parar     # fecha o servidor
#
# Serve para ver o aspeto e os fluxos. NÃO testa alarmes, notificações push, permissões nem o que acontece
# com a app fechada: para isso usa o telemóvel virtual (scripts\emulador.ps1) ou um telemóvel a sério.
param([string]$Tela = '', [int]$Porta = 8099, [switch]$Parar)

$flutter = 'C:\Users\zedop\flutter\bin\flutter.bat'
$projeto = Split-Path -Parent $PSScriptRoot

if ($Parar) {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "web-server.*--web-port $Porta|chrome.*amparo-perfil" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    'Parado.'
    return
}

$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LocalAppData\Google\Chrome\Application\chrome.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome não encontrado.' }

$args2 = @('run', '-d', 'web-server', '--web-port', $Porta, '--web-hostname', '127.0.0.1')
if ($Tela) { $args2 += "--dart-define=TELA=$Tela" }
Start-Process -FilePath $flutter -ArgumentList $args2 -WorkingDirectory $projeto -WindowStyle Hidden `
    -RedirectStandardOutput "$env:TEMP\amparo-web.log" -RedirectStandardError "$env:TEMP\amparo-web.err"

'A compilar para a web (a primeira vez demora um pouco)...'
for ($i = 0; $i -lt 120; $i++) {
    if ((Test-Path "$env:TEMP\amparo-web.log") -and (Select-String -Path "$env:TEMP\amparo-web.log" -Pattern 'is being served|lib/main.dart is being served' -Quiet)) { break }
    Start-Sleep -Seconds 3
}
# Perfil separado: não mexe nas tuas janelas nem nos teus dados do Chrome.
Start-Process -FilePath $chrome -ArgumentList @("--app=http://127.0.0.1:$Porta", '--window-size=412,915', '--window-position=60,20', "--user-data-dir=$env:TEMP\amparo-perfil")
"Aberto em http://127.0.0.1:$Porta (janela de 412x915)."
