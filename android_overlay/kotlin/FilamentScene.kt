package __PKG__

import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.Surface
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.Skybox
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.FilamentInstance
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import java.nio.ByteBuffer
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Draws the chess scene with Google Filament into a Flutter SurfaceTexture.
 *
 * Dart owns all state and sends one float buffer per changed frame (layout documented in
 * lib/scene/board_model.dart, BoardModel.buildFrame). This class only loads the glTF models once, then each frame
 * moves camera and instances and renders.
 */
class FilamentScene(
    private val ctx: Context,
    private val texture: SurfaceTexture,
    private var width: Int,
    private var height: Int,
    private var shadows: Boolean,
    private val listener: Listener,
) : Choreographer.FrameCallback {

    interface Listener {
        fun onProgress(done: Int, total: Int)
        fun onLoaded()
        fun onError(message: String)
    }

    companion object {
        // order of PT in Dart: p, n, b, r, q, k
        private val PIECE_NAMES = arrayOf("pawn", "knight", "bishop", "rook", "queen", "king")
        private val PIECE_POOL = intArrayOf(8, 10, 10, 10, 9, 1)
        private val MARKER_NAMES = arrayOf("marker_sel", "marker_last", "marker_check", "marker_dot", "marker_cap")
        private val MARKER_POOL = intArrayOf(1, 2, 1, 32, 16)
        private const val HEADER = 9
        private const val PIECE_STRIDE = 7
        private const val MARKER_STRIDE = 4
        private const val EXPOSURE = 1.05f
    }

    private val handler = Handler(Looper.getMainLooper())
    private var destroyed = false
    private var loaded = false

    private val engine: Engine
    private val renderer: Renderer
    private val scene: Scene
    private val view: View
    private val camera: Camera
    private val cameraEntity: Int
    private var surface: Surface
    private var swapChain: SwapChain
    private val materials: UbershaderProvider
    private val assetLoader: AssetLoader
    private val resourceLoader: ResourceLoader
    private val sun: Int
    private val rim: Int
    private val ibl: IndirectLight
    private val skybox: Skybox

    // piece slot -> instance, markers kind -> instances
    private val pieceInstances = arrayOfNulls<FilamentInstance>(6 * 2 * 16)
    private val pieceVisible = BooleanArray(6 * 2 * 16)
    private val pieceUsed = BooleanArray(6 * 2 * 16)
    private val markerInstances = Array(MARKER_NAMES.size) { arrayOfNulls<FilamentInstance>(MARKER_POOL[it]) }
    private val markerVisible = Array(MARKER_NAMES.size) { BooleanArray(MARKER_POOL[it]) }
    private val markerUsed = Array(MARKER_NAMES.size) { BooleanArray(MARKER_POOL[it]) }
    private val assets = ArrayList<FilamentAsset>()

    private var frame: FloatArray? = null
    private var dirty = true
    private val matrix = FloatArray(16)

    private val tasks = ArrayList<Pair<String, () -> Unit>>()
    private var taskIndex = 0

    init {
        Gltfio.init()
        engine = Engine.create()
        renderer = engine.createRenderer()
        scene = engine.createScene()
        view = engine.createView()
        cameraEntity = EntityManager.get().create()
        camera = engine.createCamera(cameraEntity)
        camera.setExposure(EXPOSURE)
        view.camera = camera
        view.scene = scene

        texture.setDefaultBufferSize(width, height)
        surface = Surface(texture)
        swapChain = engine.createSwapChain(surface)
        view.viewport = Viewport(0, 0, width, height)

        // background colour 0x15110e (linear) behind the table
        skybox = Skybox.Builder().color(0.0075f, 0.0056f, 0.0044f, 1f).build(engine)
        scene.skybox = skybox

        // soft ambient light, warm (stand-in for the hemisphere light + room environment of the web version)
        ibl = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.46f, 0.44f, 0.40f))
            .intensity(1.0f)
            .build(engine)
        scene.indirectLight = ibl

        // key light: position (-6, 13, 9) looking at the origin, intensity 3.1, colour #fff0dc
        sun = EntityManager.get().create()
        val sd = norm(6f, -13f, -9f)
        val opts = LightManager.ShadowOptions()
        opts.mapSize = 2048
        opts.shadowCascades = 1
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.871f, 0.716f)
            .intensity(3.1f)
            .direction(sd[0], sd[1], sd[2])
            .castShadows(shadows)
            .shadowOptions(opts)
            .build(engine, sun)
        scene.addEntity(sun)

        // rim light: position (8, 6, -9), intensity 0.55, colour #ffd7b0
        rim = EntityManager.get().create()
        val rd = norm(-8f, -6f, 9f)
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.679f, 0.434f)
            .intensity(0.55f)
            .direction(rd[0], rd[1], rd[2])
            .castShadows(false)
            .build(engine, rim)
        scene.addEntity(rim)

        view.isShadowingEnabled = shadows
        configureQuality()

        materials = UbershaderProvider(engine)
        assetLoader = AssetLoader(engine, materials, EntityManager.get())
        resourceLoader = ResourceLoader(engine)

        Choreographer.getInstance().postFrameCallback(this)
    }

    private fun norm(x: Float, y: Float, z: Float): FloatArray {
        val l = sqrt(x * x + y * y + z * z)
        return floatArrayOf(x / l, y / l, z / l)
    }

    private fun configureQuality() {
        val msaa = View.MultiSampleAntiAliasingOptions()
        msaa.enabled = shadows
        msaa.sampleCount = 4
        view.multiSampleAntiAliasingOptions = msaa
        view.antiAliasing = View.AntiAliasing.FXAA
    }

    // ------------------------------------------------------------------ loading
    fun startLoading() {
        tasks.add("table" to { loadStatic("table", castShadows = false) })
        tasks.add("board" to { loadStatic("board", castShadows = false) })
        for (t in PIECE_NAMES.indices) {
            for (c in 0..1) {
                val file = PIECE_NAMES[t] + if (c == 0) "_light" else "_dark"
                tasks.add(file to { loadPieces(file, t, c) })
            }
        }
        for (k in MARKER_NAMES.indices) {
            tasks.add(MARKER_NAMES[k] to { loadMarkers(k) })
        }
        loadNext()
    }

    private fun loadNext() {
        if (destroyed) return
        if (taskIndex >= tasks.size) {
            loaded = true
            dirty = true
            listener.onLoaded()
            return
        }
        val (name, run) = tasks[taskIndex]
        try {
            run()
        } catch (e: Throwable) {
            listener.onError("Could not load $name: $e")
            return
        }
        taskIndex++
        listener.onProgress(taskIndex, tasks.size)
        handler.post { loadNext() } // one model per message keeps the UI responsive
    }

    private fun readModel(name: String): ByteBuffer {
        val bytes = ctx.assets.open("flutter_assets/assets/models/$name.glb").use { it.readBytes() }
        val buf = ByteBuffer.allocateDirect(bytes.size)
        buf.put(bytes)
        buf.rewind()
        return buf
    }

    private fun loadStatic(name: String, castShadows: Boolean) {
        val asset = assetLoader.createAsset(readModel(name)) ?: throw IllegalStateException("bad glTF $name")
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()
        setShadowFlags(asset, castShadows, true)
        scene.addEntities(asset.entities)
        assets.add(asset)
    }

    private fun loadPieces(file: String, type: Int, color: Int) {
        val n = PIECE_POOL[type]
        val inst = arrayOfNulls<FilamentInstance>(n)
        val asset = assetLoader.createInstancedAsset(readModel(file), inst) ?: throw IllegalStateException("bad glTF $file")
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()
        setShadowFlags(asset, true, true)
        val base = (type * 2 + color) * 16
        for (i in 0 until n) pieceInstances[base + i] = inst[i]
        assets.add(asset)
    }

    private fun loadMarkers(kind: Int) {
        val n = MARKER_POOL[kind]
        val inst = arrayOfNulls<FilamentInstance>(n)
        val asset = assetLoader.createInstancedAsset(readModel(MARKER_NAMES[kind]), inst)
            ?: throw IllegalStateException("bad glTF ${MARKER_NAMES[kind]}")
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()
        setShadowFlags(asset, false, false)
        val rm = engine.renderableManager
        for (i in 0 until n) {
            markerInstances[kind][i] = inst[i]
            // draw order like the web version's renderOrder: last < check < selected < targets
            val order = intArrayOf(3, 1, 2, 4, 4)[kind]
            for (e in inst[i]!!.entities) {
                if (rm.hasComponent(e)) rm.setBlendOrderAt(rm.getInstance(e), 0, order)
            }
        }
        assets.add(asset)
    }

    private fun setShadowFlags(asset: FilamentAsset, cast: Boolean, receive: Boolean) {
        val rm = engine.renderableManager
        for (e in asset.renderableEntities) {
            val ri = rm.getInstance(e)
            rm.setCastShadows(ri, cast)
            rm.setReceiveShadows(ri, receive)
        }
    }

    // ------------------------------------------------------------------ public API (main thread)
    fun setFrame(f: FloatArray) {
        frame = f
        dirty = true
    }

    fun setShadows(on: Boolean) {
        shadows = on
        val lm = engine.lightManager
        lm.setShadowCaster(lm.getInstance(sun), on)
        view.isShadowingEnabled = on
        configureQuality()
        dirty = true
    }

    fun resize(w: Int, h: Int) {
        if (destroyed || (w == width && h == height)) return
        width = w
        height = h
        engine.flushAndWait()
        engine.destroySwapChain(swapChain)
        surface.release()
        texture.setDefaultBufferSize(w, h)
        surface = Surface(texture)
        swapChain = engine.createSwapChain(surface)
        view.viewport = Viewport(0, 0, w, h)
        dirty = true
    }

    // ------------------------------------------------------------------ frame
    override fun doFrame(frameTimeNanos: Long) {
        if (destroyed) return
        Choreographer.getInstance().postFrameCallback(this)
        if (!loaded || !dirty) return
        val f = frame ?: return
        dirty = false
        try {
            applyFrame(f)
        } catch (e: Throwable) {
            listener.onError("Bad frame: $e")
            return
        }
        if (renderer.beginFrame(swapChain, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    private fun applyFrame(f: FloatArray) {
        if (f.size < HEADER) return
        val aspect = width.toDouble() / height.toDouble()
        camera.setProjection(f[6].toDouble(), aspect, 0.1, 200.0, Camera.Fov.VERTICAL)
        camera.lookAt(
            f[0].toDouble(), f[1].toDouble(), f[2].toDouble(),
            f[3].toDouble(), f[4].toDouble(), f[5].toDouble(),
            0.0, 1.0, 0.0,
        )
        val tm = engine.transformManager

        java.util.Arrays.fill(pieceUsed, false)
        val pieceCount = f[8].toInt()
        var i = HEADER
        for (p in 0 until pieceCount) {
            val slot = f[i].toInt()
            val inst = if (slot in pieceInstances.indices) pieceInstances[slot] else null
            if (inst != null) {
                trs(f[i + 1], f[i + 2], f[i + 3], f[i + 4], f[i + 5], f[i + 6])
                tm.setTransform(tm.getInstance(inst.root), matrix)
                if (!pieceVisible[slot]) {
                    scene.addEntities(inst.entities)
                    pieceVisible[slot] = true
                }
                pieceUsed[slot] = true
            }
            i += PIECE_STRIDE
        }
        for (s in pieceInstances.indices) {
            if (pieceVisible[s] && !pieceUsed[s]) {
                scene.removeEntities(pieceInstances[s]!!.entities)
                pieceVisible[s] = false
            }
        }

        for (k in markerUsed.indices) java.util.Arrays.fill(markerUsed[k], false)
        val counts = IntArray(MARKER_NAMES.size)
        val markerCount = f[i].toInt()
        i++
        for (m in 0 until markerCount) {
            val kind = f[i].toInt()
            if (kind in markerInstances.indices) {
                val idx = counts[kind]++
                val inst = if (idx < markerInstances[kind].size) markerInstances[kind][idx] else null
                if (inst != null) {
                    trs(f[i + 1], f[i + 2], f[i + 3], 0f, 0f, 1f)
                    tm.setTransform(tm.getInstance(inst.root), matrix)
                    if (!markerVisible[kind][idx]) {
                        scene.addEntities(inst.entities)
                        markerVisible[kind][idx] = true
                    }
                    markerUsed[kind][idx] = true
                }
            }
            i += MARKER_STRIDE
        }
        for (k in markerInstances.indices) {
            for (idx in markerInstances[k].indices) {
                if (markerVisible[k][idx] && !markerUsed[k][idx]) {
                    scene.removeEntities(markerInstances[k][idx]!!.entities)
                    markerVisible[k][idx] = false
                }
            }
        }
    }

    /** Column-major T * Ry * Rz * S, the same maths as three.js Euler (0, rotY, rotZ). */
    private fun trs(x: Float, y: Float, z: Float, rotY: Float, rotZ: Float, scale: Float) {
        val cy = cos(rotY); val sy = sin(rotY)
        val cz = cos(rotZ); val sz = sin(rotZ)
        matrix[0] = cy * cz * scale; matrix[1] = sz * scale; matrix[2] = -sy * cz * scale; matrix[3] = 0f
        matrix[4] = -cy * sz * scale; matrix[5] = cz * scale; matrix[6] = sy * sz * scale; matrix[7] = 0f
        matrix[8] = sy * scale; matrix[9] = 0f; matrix[10] = cy * scale; matrix[11] = 0f
        matrix[12] = x; matrix[13] = y; matrix[14] = z; matrix[15] = 1f
    }

    // ------------------------------------------------------------------ teardown
    fun destroy() {
        if (destroyed) return
        destroyed = true
        Choreographer.getInstance().removeFrameCallback(this)
        handler.removeCallbacksAndMessages(null)
        engine.flushAndWait()
        for (a in assets) assetLoader.destroyAsset(a)
        assets.clear()
        assetLoader.destroy()
        resourceLoader.destroy()
        materials.destroy()
        engine.destroySkybox(skybox)
        engine.destroyIndirectLight(ibl)
        engine.destroyEntity(sun)
        engine.destroyEntity(rim)
        engine.destroyCameraComponent(cameraEntity)
        engine.destroyEntity(cameraEntity)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyRenderer(renderer)
        engine.destroySwapChain(swapChain)
        surface.release()
        engine.destroy()
    }
}
