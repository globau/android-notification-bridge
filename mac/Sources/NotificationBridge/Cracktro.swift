import AppKit
import QuartzCore

/// mid-90s style cracktro hidden behind the about window's icon: a 320x200, 256 colour screen cycling effects
/// under a bouncing logo and sine scroller, with a chiptune
@MainActor
final class CracktroView: NSView {
    static let size = NSSize(width: Screen.width * 2, height: Screen.height * 2)

    var onExit: (() -> Void)?
    private let screen = Screen()
    private let music = Chiptune()
    private var link: CADisplayLink?
    private var startTime = 0.0

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        layer = CALayer()
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start() {
        startTime = CACurrentMediaTime()
        music.start()
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        music.stop()
    }

    @objc private func step(_ link: CADisplayLink) {
        layer?.contents = screen.render(time: CACurrentMediaTime() - startTime, music: music)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onExit?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onExit?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct RGB {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        (self.r, self.g, self.b) = (r, g, b)
    }

    func scaled(_ factor: Double) -> RGB {
        RGB(r * factor, g * factor, b * factor)
    }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }

    static let black = RGB(0, 0, 0)
    static let white = RGB(255, 255, 255)
}

/// indexed frame buffer; palette slots below 128 belong to the current effect, the rest to the overlays
@MainActor
private final class Screen {
    static let width = 320
    static let height = 200

    private static let flashDuration = 0.5
    private static let logoSlot = 128
    private static let scrollerSlot = 144
    private static let vuSlot = 160
    private static let vuColours = 8
    private static let shadowSlot = 255

