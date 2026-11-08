package __PKG__

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var scene: SceneChannel? = null
    private var services: ServicesChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scene = SceneChannel(applicationContext, flutterEngine)
        services = ServicesChannel(applicationContext, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        scene?.dispose()
        services?.dispose()
        scene = null
        services = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
