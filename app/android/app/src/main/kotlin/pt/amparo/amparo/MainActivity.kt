package pt.amparo.amparo

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // O alarme abre a app por cima do ecrã bloqueado, mas só ele: o resto da app (com dados de saúde) nunca
    // aparece sem desbloquear. A app volta a desligar isto quando o ecrã do alarme fecha.
    override fun onCreate(savedInstanceState: Bundle?) {
        sobreBloqueio(veioDeUmaNotificacao(intent))
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        if (veioDeUmaNotificacao(intent)) sobreBloqueio(true)
        super.onNewIntent(intent)
    }

    /// A ação com que o flutter_local_notifications abre a app (toque ou alarme em ecrã inteiro).
    private fun veioDeUmaNotificacao(i: Intent?) = i?.action == "SELECT_NOTIFICATION"

    private fun sobreBloqueio(sim: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(sim)
            setTurnScreenOn(sim)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pt.amparo/alarmes").setMethodCallHandler { chamada, resultado ->
            when (chamada.method) {
                // "Alarmes fiáveis": o flutter_local_notifications pede a permissão de ecrã inteiro mas não diz se já a tem.
                "podeEcraInteiro" -> {
                    val gestor = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    // Até ao Android 13 a permissão vem com a instalação.
                    resultado.success(Build.VERSION.SDK_INT < 34 || gestor.canUseFullScreenIntent())
                }
                "sobreBloqueio" -> {
                    sobreBloqueio(chamada.arguments as? Boolean ?: false)
                    resultado.success(null)
                }
                else -> resultado.notImplemented()
            }
        }
    }
}
