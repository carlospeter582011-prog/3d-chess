import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js'
import { loadModelBuffer, MODEL_FILES } from './modelCache'

export type Color = 'w' | 'b'
export type PType = 'k' | 'q' | 'r' | 'b' | 'n' | 'p'
export type Sq = string // "e4"

const NAMES: Record<PType, string> = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' }

/** One board square == 1.0 world unit. File a is at -x, rank 1 is at +z (white sits on the +z side). */
export const SURFACE_Y = 0.464 // playing surface height of the supplied board model (0.0232 * 20)

export function sqToWorld(sq: Sq, y = SURFACE_Y): THREE.Vector3 {
  const file = sq.charCodeAt(0) - 97
  const rank = sq.charCodeAt(1) - 49
  return new THREE.Vector3(file - 3.5, y, 3.5 - rank)
}
export function worldToSq(x: number, z: number): Sq | null {
  const file = Math.floor(x + 4)
  const rank = Math.floor(4 - z)
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null
  return String.fromCharCode(97 + file) + (rank + 1)
}

interface PieceObj {
  group: THREE.Group
  hit: THREE.Mesh
  color: Color
  type: PType
  square: Sq
  id: number
}

export interface PlacedPiece { square: Sq; color: Color; type: PType }

interface Tween { t: number; dur: number; update: (k: number) => void; done?: () => void; resolve: () => void; delay: number }

const ease = (k: number) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2)

export interface BoardOptions {
  canvas: HTMLCanvasElement
  onTap: (sq: Sq, ground: Sq | null) => void
  quality: 'high' | 'low'
}

