# Telemóvel virtual leve para testar o Amparo no Android.
#   .\scripts\emulador.ps1 ligar    # arranca (cerca de 2 GB de RAM no total)
#   .\scripts\emulador.ps1 desligar # fecha e liberta a RAM
#   .\scripts\emulador.ps1 estado   # mostra se está ligado e quanta RAM usa
#
# O telemóvel "amparo_leve": Android 11 com Google APIs, 1,5 GB de RAM, 2 núcleos, ecrã 720x1520,
# sem áudio, câmara nem cartão SD, arranque a frio (sem snapshot, que ocupa o tamanho da RAM em disco).
param([Parameter(Position = 0)][ValidateSet('ligar', 'desligar', 'estado')][string]$Acao = 'estado')

$sdk = 'C:\Users\zedop\Android\Sdk'
$env:ANDROID_SDK_ROOT = $sdk
$emulador = "$sdk\emulator\emulator.exe"
$adb = "$sdk\platform-tools\adb.exe"

function Processos { Get-Process -Name 'qemu-system-x86_64*', 'emulator*' -ErrorAction SilentlyContinue }

switch ($Acao) {
    'ligar' {
        if (Processos) { 'Já está ligado.'; break }
        # -no-snapshot-save/-no-snapshot: não grava o estado da RAM em disco; -memory/-cores: limites firmes.
        Start-Process -FilePath $emulador -WindowStyle Hidden -ArgumentList @(
            '-avd', 'amparo_leve', '-memory', '1536', '-cores', '2',
            '-no-audio', '-no-boot-anim', '-no-snapshot', '-gpu', 'auto', '-netdelay', 'none', '-netspeed', 'full'
        )
        'A arrancar (a primeira vez demora 1 a 3 minutos)...'
        & $adb wait-for-device | Out-Null
        for ($i = 0; $i -lt 120; $i++) {
            if ((& $adb shell getprop sys.boot_completed 2>$null) -match '1') { break }
            Start-Sleep -Seconds 3
        }
        'Pronto. Para correr a app: flutter run -d emulator-5554'
    }
    'desligar' {
        & $adb emu kill 2>$null | Out-Null
        Start-Sleep -Seconds 3
        Processos | Stop-Process -Force -ErrorAction SilentlyContinue
        'Desligado.'
    }
    'estado' {
        $p = Processos
        if (-not $p) { 'Desligado.'; break }
        $mb = ($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB
        'Ligado. RAM usada pelo emulador: {0:N0} MB' -f $mb
        & $adb devices
    }
}
