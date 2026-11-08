package __PKG__

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Key-value storage (SharedPreferences) and sound effects (SoundPool) for the Dart side. */
class ServicesChannel(private val ctx: Context, engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chess3d/services")
    private val prefs = ctx.getSharedPreferences("chess3d", Context.MODE_PRIVATE)
    private val sounds = HashMap<String, Int>()
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "storeGetAll" -> {
                    val out = HashMap<String, String>()
                    for ((k, v) in prefs.all) if (v is String) out[k] = v
                    result.success(out)
                }
                "storeSet" -> {
                    prefs.edit().putString(call.argument<String>("key"), call.argument<String>("value")).apply()
                    result.success(null)
                }
                "storeRemove" -> {
                    prefs.edit().remove(call.argument<String>("key")).apply()
                    result.success(null)
                }
                "sfxLoad" -> {
                    val name = call.argument<String>("name") ?: throw IllegalArgumentException("name")
                    val wav = call.argument<ByteArray>("wav") ?: throw IllegalArgumentException("wav")
                    val f = File(ctx.cacheDir, "sfx_$name.wav")
                    f.writeBytes(wav)
                    sounds[name] = pool.load(f.absolutePath, 1)
                    result.success(null)
                }
                "sfxPlay" -> {
                    val id = sounds[call.argument<String>("name")]
                    if (id != null) pool.play(id, 1f, 1f, 1, 0, 1f)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("services", e.message, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pool.release()
    }
}