export class Board3D {
  readonly renderer: THREE.WebGLRenderer
  readonly scene = new THREE.Scene()
  readonly camera: THREE.PerspectiveCamera
  readonly controls: OrbitControls
  private canvas: HTMLCanvasElement
  private templates = new Map<string, THREE.Object3D>()
  private boardModel: THREE.Object3D | null = null
  private pieces = new Map<Sq, PieceObj>()
  private nextId = 1
  private pieceRoot = new THREE.Group()
  private hitMeshes: THREE.Mesh[] = []
  private modelMeshes: THREE.Mesh[] = []
  private markers = new THREE.Group()
  private labels = new THREE.Group()
  private tweens: Tween[] = []
  private needsRender = true
  private raf = 0
  private lastT = performance.now()
  private light!: THREE.DirectionalLight
  private onTap: (sq: Sq, ground: Sq | null) => void
  private disposed = false
  private lifted: PieceObj | null = null
  private camTween: { t: number; dur: number; from: THREE.Spherical; to: THREE.Spherical; target: THREE.Vector3 } | null = null
  private quality: 'high' | 'low'
  private pointerDown: { x: number; y: number; t: number; multi: boolean } | null = null
  private activePointers = new Set<number>()
  private ro: ResizeObserver
  /** When false, moves are applied instantly (used by tests). */
  animations = true
  private ray = new THREE.Raycaster()
  private plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -SURFACE_Y)

  constructor(opts: BoardOptions) {
    this.canvas = opts.canvas
    this.onTap = opts.onTap
    this.quality = opts.quality
    const low = this.quality === 'low'
    this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: !low, powerPreference: 'high-performance', preserveDrawingBuffer: true })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, low ? 1.25 : 2))
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping
    this.renderer.toneMappingExposure = 1.05
    this.renderer.shadowMap.enabled = !low
    this.renderer.shadowMap.type = THREE.PCFShadowMap

    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 200)
    this.controls = new OrbitControls(this.camera, this.canvas)
    this.setupScene()
    this.setupControls()
    this.setupPointer()
    this.ro = new ResizeObserver(() => this.resize())
    this.ro.observe(this.canvas.parentElement ?? this.canvas)
    this.resize()
    this.resetCamera(false)
    this.loop()
  }

  // ---------------------------------------------------------------- scene
  private setupScene() {
    const s = this.scene
    // soft studio gradient backdrop
    const bg = document.createElement('canvas'); bg.width = 4; bg.height = 256
    const g = bg.getContext('2d')!
    const grad = g.createLinearGradient(0, 0, 0, 256)
    grad.addColorStop(0, '#2c2621'); grad.addColorStop(0.5, '#15110e'); grad.addColorStop(1, '#15110e')
    g.fillStyle = grad; g.fillRect(0, 0, 4, 256)
    const bgTex = new THREE.CanvasTexture(bg); bgTex.colorSpace = THREE.SRGBColorSpace
    s.background = bgTex
    s.fog = new THREE.Fog(0x15110e, 30, 80)

    const pmrem = new THREE.PMREMGenerator(this.renderer)
    s.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture
    s.environmentIntensity = 0.55

    s.add(new THREE.HemisphereLight(0xfff3e2, 0x3a2a1a, 0.45))
    const key = new THREE.DirectionalLight(0xfff0dc, 3.1)
    key.position.set(-6, 13, 9)
    key.castShadow = this.quality === 'high'
    key.shadow.mapSize.set(2048, 2048)
    const c = key.shadow.camera
    c.left = -8; c.right = 8; c.top = 8; c.bottom = -8; c.near = 1; c.far = 40
    key.shadow.bias = -0.0004
    key.shadow.normalBias = 0.03
    key.shadow.radius = 3
    s.add(key); s.add(key.target)
    this.light = key
    const rim = new THREE.DirectionalLight(0xffd7b0, 0.55)
    rim.position.set(8, 6, -9)
    s.add(rim)

    // table
    const tableTex = this.makeTableTexture()
    const table = new THREE.Mesh(
      new THREE.CircleGeometry(90, 64),
      new THREE.MeshStandardMaterial({ map: tableTex, color: 0xb0a090, roughness: 0.95, metalness: 0, envMapIntensity: 0.25 }),
    )
    table.rotation.x = -Math.PI / 2
    table.position.y = -0.002
    table.receiveShadow = true
    s.add(table)

    s.add(this.pieceRoot, this.markers, this.labels)
  }

  private makeTableTexture() {
    const c = document.createElement('canvas'); c.width = c.height = 1024
    const g = c.getContext('2d')!
    const r = g.createRadialGradient(512, 512, 40, 512, 512, 512)
    r.addColorStop(0, '#4a382b'); r.addColorStop(0.12, '#33261c'); r.addColorStop(0.4, '#1d1510'); r.addColorStop(1, '#15110e')
    g.fillStyle = r; g.fillRect(0, 0, 1024, 1024)
    // very fine, low-contrast grain so the surface doesn't look like plastic
    const img = g.getImageData(0, 0, 1024, 1024)
    for (let y = 0; y < 1024; y++) {
      const row = 0
      for (let x = 0; x < 1024; x++) {
        const i = (y * 1024 + x) * 4
        const n = row + (Math.random() - 0.5) * 2
        img.data[i] += n; img.data[i + 1] += n; img.data[i + 2] += n
      }
    }
    g.putImageData(img, 0, 0)
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8
    return t
  }

  private setupControls() {
    const c = this.controls
    c.enableDamping = true
    c.dampingFactor = 0.09
    c.rotateSpeed = 0.7
    c.zoomSpeed = 0.9
    c.panSpeed = 0.8
    c.screenSpacePanning = false      // pan along the table, like sliding your view over it
    c.minDistance = 5
    c.maxDistance = 40
    c.minPolarAngle = 0.02
    c.maxPolarAngle = Math.PI * 0.49  // never go below the table
    c.target.set(0, 0.4, 0)
    c.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN }
    c.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN }
    c.addEventListener('change', () => { this.clampTarget(); this.needsRender = true })
  }

  private clampTarget() {
    const t = this.controls.target
    t.x = THREE.MathUtils.clamp(t.x, -6, 6)
    t.z = THREE.MathUtils.clamp(t.z, -6, 6)
    t.y = THREE.MathUtils.clamp(t.y, 0, 3)
  }

  // ---------------------------------------------------------------- loading
  async load(onProgress: (done: number, total: number) => void): Promise<void> {
    const loader = new GLTFLoader()
    const total = MODEL_FILES.length
    let done = 0
    const parse = (buf: ArrayBuffer) => new Promise<THREE.Object3D>((res, rej) => loader.parse(buf, '', (g) => res(g.scene), rej))
    const jobs = MODEL_FILES.map((name) => async () => {
      const buf = await loadModelBuffer(name, () => {})
      const obj = await parse(buf)
      done++; onProgress(done, total)
      return [name, obj] as const
    })
    // modest parallelism so phones aren't overwhelmed
    const results: (readonly [string, THREE.Object3D])[] = []
    const queue = [...jobs]
    const worker = async () => { for (let j = queue.shift(); j; j = queue.shift()) results.push(await j()) }
    await Promise.all([worker(), worker(), worker(), worker()])
    for (const [name, obj] of results) {
      obj.traverse((o) => {
        const m = o as THREE.Mesh
        if (m.isMesh) {
          m.castShadow = name !== 'board'
          m.receiveShadow = true
          const mat = m.material as THREE.MeshStandardMaterial
          mat.envMapIntensity = name === 'board' ? 0.5 : 0.9
          if (name === 'board') mat.side = THREE.FrontSide
        }
      })
      if (name === 'board') this.boardModel = obj
      else this.templates.set(name, obj)
    }
    if (!this.boardModel) throw new Error('board model missing')
    this.scene.add(this.boardModel)
    this.buildLabels()
    this.needsRender = true
  }

  private buildLabels() {
    const mk = (text: string) => {
      const c = document.createElement('canvas'); c.width = c.height = 128
      const g = c.getContext('2d')!
      g.fillStyle = 'rgba(240,222,190,0.85)'
      g.font = '600 84px system-ui, -apple-system, Segoe UI, sans-serif'
      g.textAlign = 'center'; g.textBaseline = 'middle'
      g.fillText(text, 64, 70)
      const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4
      const m = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.42), new THREE.MeshBasicMaterial({ map: t, transparent: true, depthWrite: false, toneMapped: false }))
      m.rotation.x = -Math.PI / 2
      return m
    }
    for (let i = 0; i < 8; i++) {
      const letter = String.fromCharCode(97 + i)
      const a = mk(letter); a.position.set(i - 3.5, SURFACE_Y + 0.004, 4.3); this.labels.add(a)
      const b = mk(letter); b.position.set(i - 3.5, SURFACE_Y + 0.004, -4.3); b.rotation.z = Math.PI; this.labels.add(b)
      const n1 = mk(String(i + 1)); n1.position.set(-4.3, SURFACE_Y + 0.004, 3.5 - i); this.labels.add(n1)
      const n2 = mk(String(i + 1)); n2.position.set(4.3, SURFACE_Y + 0.004, 3.5 - i); n2.rotation.z = Math.PI; this.labels.add(n2)
    }
  }

  setLabelsVisible(v: boolean) { this.labels.visible = v; this.needsRender = true }

  // ---------------------------------------------------------------- pieces
  private makePiece(color: Color, type: PType, square: Sq): PieceObj {
    const tpl = this.templates.get(`${NAMES[type]}_${color === 'w' ? 'light' : 'dark'}`)
    if (!tpl) throw new Error('missing template ' + NAMES[type])
    const group = new THREE.Group()
    const model = tpl.clone(true)
    group.add(model)
    // Knights face the opponent (the models face +z; white's opponent is on -z)
    if (type === 'n') group.rotation.y = color === 'w' ? Math.PI : 0
    if (type === 'b') group.rotation.y = color === 'w' ? Math.PI : 0
    const height = ({ k: 1.5, q: 1.3, b: 1.1, n: 1.0, r: 0.82, p: 0.74 } as const)[type]
    const hit = new THREE.Mesh(
      new THREE.CylinderGeometry(0.3, 0.3, Math.max(height, 0.9), 10),
      new THREE.MeshBasicMaterial({ visible: false }),
    )
    hit.position.y = Math.max(height, 0.9) / 2
    group.add(hit)
    const p: PieceObj = { group, hit, color, type, square, id: this.nextId++ }
    hit.userData.pieceId = p.id
    model.traverse((o) => {
      const m = o as THREE.Mesh
      if (m.isMesh) { m.userData.pieceId = p.id; this.modelMeshes.push(m) }
    })
    group.position.copy(sqToWorld(square))
    this.pieceRoot.add(group)
    this.hitMeshes.push(hit)
    this.pieces.set(square, p)
    return p
  }

  private removePiece(p: PieceObj) {
    this.pieceRoot.remove(p.group)
    this.hitMeshes = this.hitMeshes.filter((h) => h !== p.hit)
    this.modelMeshes = this.modelMeshes.filter((m) => m.userData.pieceId !== p.id)
    p.hit.geometry.dispose()
    if (this.pieces.get(p.square) === p) this.pieces.delete(p.square)
    if (this.lifted === p) this.lifted = null
  }

  /** Rebuild every piece from a position (new game, undo, resume). */
  setPosition(placed: PlacedPiece[]) {
    this.tweens = []
    this.lifted = null
    for (const p of [...this.pieces.values()]) this.removePiece(p)
    this.pieces.clear()
    for (const pc of placed) this.makePiece(pc.color, pc.type, pc.square)
    this.needsRender = true
  }

  /** What is on the board right now (for tests: compare with the rules engine). */
  snapshot(): PlacedPiece[] {
    return [...this.pieces.values()].map((p) => {
      // read the real world position of the mesh, not just our bookkeeping
      const w = p.group.position
      const sq = worldToSq(w.x, w.z) ?? '??'
      return { square: sq, color: p.color, type: p.type }
    })
  }

  private tween(dur: number, update: (k: number) => void, delay = 0): Promise<void> {
    if (!this.animations) { update(1); this.needsRender = true; return Promise.resolve() }
    return new Promise((resolve) => this.tweens.push({ t: 0, dur, update, resolve, delay }))
  }

  async movePiece(from: Sq, to: Sq, opts: { capture?: Sq; promotion?: PType } = {}): Promise<void> {
    const p = this.pieces.get(from)
    if (!p) throw new Error(`no piece on ${from}`)
    this.unlift()
    const a = sqToWorld(from), b = sqToWorld(to)
    const dist = a.distanceTo(b)
    const jumper = p.type === 'n'
    const arc = jumper ? 0.9 : 0.28
    const dur = Math.min(700, 280 + dist * 70)
    const victim = opts.capture ? this.pieces.get(opts.capture) : undefined
    if (victim) this.pieces.delete(opts.capture!)
    p.square = to
    this.pieces.delete(from)
    // the destination is only claimed at the end so snapshot() shows the final state
    const movePromise = this.tween(dur, (k) => {
      const e = ease(k)
      p.group.position.set(a.x + (b.x - a.x) * e, SURFACE_Y + Math.sin(Math.PI * e) * arc, a.z + (b.z - a.z) * e)
    })
    let victimPromise: Promise<void> = Promise.resolve()
    if (victim) {
      const vp = victim.group.position.clone()
      victimPromise = this.tween(320, (k) => {
        victim.group.position.y = vp.y + k * 0.7
        const s = 1 - k
        victim.group.scale.setScalar(Math.max(0.0001, s))
        victim.group.rotation.z = k * 0.9
      }, dur * 0.6)
    }
    await Promise.all([movePromise, victimPromise])
    p.group.position.copy(b)
    this.pieces.set(to, p)
    if (victim) this.removePiece(victim)
    if (opts.promotion) {
      this.removePiece(p)
      this.makePiece(p.color, opts.promotion, to)
    }
    this.needsRender = true
  }

  // selection feedback -----------------------------------------------------
  lift(sq: Sq) {
    this.unlift()
    const p = this.pieces.get(sq)
    if (!p) return
    p.group.position.y = SURFACE_Y + 0.22
    this.lifted = p
    this.needsRender = true
  }
  unlift() {
    if (this.lifted) { this.lifted.group.position.y = SURFACE_Y; this.lifted = null; this.needsRender = true }
  }

  // markers -----------------------------------------------------------------
  private markerMat = {
    sel: new THREE.MeshBasicMaterial({ color: 0x4fd18b, transparent: true, opacity: 0.55, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }),
    last: new THREE.MeshBasicMaterial({ color: 0xf3c64a, transparent: true, opacity: 0.42, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }),
    dot: new THREE.MeshBasicMaterial({ color: 0x3fa66f, transparent: true, opacity: 0.8, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 }),
    cap: new THREE.MeshBasicMaterial({ color: 0xe5533d, transparent: true, opacity: 0.85, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 }),
  }
  private quad = new THREE.PlaneGeometry(0.98, 0.98)
  private dotGeo = new THREE.CircleGeometry(0.16, 24)
  private ringGeo = new THREE.RingGeometry(0.36, 0.47, 32)

  private addFlat(geo: THREE.BufferGeometry, mat: THREE.Material, sq: Sq, y: number, order: number) {
    const m = new THREE.Mesh(geo, mat)
    m.rotation.x = -Math.PI / 2
    m.position.copy(sqToWorld(sq, SURFACE_Y + y))
    m.renderOrder = order
    this.markers.add(m)
    return m
  }

  setMarkers(opts: { selected?: Sq | null; targets?: { sq: Sq; capture: boolean }[]; last?: [Sq, Sq] | null; check?: Sq | null }) {
    this.markers.clear()
    if (opts.last) { this.addFlat(this.quad, this.markerMat.last, opts.last[0], 0.004, 1); this.addFlat(this.quad, this.markerMat.last, opts.last[1], 0.004, 1) }
    if (opts.check) {
      if (!this.checkTex) this.checkTex = this.makeCheckTexture()
      const mat = new THREE.MeshBasicMaterial({ map: this.checkTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })
      this.addFlat(this.quad, mat, opts.check, 0.006, 2)
    }
    if (opts.selected) this.addFlat(this.quad, this.markerMat.sel, opts.selected, 0.008, 3)
    for (const t of opts.targets ?? []) {
      if (t.capture) this.addFlat(this.ringGeo, this.markerMat.cap, t.sq, 0.012, 4)
      else this.addFlat(this.dotGeo, this.markerMat.dot, t.sq, 0.012, 4)
    }
    this.needsRender = true
  }
  private checkTex: THREE.CanvasTexture | null = null
  private makeCheckTexture() {
    const c = document.createElement('canvas'); c.width = c.height = 128
    const g = c.getContext('2d')!
    const r = g.createRadialGradient(64, 64, 4, 64, 64, 64)
    r.addColorStop(0, 'rgba(255,40,30,0.95)'); r.addColorStop(0.6, 'rgba(230,40,30,0.5)'); r.addColorStop(1, 'rgba(230,40,30,0)')
    g.fillStyle = r; g.fillRect(0, 0, 128, 128)
    return new THREE.CanvasTexture(c)
  }

  // ---------------------------------------------------------------- camera
  private fitDistance() {
    const aspect = this.camera.aspect
    const vfov = THREE.MathUtils.degToRad(this.camera.fov)
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * aspect)
    const need = 12.6 // world width/height we want visible around the board (frame + margin)
    const dH = need / 2 / Math.tan(hfov / 2)
    const dV = (need * 0.82) / 2 / Math.tan(vfov / 2)
    return Math.max(dH, dV)
  }

  /** side: 'w' looks from white's side (+z), 'b' from black's side (-z). */
  resetCamera(animate = true, side: Color = 'w', top = false) {
    const d = this.fitDistance()
    const to = new THREE.Spherical(d, top ? 0.02 : THREE.MathUtils.degToRad(52), side === 'w' ? 0 : Math.PI)
    this.flyTo(to, new THREE.Vector3(0, 0.4, 0), animate)
  }

  flyTo(to: THREE.Spherical, target: THREE.Vector3, animate = true) {
    const from = new THREE.Spherical().setFromVector3(this.camera.position.clone().sub(this.controls.target))
    // shortest way around
    let dTheta = to.theta - from.theta
    dTheta = Math.atan2(Math.sin(dTheta), Math.cos(dTheta))
    const toFixed = new THREE.Spherical(to.radius, to.phi, from.theta + dTheta)
    if (!animate || !this.animations) {
      this.controls.target.copy(target)
      this.camera.position.setFromSpherical(toFixed).add(target)
      this.camera.lookAt(target)
      this.controls.update()
      this.needsRender = true
      return
    }
    this.camTween = { t: 0, dur: 700, from, to: toFixed, target: target.clone() }
  }

  /** Flip the view to the other side of the board. */
  flipView() {
    const cur = new THREE.Spherical().setFromVector3(this.camera.position.clone().sub(this.controls.target))
    const to = new THREE.Spherical(cur.radius, cur.phi, cur.theta + Math.PI)
    this.flyTo(to, this.controls.target.clone())
  }

  viewSide(): Color {
    const v = this.camera.position.clone().sub(this.controls.target)
    return v.z >= 0 ? 'w' : 'b'
  }

  // ---------------------------------------------------------------- input
  private setupPointer() {
    const el = this.canvas
    el.style.touchAction = 'none'
    el.addEventListener('pointerdown', (e) => {
      this.activePointers.add(e.pointerId)
      if (this.activePointers.size === 1) this.pointerDown = { x: e.clientX, y: e.clientY, t: performance.now(), multi: false }
      else if (this.pointerDown) this.pointerDown.multi = true
    })
    const up = (e: PointerEvent) => {
      this.activePointers.delete(e.pointerId)
      const d = this.pointerDown
      if (!d) return
      if (this.activePointers.size === 0) {
        this.pointerDown = null
        if (e.type === 'pointerup' && !d.multi && Math.hypot(e.clientX - d.x, e.clientY - d.y) < 9 && performance.now() - d.t < 600) {
          this.tap(e.clientX, e.clientY)
        }
      }
    }
    el.addEventListener('pointerup', up)
    el.addEventListener('pointercancel', up)
  }

  private tap(cx: number, cy: number) {
    const sq = this.pick(cx, cy)
    if (sq) this.onTap(sq, this.pickGround(cx, cy))
  }

  /** Square under a screen position. */
  pick(cx: number, cy: number): Sq | null {
    const r = this.canvas.getBoundingClientRect()
    const ndc = new THREE.Vector2(((cx - r.left) / r.width) * 2 - 1, -((cy - r.top) / r.height) * 2 + 1)
    this.ray.setFromCamera(ndc, this.camera)
    // 1) the piece you can actually see under the finger, 2) slim hit-volumes for thin parts (cross, ears), 3) the square
    for (const list of [this.modelMeshes, this.hitMeshes]) {
      const hits = this.ray.intersectObjects(list, false)
      if (hits.length) {
        const id = hits[0].object.userData.pieceId
        for (const p of this.pieces.values()) if (p.id === id) return p.square
      }
    }
    const pt = new THREE.Vector3()
    if (this.ray.ray.intersectPlane(this.plane, pt)) return worldToSq(pt.x, pt.z)
    return null
  }

  /** The board square under a screen position, ignoring pieces (what you'd hit if the pieces were see-through). */
  pickGround(cx: number, cy: number): Sq | null {
    const r = this.canvas.getBoundingClientRect()
    const ndc = new THREE.Vector2(((cx - r.left) / r.width) * 2 - 1, -((cy - r.top) / r.height) * 2 + 1)
    this.ray.setFromCamera(ndc, this.camera)
    const pt = new THREE.Vector3()
    return this.ray.ray.intersectPlane(this.plane, pt) ? worldToSq(pt.x, pt.z) : null
  }

  /** Screen position of a square centre (tests). */
  squareToScreen(sq: Sq, h = 0.3): { x: number; y: number } {
    const v = sqToWorld(sq, SURFACE_Y + h).project(this.camera)
    const r = this.canvas.getBoundingClientRect()
    return { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height }
  }

  // ---------------------------------------------------------------- loop
  private resize() {
    const parent = this.canvas.parentElement ?? this.canvas
    const w = Math.max(1, parent.clientWidth), h = Math.max(1, parent.clientHeight)
    this.renderer.setSize(w, h, false)
    this.canvas.style.width = '100%'; this.canvas.style.height = '100%'
    const prevAspect = this.camera.aspect
    this.camera.aspect = w / h
    this.camera.fov = w / h < 0.85 ? 50 : 38 // wider lens on portrait phones so the board stays big
    this.camera.updateProjectionMatrix()
    // keep the whole board visible after rotation / resize
    if (Math.abs(prevAspect - this.camera.aspect) > 0.01 && this.boardModel) {
      const want = this.fitDistance()
      const v = this.camera.position.clone().sub(this.controls.target)
      if (v.length() < want) { v.setLength(want); this.camera.position.copy(this.controls.target).add(v) }
    }
    this.needsRender = true
  }

  requestRender() { this.needsRender = true }

  setQuality(q: 'high' | 'low') {
    this.quality = q
    const low = q === 'low'
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, low ? 1.25 : 2))
    this.renderer.shadowMap.enabled = !low
    this.light.castShadow = !low
    this.scene.traverse((o) => {
      const m = (o as THREE.Mesh).material as THREE.Material | undefined
      if (m) m.needsUpdate = true
    })
    this.resize()
  }

  private loop = () => {
    if (this.disposed) return
    this.raf = requestAnimationFrame(this.loop)
    const now = performance.now()
    const dt = Math.min(0.25, (now - this.lastT) / 1000)
    this.lastT = now
    let animating = false

    if (this.camTween) {
      const c = this.camTween
      c.t += dt * 1000
      const k = ease(Math.min(1, c.t / c.dur))
      const s = new THREE.Spherical(
        c.from.radius + (c.to.radius - c.from.radius) * k,
        c.from.phi + (c.to.phi - c.from.phi) * k,
        c.from.theta + (c.to.theta - c.from.theta) * k,
      )
      this.controls.target.lerp(c.target, 0.2 + 0.8 * k)
      this.camera.position.setFromSpherical(s).add(this.controls.target)
      this.camera.lookAt(this.controls.target)
      if (c.t >= c.dur) this.camTween = null
      animating = true
    }

    if (this.tweens.length) {
      animating = true
      for (const tw of [...this.tweens]) {
        if (tw.delay > 0) { tw.delay -= dt * 1000; continue }
        tw.t += dt * 1000
        const k = Math.min(1, tw.t / tw.dur)
        tw.update(k)
        if (k >= 1) { this.tweens.splice(this.tweens.indexOf(tw), 1); tw.resolve() }
      }
    }

    const changed = this.controls.update() // returns true while damping / dragging
    if (changed || animating || this.needsRender) {
      this.needsRender = false
      this.renderer.render(this.scene, this.camera)
    }
  }

  dispose() {
    this.disposed = true
    cancelAnimationFrame(this.raf)
    this.ro.disconnect()
    this.controls.dispose()
    this.renderer.dispose()
  }
}