    private static let logo = "NOTIFICATION BRIDGE"
    private static var scrollText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return """
            NOTIFICATION BRIDGE V\(version) ...   YES! ANOTHER FINE RELEASE FROM GLOB ...   \
            YOUR PHONE'S NOTIFICATIONS, BEAMED TO YOUR MAC WHILE IT SITS FACE DOWN ON THE DESK ...   \
            X25519 + HKDF + AES-256-GCM: NO CLOUD, NO ACCOUNTS, NO NONSENSE ...   \
            CODE: GLOB  -  MUSIC: SYNTHESISED IN REAL TIME, NO SAMPLES WERE HARMED ...   \
            GREETZ FLY OUT TO: KOTLIN, SWIFTUI, BONJOUR, ADB, OPENSSL AND EVERYONE WITH THEIR PHONE ON SILENT ...   \
            NO GREETZ TO WHATSAPP BACKUP NOTIFICATIONS ...   CLICK OR PRESS ESC TO EXIT ...   TEXT RESTARTS ...
            """
    }

    private var pixels = [UInt8](repeating: 0, count: width * height)
    private var palette = [RGB](repeating: .black, count: 256)
    private var output = [UInt32](repeating: 0, count: width * height)
    private let scroller = scrollText.map(Font8x8.glyph)
    private let texture: (pixels: [UInt8], palette: [RGB])
    private let stars: [(x: Double, y: Double, z: Double)]
    private var vu = [Double](repeating: 0, count: Chiptune.channels)
    private var lastTime = 0.0

    init() {
        texture = Self.iconTexture()
        stars = (0..<200).map { _ in (.random(in: -1...1), .random(in: -1...1), .random(in: 0...1)) }
        for row in 0..<16 {
            let amount = Double(row % 8) / 7
            palette[Self.scrollerSlot + row] = row < 8
                ? RGB(40, 80, 200).mixed(with: RGB(240, 250, 255), amount)
                : RGB(120, 60, 20).mixed(with: RGB(255, 200, 120), amount)
        }
        for i in 0..<Self.vuColours {
            palette[Self.vuSlot + i] = RGB(40, 230, 60).mixed(with: RGB(255, 40, 30), Double(i) / Double(Self.vuColours - 1))
        }
    }

    /// effects change with each section of the music, flashing on its first beat
    func render(time t: Double, music: Chiptune) -> CGImage? {
        let dt = max(0, t - lastTime)
        lastTime = t
        let section = Int(music.time / music.sectionDuration)
        let local = music.time - Double(section) * music.sectionDuration
        switch section % 7 {
        case 0: rotozoom(local)
        case 1: glenz(local)
        case 2: plasma(local)
        case 3: dots(local)
        case 4: starfield(local)
        case 5: circles(local, beat: local / (music.sectionDuration / 16))
        default: cube(local)
        }
        drawLogo(t)
        drawScroller(t)
        drawVU(music.levels, dt)
        let flash = section > 0 ? max(0, 1 - local / Self.flashDuration) : 0
        return image(fade: min(1, t), flash: flash)
    }

    // MARK: effects

    private func rotozoom(_ t: Double) {
        for i in 0..<texture.palette.count {
            palette[i] = texture.palette[i]
        }
        let scale = 0.9 + 0.6 * sin(t * 0.8)
        let (sa, ca) = (sin(t * 0.5) * scale, cos(t * 0.5) * scale)
        let (u0, v0) = (t * 12, t * 7)
        texture.pixels.withUnsafeBufferPointer { texels in
            pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<Self.height {
                    let dy = Double(y - Self.height / 2)
                    var u = -Double(Self.width / 2) * ca - dy * sa + u0
                    var v = -Double(Self.width / 2) * sa + dy * ca + v0
                    for x in 0..<Self.width {
                        let tu = Int(u.rounded(.down)) & 63
                        let tv = Int(v.rounded(.down)) & 63
                        out[y * Self.width + x] = texels[tv * 64 + tu]
                        u += ca
                        v += sa
                    }
                }
            }
        }
    }

    private func plasma(_ t: Double) {
        let shift = Int(t * 50)
        for i in 0..<128 {
            let a = Double((i + shift) & 127) * .pi / 64
            palette[i] = RGB(128 + 127 * sin(a), 128 + 127 * sin(a + 2.1), 128 + 127 * sin(a + 4.2)).scaled(0.9)
        }
        let columns = (0..<Self.width).map { sin(Double($0) * 0.045 + t) }
        let rows = (0..<Self.height).map { sin(Double($0) * 0.035 - t * 1.3) }
        let diagonals = (0..<Self.width + Self.height).map { sin(Double($0) * 0.025 + t * 0.7) }
        let (cx, cy) = (160 + sin(t * 0.6) * 90, 100 + cos(t * 0.8) * 60)
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<Self.height {
                let dy = Double(y) - cy
                for x in 0..<Self.width {
                    let dx = Double(x) - cx
                    let v = columns[x] + rows[y] + diagonals[x + y] + sin((dx * dx + dy * dy).squareRoot() * 0.06 - t * 2)
                    out[y * Self.width + x] = UInt8(Int((v + 4) * 16) & 127)
                }
            }
        }
    }

    private func starfield(_ t: Double) {
        let barColours = [
            RGB(255, 40, 40), RGB(255, 150, 20), RGB(255, 240, 40), RGB(40, 220, 60), RGB(40, 120, 255), RGB(180, 60, 255),
        ]
        palette[0] = .black
        for i in 1..<16 {
            palette[i] = RGB.white.scaled(Double(i) / 15)
        }
        for (bar, colour) in barColours.enumerated() {
            for shade in 0..<16 {
                let light = sin(.pi * (Double(shade) + 0.5) / 16)
                palette[16 + bar * 16 + shade] = colour.scaled(light).mixed(with: .white, pow(light, 8) * 0.6)
            }
        }
        pixels.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }

        // bars further back are drawn first so the nearer ones pass over them
        let phases = barColours.indices.map { t * 1.8 - Double($0) * 0.35 }
        for bar in barColours.indices.sorted(by: { cos(phases[$0]) < cos(phases[$1]) }) {
            let top = 92 + Int(sin(phases[bar]) * 70)
            for shade in 0..<16 where (0..<Self.height).contains(top + shade) {
                let start = (top + shade) * Self.width
                pixels.replaceSubrange(start..<start + Self.width, with: repeatElement(UInt8(16 + bar * 16 + shade), count: Self.width))
            }
        }

        for star in stars {
            let z = 1 - (star.z + t * 0.25).truncatingRemainder(dividingBy: 1)
            guard z > 0.05 else { continue }
            let x = 160 + Int(star.x / z * 100)
            let y = 100 + Int(star.y / z * 100)
            let colour = UInt8(15 - Int(z * 14))
            let size = z < 0.3 ? 2 : 1
            for py in y..<y + size {
                for px in x..<x + size {
                    put(px, py, colour)
                }
            }
        }
    }

    private static let cubeVertices: [(Double, Double, Double)] = (0..<8).map {
        ($0 & 1 != 0 ? 1 : -1, $0 & 2 != 0 ? 1 : -1, $0 & 4 != 0 ? 1 : -1)
    }
    /// opposite faces share a colour
    private static let cubeFaces: [(vertices: [Int], normal: (Double, Double, Double))] = [
        ([1, 3, 7, 5], (1, 0, 0)), ([0, 2, 6, 4], (-1, 0, 0)),
        ([2, 3, 7, 6], (0, 1, 0)), ([0, 1, 5, 4], (0, -1, 0)),
        ([4, 5, 7, 6], (0, 0, 1)), ([0, 1, 3, 2], (0, 0, -1)),
    ]

    private func cube(_ t: Double) {
        let hues = [RGB(40, 140, 255), RGB(255, 60, 150), RGB(255, 200, 40)]
        for (hue, colour) in hues.enumerated() {
            for shade in 0..<32 {
                palette[hue * 32 + shade] = colour.scaled(Double(shade) / 31)
            }
        }
        for i in 0..<32 {
            palette[96 + i] = RGB(60, 0, 90).mixed(with: RGB(0, 0, 12), Double(i) / 31)
        }
        for y in 0..<Self.height {
            let start = y * Self.width
            pixels.replaceSubrange(start..<start + Self.width, with: repeatElement(UInt8(96 + y * 32 / Self.height), count: Self.width))
        }

        func rotate(_ p: (Double, Double, Double)) -> (Double, Double, Double) {
            Self.rotate(p, t * 0.9, t * 0.7, t * 0.4)
        }
        let distance = 5 + sin(t * 0.5) * 1.2
        let (cx, cy) = (160 + sin(t * 0.7) * 60, 96 + sin(t * 1.3) * 12)
        let vertices = Self.cubeVertices.map { vertex in
            let (x, y, z) = rotate(vertex)
            return (x: x, y: y, z: z + distance)
        }
        let light = (x: -0.4, y: -0.6, z: -1.0)
        let lightLength = (light.x * light.x + light.y * light.y + light.z * light.z).squareRoot()

        for (index, face) in Self.cubeFaces.enumerated() {
            let corners = face.vertices.map { vertices[$0] }
            let centre = corners.reduce((x: 0.0, y: 0.0, z: 0.0)) { ($0.x + $1.x / 4, $0.y + $1.y / 4, $0.z + $1.z / 4) }
            let normal = rotate(face.normal)
            guard normal.0 * centre.x + normal.1 * centre.y + normal.2 * centre.z < 0 else { continue }
            let brightness = max(0, (normal.0 * light.x + normal.1 * light.y + normal.2 * light.z) / lightLength)
            let colour = UInt8(index / 2 * 32 + 5 + Int(brightness * 26))
            fillPolygon(corners.map { (cx + $0.x * 170 / $0.z, cy + $0.y * 170 / $0.z) }, colour)
        }
    }

    private static func rotate(_ p: (Double, Double, Double), _ ax: Double, _ ay: Double, _ az: Double) -> (Double, Double, Double) {
        var (x, y, z) = p
        (y, z) = (y * cos(ax) - z * sin(ax), y * sin(ax) + z * cos(ax))
        (x, z) = (x * cos(ay) + z * sin(ay), -x * sin(ay) + z * cos(ay))
        (x, y) = (x * cos(az) - y * sin(az), x * sin(az) + y * cos(az))
        return (x, y, z)
    }

    /// a cube with a pyramid raised on each face; its triangles alternate between two glass colours
    private static let glenzVertices = cubeVertices + cubeFaces.map { ($0.normal.0 * 1.5, $0.normal.1 * 1.5, $0.normal.2 * 1.5) }
    private static let glenzTriangles: [(a: Int, b: Int, c: Int, glass: Int)] = cubeFaces.indices.flatMap { face in
        let ring = cubeFaces[face].vertices
        return (0..<4).map { (8 + face, ring[$0], ring[($0 + 1) % 4], ($0 + face) % 2) }
    }

    /// second reality's glenz vectors: translucent faces in their own bitplanes over a checkerboard; index bits
    /// 0-1 are the floor, 2-3 the glass seen through the object, 4-6 the shaded glass facing the viewer
    private func glenz(_ t: Double) {
        let floors = [RGB(10, 10, 30), RGB(190, 190, 215), RGB(50, 50, 110)]
        let glass = [RGB(40, 110, 255), RGB(255, 255, 255)]
        for index in 0..<112 {
            let (background, back, front) = (index & 3, index >> 2 & 3, index >> 4)
            var colour = floors[min(background, 2)]
            if back > 0 {
                colour = colour.mixed(with: glass[min(back, 2) - 1].scaled(0.6), 0.4)
            }
            if front > 0 {
                colour = colour.mixed(with: glass[(front - 1) / 3].scaled(0.55 + Double((front - 1) % 3) * 0.225), 0.6)
            }
            palette[index] = colour
        }

        let (horizon, fov, floorY) = (70, 170.0, 2.0)
        let (sa, ca) = (sin(t * 0.3), cos(t * 0.3))
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<Self.height {
                let z = y > horizon ? floorY * fov / Double(y - horizon) : .infinity
                for x in 0..<Self.width {
                    guard z < 30 else {
                        out[y * Self.width + x] = 0
                        continue
                    }
                    let wx = Double(x - Self.width / 2) * z / fov
                    let u = Int((wx * ca - z * sa).rounded(.down))
                    let v = Int((wx * sa + z * ca + t * 1.5).rounded(.down))
                    out[y * Self.width + x] = UInt8(1 + (u + v) & 1)
                }
            }
        }

        let height = abs(sin(t * 2.4))
        let squash = max(0, 1 - height * 6)
        let (stretch, flatten) = (1 + 0.15 * squash, 1 - 0.3 * squash)
        let size = 0.75
        let centre = (x: sin(t * 0.5) * 1.5, y: floorY - 1.5 * size * flatten - height * 1.3, z: 6.5)
        let points = Self.glenzVertices.map { vertex in
            let (x, y, z) = Self.rotate(vertex, t * 0.8, t * 1.1, 0)
            return (x: x * size * stretch + centre.x, y: y * size * flatten + centre.y, z: z * size * stretch + centre.z)
        }
        let light = (x: -0.4, y: -0.7, z: -1.0)
        let lightLength = (light.x * light.x + light.y * light.y + light.z * light.z).squareRoot()
        for triangle in Self.glenzTriangles {
            let (a, b, c) = (points[triangle.a], points[triangle.b], points[triangle.c])
            let (ux, uy, uz) = (b.x - a.x, b.y - a.y, b.z - a.z)
            let (vx, vy, vz) = (c.x - a.x, c.y - a.y, c.z - a.z)
            var normal = (x: uy * vz - uz * vy, y: uz * vx - ux * vz, z: ux * vy - uy * vx)
            let middle = (x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3, z: (a.z + b.z + c.z) / 3)
            if normal.x * (middle.x - centre.x) + normal.y * (middle.y - centre.y) + normal.z * (middle.z - centre.z) < 0 {
                normal = (-normal.x, -normal.y, -normal.z)
            }
            let corners = [a, b, c].map { (Double(Self.width / 2) + $0.x * fov / $0.z, Double(horizon) + $0.y * fov / $0.z) }
            if normal.x * middle.x + normal.y * middle.y + normal.z * middle.z < 0 {
                let length = (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot()
                let brightness = max(0, (normal.x * light.x + normal.y * light.y + normal.z * light.z) / length / lightLength)
                let shade = min(2, Int(brightness * 3))
                fillPolygon(corners, UInt8((1 + triangle.glass * 3 + shade) << 4), mask: 0x70)
            } else {
                fillPolygon(corners, UInt8((1 + triangle.glass) << 2), mask: 0x0C)
            }
        }
    }

    /// sunflower spiral, so the dots spread evenly over a disc
    private static let dotPositions: [(x: Double, z: Double, radius: Double)] = (0..<512).map { i in
        let radius = (Double(i) / 512).squareRoot() * 3
        let angle = Double(i) * 2.39996
        return (radius * cos(angle), radius * sin(angle), radius)
    }

    /// second reality's dots: a rippling sheet that spins and bounces, shadowed on the floor
    private func dots(_ t: Double) {
        let (horizon, fov, floorY) = (80, 170.0, 1.5)
        let floorSlots = 31
        let (shadowSlot, dotSlot) = (32, 33)
        palette[0] = .black
        for i in 0..<floorSlots {
            palette[1 + i] = RGB(10, 0, 30).mixed(with: RGB(40, 30, 120), Double(i) / Double(floorSlots - 1))
        }
        palette[shadowSlot] = RGB(4, 0, 12)
        for i in 0..<32 {
            palette[dotSlot + i] = RGB(0, 60, 120).mixed(with: RGB(200, 255, 255), Double(i) / 31)
        }
        for y in 0..<Self.height {
            let slot = y > horizon ? 1 + (y - horizon) * (floorSlots - 1) / (Self.height - 1 - horizon) : 0
            let start = y * Self.width
            pixels.replaceSubrange(start..<start + Self.width, with: repeatElement(UInt8(slot), count: Self.width))
        }

        let height = abs(sin(t * 1.7)) * 2
        let (sa, ca) = (sin(t * 0.6), cos(t * 0.6))
        // tilted towards the viewer so the sheet is seen from above
        let tilt = 0.3 + sin(t * 0.4) * 0.15
        let (st, ct) = (sin(tilt), cos(tilt))
        let positions = Self.dotPositions.map { dot in
            let wave = sin(dot.radius * 2.5 - t * 5) * 0.25
            let (x, z) = (dot.x * ca - dot.z * sa, dot.x * sa + dot.z * ca)
            let (y, tz) = (wave * ct - z * st, wave * st + z * ct)
            return (x: x, y: floorY - 0.4 - height + y, z: tz + 7)
        }
        func project(_ x: Double, _ y: Double, _ z: Double) -> (Int, Int) {
            (Self.width / 2 + Int(x * fov / z), horizon + Int(y * fov / z))
        }
        for dot in positions {
            let (x, y) = project(dot.x, floorY, dot.z)
            put(x, y, UInt8(shadowSlot))
            put(x + 1, y, UInt8(shadowSlot))
        }
        for dot in positions {
            let (x, y) = project(dot.x, dot.y, dot.z)
            let colour = UInt8(dotSlot + max(0, min(31, Int((10 - dot.z) / 5 * 31))))
            let size = dot.z < 7 ? 2 : 1
            for py in y..<y + size {
                for px in x..<x + size {
                    put(px, py, colour)
                }
            }
        }
    }

    /// ring number at each offset from a centre, covering any centre on screen
    private static let rings: [UInt8] = (0..<width * 2 * height * 2).map { i in
        let (x, y) = (i % (width * 2) - width, i / (width * 2) - height)
        return UInt8(Int(Double(x * x + y * y).squareRoot()) / 6 & 255)
    }

    /// second reality's interference circles: two ring sets as separate bits, white where they overlap, recoloured
    /// on every beat
    private func circles(_ t: Double, beat: Double) {
        let hue = Double(Int(beat)) * 0.37
        let pulse = 0.55 + 0.45 * (1 - (beat - beat.rounded(.down)))
        palette[0] = RGB(6, 0, 16)
        palette[1] = Self.rainbow(hue).scaled(pulse)
        palette[2] = Self.rainbow(hue + 0.5).scaled(pulse)
        palette[3] = RGB.white.scaled(pulse)

        let centres = [
            (160 + sin(t * 0.7) * 120, 100 + cos(t * 0.9) * 80),
            (160 + sin(t * 1.1 + 2) * 120, 100 + cos(t * 0.6 + 1) * 80),
        ]
        let offsets = centres.map { (Self.width - Int($0.0)) + (Self.height - Int($0.1)) * Self.width * 2 }
        Self.rings.withUnsafeBufferPointer { rings in
            pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<Self.height {
                    for x in 0..<Self.width {
                        let position = x + y * Self.width * 2
                        out[y * Self.width + x] = rings[position + offsets[0]] & 1 | (rings[position + offsets[1]] & 1) << 1
                    }
                }
            }
        }
    }

    // MARK: overlays

    private func drawLogo(_ t: Double) {
        for row in 0..<16 {
            let hue = (Double(row) / 32 + t * 0.3).truncatingRemainder(dividingBy: 1)
            palette[Self.logoSlot + row] = Self.rainbow(hue)
        }
        let top = 22 - Int(abs(sin(t * 2.6)) * 16)
        let left = (Self.width - Self.logo.count * 16) / 2
        for (slot, offset) in [(Self.shadowSlot, 2), (nil, 0)] {
            for row in 0..<16 {
                let wobble = Int(sin(t * 5 + Double(row) * 0.5) * 3)
                for (index, character) in Self.logo.enumerated() {
                    let glyph = Font8x8.glyph(character)
                    for column in 0..<16 where Font8x8.pixel(glyph, x: column / 2, y: row / 2) {
                        put(left + index * 16 + column + wobble + offset, top + row + offset, UInt8(slot ?? Self.logoSlot + row))
                    }
                }
            }
        }
    }

    private func drawScroller(_ t: Double) {
        let textWidth = scroller.count * 16
        let position = Int(t * 100) % (textWidth + Self.width) - Self.width
        for x in 0..<Self.width {
            let textX = x + position
            guard textX >= 0 && textX < textWidth else { continue }
            let glyph = scroller[textX / 16]
            let top = 146 + Int(sin(t * 2.5 + Double(x) * 0.025) * 14)
            for row in 0..<16 where Font8x8.pixel(glyph, x: textX % 16 / 2, y: row / 2) {
                put(x + 2, top + row + 2, UInt8(Self.shadowSlot))
            }
            for row in 0..<16 where Font8x8.pixel(glyph, x: textX % 16 / 2, y: row / 2) {
                put(x, top + row, UInt8(Self.scrollerSlot + row))
            }
        }
    }

    /// lead and arpeggio on the left edge, bass and drums on the right
    private func drawVU(_ levels: UnsafePointer<Float>, _ dt: Double) {
        let segments = 22
        let columns = [4, 14, Self.width - 22, Self.width - 12]
        for channel in 0..<Chiptune.channels {
            vu[channel] = max(Double(levels[channel]), vu[channel] - dt * 1.5)
            let lit = Int(vu[channel] * Double(segments))
            for segment in 0..<lit {
                let colour = UInt8(Self.vuSlot + segment * Self.vuColours / segments)
                for y in 0..<3 {
                    for x in 0..<8 {
                        put(columns[channel] + x, 128 - segment * 4 - y, colour)
                    }
                }
            }
        }
    }

    // MARK: drawing

    private func put(_ x: Int, _ y: Int, _ colour: UInt8) {
        guard x >= 0 && x < Self.width && y >= 0 && y < Self.height else { return }
        pixels[y * Self.width + x] = colour
    }

    /// only the bits in mask are replaced, so glenz faces can share pixels
    private func fillPolygon(_ points: [(x: Double, y: Double)], _ colour: UInt8, mask: UInt8 = 0xFF) {
        let top = max(0, Int(points.map(\.y).min()!.rounded(.up)))
        let bottom = min(Self.height - 1, Int(points.map(\.y).max()!.rounded(.down)))
        guard top <= bottom else { return }
        for y in top...bottom {
            let scan = Double(y)
            var crossings: [Double] = []
            for (a, b) in zip(points, points.dropFirst() + [points[0]]) where (a.y <= scan) != (b.y <= scan) {
                crossings.append(a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x))
            }
            guard let lo = crossings.min(), let hi = crossings.max() else { continue }
            let start = max(0, Int(lo.rounded()))
            let end = min(Self.width, Int(hi.rounded()))
            guard start < end else { continue }
            for x in y * Self.width + start..<y * Self.width + end {
                pixels[x] = pixels[x] & ~mask | colour
            }
        }
    }

    private func image(fade: Double, flash: Double) -> CGImage? {
        let colours: [UInt32] = palette.map { colour in
            let c = colour.mixed(with: .white, flash).scaled(fade)
            func channel(_ value: Double) -> UInt32 { UInt32(max(0, min(255, value))) }
            return channel(c.r) << 24 | channel(c.g) << 16 | channel(c.b) << 8 | 0xFF
        }
        for i in 0..<pixels.count {
            output[i] = colours[Int(pixels[i])].bigEndian
        }
        guard let provider = CGDataProvider(data: output.withUnsafeBytes { Data($0) } as CFData) else { return nil }
        return CGImage(
            width: Self.width, height: Self.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Self.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func rainbow(_ hue: Double) -> RGB {
        let a = hue * 2 * .pi
        return RGB(128 + 127 * sin(a), 128 + 127 * sin(a + 2.1), 128 + 127 * sin(a + 4.2))
    }

    /// the app icon at 64x64 over a dark background, reduced to at most 128 colours
    private static func iconTexture() -> (pixels: [UInt8], palette: [RGB]) {
        let size = 64
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            context.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rect = NSRect(x: 0, y: 0, width: size, height: size)
            if let icon = NSApp.applicationIconImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                context.draw(icon, in: rect)
            }
        }

        let colours = (0..<size * size).map { RGB(Double(rgba[$0 * 4]), Double(rgba[$0 * 4 + 1]), Double(rgba[$0 * 4 + 2])) }
        func bucket(_ c: RGB) -> Int { (Int(c.r) >> 4) << 8 | (Int(c.g) >> 4) << 4 | Int(c.b) >> 4 }
        var counts: [Int: (count: Int, sum: RGB)] = [:]
        for colour in colours {
            let entry = counts[bucket(colour), default: (0, .black)]
            counts[bucket(colour)] = (entry.count + 1, RGB(entry.sum.r + colour.r, entry.sum.g + colour.g, entry.sum.b + colour.b))
        }
        let popular = counts.sorted { $0.value.count > $1.value.count }.prefix(128)
        let palette = popular.map { $0.value.sum.scaled(1 / Double($0.value.count)) }
        let pixels = colours.map { colour in
            UInt8(palette.indices.min { distance(palette[$0], colour) < distance(palette[$1], colour) }!)
        }
        return (pixels, palette)
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
    }
}
