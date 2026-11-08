package __PKG__

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/** Bridges the Dart scene model to the Filament renderer (see FilamentScene). */
class SceneChannel(private val ctx: Context, private val engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chess3d/scene")
    private var scene: FilamentScene? = null
    private var entry: TextureRegistry.SurfaceTextureEntry? = null

    init {
        channel.setMethodCallHandler(this)
    }

    private fun release() {
        scene?.destroy()
        scene = null
        entry?.release()
        entry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    release()
                    val w = call.argument<Int>("width") ?: 2
                    val h = call.argument<Int>("height") ?: 2
                    val shadows = call.argument<Boolean>("shadows") ?: true
                    val e = engine.renderer.createSurfaceTexture()
                    entry = e
                    scene = FilamentScene(ctx, e.surfaceTexture(), w, h, shadows, object : FilamentScene.Listener {
                        override fun onProgress(done: Int, total: Int) {
                            channel.invokeMethod("progress", mapOf("done" to done, "total" to total))
                        }
                        override fun onLoaded() {
                            channel.invokeMethod("loaded", null)
                        }
                        override fun onError(message: String) {
                            channel.invokeMethod("error", mapOf("message" to message))
                        }
                    })
                    result.success(e.id().toInt())
                    scene?.startLoading()
                }
                "resize" -> {
                    scene?.resize(call.argument<Int>("width") ?: 2, call.argument<Int>("height") ?: 2)
                    result.success(null)
                }
                "setShadows" -> {
                    scene?.setShadows(call.argument<Boolean>("on") ?: true)
                    result.success(null)
                }
                "frame" -> {
                    val f = call.arguments
                    if (f is FloatArray) scene?.setFrame(f)
                    result.success(null)
                }
                "dispose" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("scene", e.toString(), null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        release()
    }
}
