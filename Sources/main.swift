import AppKit
import Foundation

// MARK: - Claude Names (persistent, hashed, short)

enum ClaudeNamer {
    // One name per starting letter for easy visual distinction
    private static let names = [
        "ace", "bay", "cor", "dax", "elm", "fox", "gem", "hex",
        "ion", "jax", "kai", "lux", "max", "neo", "orb", "pax",
        "qor", "ray", "sol", "tau", "uno", "vex", "wex", "xen",
        "yew", "zed",
    ]

    private static var cache: [String: String] = [:]
    private static var usedLetters: Set<Character> = []

    static func name(for tty: String) -> String {
        if let cached = cache[tty] { return cached }

        // djb2 hash of tty
        var h: UInt64 = 5381
        for byte in tty.utf8 {
            h = ((h &<< 5) &+ h) &+ UInt64(byte)
        }

        // Pick a name, skip names whose first letter is already taken
        let startIdx = Int(h % UInt64(names.count))
        var name = names[startIdx]
        var offset = 0
        while usedLetters.contains(name.first!) {
            offset += 1
            if offset >= names.count { name = "\(names[startIdx])\(tty.suffix(1))"; break }
            name = names[(startIdx + offset) % names.count]
        }

        cache[tty] = name
        usedLetters.insert(name.first!)
        return name
    }

    static func prune(activeTTYs: Set<String>) {
        let stale = cache.keys.filter { !activeTTYs.contains($0) }
        for key in stale {
            if let name = cache[key] { usedLetters.remove(name.first!) }
            cache.removeValue(forKey: key)
        }
    }
}

// MARK: - Claude Session

enum SessionState {
    case idle
    case working
    case done  // was working, now idle = hand raised
}

struct ClaudeSession: Hashable {
    let pid: Int32
    let tty: String
    let isInteractive: Bool
    let commandArgs: String
    let smoothedCpu: Double
    let state: SessionState

    var displayName: String {
        guard isInteractive else { return "sub" }
        return ClaudeNamer.name(for: tty)
    }

    var tooltipText: String {
        let stateStr: String
        switch state {
        case .idle: stateStr = "Idle"
        case .working: stateStr = "Working"
        case .done: stateStr = "Done!"
        }
        let cpu = String(format: "%.1f%%", smoothedCpu)
        let name = displayName
        return "\(name) - \(stateStr) (\(cpu) CPU)\nPID: \(pid) [\(tty)]"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(pid) }
    static func == (lhs: ClaudeSession, rhs: ClaudeSession) -> Bool { lhs.pid == rhs.pid }
}

// MARK: - Session Detector

class SessionDetector {
    private var cpuHistory: [Int32: [Double]] = [:]
    private var wasWorking: Set<Int32> = []  // Track "done" state
    private var workingTickCount: [Int32: Int] = [:]  // Hysteresis: must be high CPU for N ticks to count

    func detectSessions() -> [ClaudeSession] {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-eo", "pid,tty,%cpu,command"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var sessions: [ClaudeSession] = []
        var seen = Set<Int32>()

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            guard let pid = Int32(parts[0]) else { continue }
            guard !seen.contains(pid) else { continue }

            let cmd = String(parts[3])
            let binary = cmd.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            let binaryName = (binary as NSString).lastPathComponent
            guard binaryName == "claude" else { continue }
            if cmd.contains("ClaudeMonitor") { continue }

            let tty = String(parts[1])

            // Only show interactive sessions (with a real TTY)
            guard tty != "??" else { continue }

            // Skip -p (piped/programmatic) subagents
            let isPiped = cmd.contains(" -p ") || cmd.contains(" --print")
            guard !isPiped else { continue }

            seen.insert(pid)

            let cpu = Double(parts[2]) ?? 0.0
            var hist = cpuHistory[pid] ?? []
            hist.append(cpu)
            if hist.count > 3 { hist.removeFirst() }
            cpuHistory[pid] = hist
            let smoothed = hist.reduce(0, +) / Double(hist.count)

            let cpuHigh = smoothed > 5.0

            // Hysteresis: need 2+ consecutive high-CPU polls to enter "working"
            // This prevents brief spikes (like clicking the terminal) from triggering animation
            if cpuHigh {
                workingTickCount[pid] = (workingTickCount[pid] ?? 0) + 1
            } else {
                workingTickCount[pid] = 0
            }
            let isWorking = (workingTickCount[pid] ?? 0) >= 2

            let state: SessionState
            if isWorking {
                wasWorking.insert(pid)
                state = .working
            } else if wasWorking.contains(pid) {
                // Was working, now stopped = needs your input
                state = .done
            } else {
                state = .idle
            }

            sessions.append(ClaudeSession(
                pid: pid, tty: tty, isInteractive: true,
                commandArgs: cmd, smoothedCpu: smoothed, state: state
            ))
        }

        // Cleanup dead PIDs
        let alive = Set(sessions.map { $0.pid })
        cpuHistory = cpuHistory.filter { alive.contains($0.key) }
        wasWorking = wasWorking.filter { alive.contains($0) }
        workingTickCount = workingTickCount.filter { alive.contains($0.key) }

        // Prune names for dead TTYs
        let activeTTYs = Set(sessions.map { $0.tty })
        ClaudeNamer.prune(activeTTYs: activeTTYs)

        sessions.sort { $0.tty < $1.tty }
        return sessions
    }

    // Reset "done" back to idle after user has seen it
    func clearDone(pid: Int32) {
        wasWorking.remove(pid)
    }
}

// MARK: - Pixel Art: Claude Monitor Mascot

struct Clr {
    let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    // Claude-ish mascot palette
    static let O = Clr(r: 0.15, g: 0.11, b: 0.20, a: 1)    // outline
    static let C = Clr(r: 0.85, g: 0.45, b: 0.22, a: 1)    // primary orange
    static let c = Clr(r: 0.72, g: 0.36, b: 0.16, a: 1)    // shadow orange
    static let L = Clr(r: 0.95, g: 0.60, b: 0.30, a: 1)    // highlight orange
    static let E = Clr(r: 0.12, g: 0.10, b: 0.18, a: 1)    // eyes
    static let W = Clr(r: 0.98, g: 0.96, b: 0.92, a: 1)    // bright highlight
    static let X = Clr(r: 1.00, g: 0.88, b: 0.35, a: 1)    // spark
    static let G = Clr(r: 0.35, g: 0.82, b: 0.55, a: 1)    // screen green
    static let g = Clr(r: 0.22, g: 0.55, b: 0.35, a: 1)    // screen dark
    static let K = Clr(r: 0.45, g: 0.35, b: 0.25, a: 1)    // desk
    static let k = Clr(r: 0.35, g: 0.25, b: 0.18, a: 1)    // desk shadow
    static let B = Clr(r: 0.30, g: 0.28, b: 0.34, a: 1)    // keyboard
    static let D = Clr(r: 0.40, g: 0.80, b: 0.45, a: 1)    // done glow
    static let A = Clr(r: 0.29, g: 0.79, b: 0.92, a: 1)    // accent cyan
    static let a = Clr(r: 0.17, g: 0.45, b: 0.56, a: 1)    // accent cyan shadow
    static let M = Clr(r: 0.72, g: 0.74, b: 0.78, a: 1)    // metal highlight
    static let m = Clr(r: 0.52, g: 0.54, b: 0.58, a: 1)    // metal shadow
}

typealias P = Clr?
let n: P = nil
let O = Clr.O, C = Clr.C, c = Clr.c, L = Clr.L
let E = Clr.E, W = Clr.W, X = Clr.X
let G = Clr.G, g = Clr.g, K = Clr.K, k = Clr.k, B = Clr.B, D = Clr.D
let A = Clr.A, a = Clr.a, M = Clr.M, m = Clr.m

let spritePalette: [Character: P] = [
    ".": n, "O": O, "F": C, "f": c, "L": L, "E": E, "W": W, "X": X,
    "G": G, "g": g, "K": K, "k": k, "B": B, "D": D, "A": A, "a": a,
    "M": M, "m": m
]

func sprite(_ rows: [String]) -> [[P]] {
    rows.map { row in
        row.map { token in
            guard let color = spritePalette[token] else {
                preconditionFailure("Unknown sprite color token: \(token)")
            }
            return color
        }
    }
}

// Idle: breathing/blink loop, 16x16
let idleFrame1: [[P]] = sprite([
    "................",
    ".......AA.......",
    "......AaaA......",
    ".....OOFFOO.....",
    "....OFFLLFFO....",
    "...OFFLWWLFFO...",
    "...OFFAEEAFFO...",
    "...OFFAEEAFFO...",
    "...OFFFFfffFO...",
    "...OFFFFFFFFO...",
    "....OFMFFMFO....",
    "....OKBBBBKO....",
    "....OKKBBKKO....",
    ".....OkkkkO.....",
    "......OOOO......",
    "................",
])

let idleFrame2: [[P]] = sprite([
    "................",
    "................",
    ".......AA.......",
    "......AaaA......",
    ".....OOFFOO.....",
    "....OFFLLFFO....",
    "...OFFLWWLFFO...",
    "...OFFAaaAFFO...",
    "...OFFAAAAFFO...",
    "...OFFFFfffFO...",
    "...OFFFFFFFFO...",
    "....OFMFFMFO....",
    "....OKBBBBKO....",
    "....OKKBBKKO....",
    ".....OkkkkO.....",
    "......OOOO......",
])

let idleFrame3: [[P]] = sprite([
    "................",
    ".......AA.......",
    "......AaaA......",
    ".....OOFFOO.....",
    "...OOFFLLFFOO...",
    "...OFFLWWLFFO...",
    "...OFFAEaAFFO...",
    "...OFFAEEAFFO...",
    "...OFFFFfffFO...",
    "...OFFFFFFFFO...",
    "....OFFMMFFO....",
    "....OKBBBBKO....",
    "....OKBBKBKO....",
    ".....OkkkkO.....",
    "......OOOO......",
    "................",
])

// Working: desk typing loop, 18x16
let workFrame1: [[P]] = sprite([
    "..................",
    "......AA..........",
    ".....AaaA.........",
    "....OOFFOO........",
    "...OFFLLFFO.OOOO..",
    "..OFFAEEAFFOOGGO..",
    "..OFFAEEAFFOOGgO..",
    "..OFFFFfffFOOOOO..",
    "...OOFFFfOO.OOO...",
    ".OOKKKKKKKKKKKOO..",
    ".OKBBBBBBBBBBKBO..",
    ".OKKBBKBBKBBKKO...",
    "..OkkkkkkkkkkkO...",
    "...OOOOOOOOOOO....",
    "..................",
    "..................",
])

let workFrame2: [[P]] = sprite([
    "..................",
    "......AA..........",
    ".....AaaA.........",
    "....OOFFOO........",
    "...OFFLLFFO.OOOO..",
    "..OFFAEEAFFOOgGO..",
    "..OFFAEEAFFOOGGO..",
    "..OFFFffffFOOOOO..",
    "...OOFFffOO.OOO...",
    ".OOKKKKKKKKKKKOO..",
    ".OKBBBBBBBBBBKBO..",
    ".OKBKBKBBKBBKKO...",
    "..OkkkkkkkkkkkO...",
    "...OOOOOOOOOOO....",
    "..................",
    "..................",
])

let workFrame3: [[P]] = sprite([
    "..................",
    ".......AA.........",
    "......AaaA........",
    ".....OOFFOO.......",
    "....OFFLLFFO.OOOO.",
    "...OFFAEEAFFOOGgO.",
    "...OFFAEEAFFOOGGO.",
    "...OFFFFfffFOOOO..",
    "....OFFFFfOO.OO...",
    "..OOKKKKKKKKKOO...",
    ".OKBBBBBBBBBBKBO..",
    ".OKKBBKBBKKBKKO...",
    "..OkkkkkkkkkkO....",
    "...OOOOOOOOOO.....",
    "..................",
    "..................",
])

// Done: celebratory hand-raise wave, 16x16
let doneFrame1: [[P]] = sprite([
    ".......A........",
    "......AAA.......",
    ".....AWWA.......",
    ".....OOFFOO.....",
    "...OOFFLLFFO....",
    "...OFFAEEAFFOA..",
    "..OFFFAEEAFFOAA.",
    "..OFFFFfffFFOAA.",
    "..OFFFFFFFfFFO..",
    "...OOFFFFFfOO...",
    "....OOFFFfOO....",
    "...OkkkkkkkkO...",
    "...OKKKKKKKKO...",
    "....OOOOOOOO....",
    "......O..O......",
    ".....OOOOOO.....",
])

let doneFrame2: [[P]] = sprite([
    "......AA........",
    ".....AWWA.......",
    "....AAWWAA......",
    ".....OOFFOO.....",
    "...OOFFLLFFOA...",
    "...OFFAEEAFFOAA.",
    "..OFFFAEEAFFOAA.",
    "..OFFFFfffFFOA..",
    "..OFFFFFFFfFFO..",
    "...OOFFFFFfOO...",
    "....OOFFFfOO....",
    "...OkkkkkkkkO...",
    "...OKKKKKKKKO...",
    "....OOOOOOOO....",
    "......O..O......",
    ".....OOOOOO.....",
])

let doneFrame3: [[P]] = sprite([
    "...........X....",
    ".......A..XXX...",
    "......AAA..X....",
    ".....AWWA.......",
    "...OOFFLLFFOA...",
    "..OFFAEEAFFO....",
    "..OFFFAEEAFFOA..",
    ".OFFFFfffFFFO...",
    ".OFFFFFFFfFFO...",
    "..OOFFFFFfOO....",
    "...OOFFFfOO.....",
    "..OkkkkkkkkO....",
    "..OKKKKKKKKO....",
    "...OOOOOOOO.....",
    ".....O..O.......",
    "....OOOOOO......",
])

// MARK: - Sprite Renderer

func renderSprite(_ sprite: [[P]], pixelSize: Int) -> NSImage {
    let rows = sprite.count
    let cols = sprite.map { $0.count }.max() ?? 0
    let w = cols * pixelSize
    let h = rows * pixelSize

    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: w * 4, bitsPerPixel: 32
    )!

    let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)!
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext
    cgCtx.clear(CGRect(x: 0, y: 0, width: w, height: h))

    for (row, pixels) in sprite.enumerated() {
        for (col, clr) in pixels.enumerated() {
            guard let clr = clr else { continue }
            cgCtx.setFillColor(CGColor(red: clr.r, green: clr.g, blue: clr.b, alpha: clr.a))
            cgCtx.fill(CGRect(x: col * pixelSize, y: (rows - 1 - row) * pixelSize, width: pixelSize, height: pixelSize))
        }
    }

    NSGraphicsContext.current = nil
    let image = NSImage(size: NSSize(width: w, height: h))
    image.addRepresentation(bitmapRep)
    return image
}

// Pre-rendered sprite cache (created once at launch)
struct SpriteCache {
    let idle1: NSImage
    let idle2: NSImage
    let idle3: NSImage
    let work1: NSImage
    let work2: NSImage
    let work3: NSImage
    let done1: NSImage
    let done2: NSImage
    let done3: NSImage

    static func create() -> SpriteCache {
        SpriteCache(
            idle1: renderSprite(idleFrame1, pixelSize: 3),
            idle2: renderSprite(idleFrame2, pixelSize: 3),
            idle3: renderSprite(idleFrame3, pixelSize: 3),
            work1: renderSprite(workFrame1, pixelSize: 3),
            work2: renderSprite(workFrame2, pixelSize: 3),
            work3: renderSprite(workFrame3, pixelSize: 3),
            done1: renderSprite(doneFrame1, pixelSize: 3),
            done2: renderSprite(doneFrame2, pixelSize: 3),
            done3: renderSprite(doneFrame3, pixelSize: 3)
        )
    }
}

// MARK: - Session View

class ClaudeSessionView: NSView {
    let session: ClaudeSession
    var animFrame: Int = 0
    var sprites: SpriteCache!
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    var onClick: ((ClaudeSession) -> Void)?

    init(session: ClaudeSession, frame: NSRect, sprites: SpriteCache) {
        self.session = session
        self.sprites = sprites
        super.init(frame: frame)
        toolTip = session.tooltipText
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        trackingArea.map { removeTrackingArea($0) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?(session) }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor(white: 1.0, alpha: 0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        let img: NSImage
        switch session.state {
        case .working:
            let frames = [sprites.work1, sprites.work2, sprites.work3]
            img = frames[animFrame % frames.count]
        case .done:
            let frames = [sprites.done1, sprites.done2, sprites.done3]
            img = frames[(animFrame / 4) % frames.count]
        case .idle:
            let frames = [sprites.idle1, sprites.idle2, sprites.idle3]
            img = frames[(animFrame / 6) % frames.count]
        }

        let x = (bounds.width - img.size.width) / 2
        let y = (bounds.height - img.size.height) / 2 + 8
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: NSRect(x: x, y: y, width: img.size.width, height: img.size.height),
                 from: .zero, operation: .sourceOver, fraction: 1.0)

        // Name label
        let name = session.displayName
        let color: NSColor
        switch session.state {
        case .working: color = NSColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1.0)
        case .done: color = NSColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1.0)
        case .idle: color = NSColor(white: 0.6, alpha: 0.9)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: name, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: 2))

        // Activity dots for working
        if session.state == .working {
            let dots = (animFrame % 3) + 1
            NSColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 0.9).setFill()
            let totalW = CGFloat(dots) * 4 + CGFloat(dots - 1) * 3
            let sx = (bounds.width - totalW) / 2
            for i in 0..<dots {
                NSBezierPath(ovalIn: NSRect(x: sx + CGFloat(i) * 7, y: bounds.height - 6, width: 4, height: 4)).fill()
            }
        }

    }
}

// MARK: - Panel

class MonitorContentView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).addClip()
        NSColor(white: 0.08, alpha: 0.92).setFill()
        bounds.fill()
        NSColor(white: 0.25, alpha: 0.4).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()
    }
}

class MonitorPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - 140, y: f.maxY - 120))
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: MonitorPanel!
    var detector = SessionDetector()
    var sessions: [ClaudeSession] = []
    var views: [ClaudeSessionView] = []
    var frame: Int = 0
    var content: MonitorContentView!
    var titleLabel: NSTextField!
    var statusItem: NSStatusItem?
    var sprites: SpriteCache!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sprites = SpriteCache.create()

        panel = MonitorPanel()
        content = MonitorContentView()
        content.wantsLayer = true
        panel.contentView = content

        titleLabel = NSTextField(labelWithString: "Claude Monitor")
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        titleLabel.textColor = NSColor(red: 0.85, green: 0.45, blue: 0.22, alpha: 1.0)
        content.addSubview(titleLabel)

        panel.orderFront(nil)
        setupMenuBar()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollSessions()
        }
        Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            self?.frame += 1
            self?.animate()
        }
        pollSessions()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            let img = NSImage(size: NSSize(width: 16, height: 16))
            img.lockFocus()
            let p = NSBezierPath()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4 - .pi / 2
                let r: CGFloat = (i % 2 == 0) ? 6.5 : 2.5
                let pt = NSPoint(x: 8 + r * cos(a), y: 8 + r * sin(a))
                i == 0 ? p.move(to: pt) : p.line(to: pt)
            }
            p.close(); NSColor.black.setFill(); p.fill()
            img.unlockFocus()
            img.isTemplate = true
            btn.image = img
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Monitor", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func showPanel() { panel.orderFront(nil) }

    func pollSessions() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let newSessions = self.detector.detectSessions()
            DispatchQueue.main.async {
                let oldFP = self.sessions.map { "\($0.pid):\($0.state)" }.joined()
                let newFP = newSessions.map { "\($0.pid):\($0.state)" }.joined()
                self.sessions = newSessions
                if oldFP != newFP { self.rebuildViews() }
            }
        }
    }

    func rebuildViews() {
        content.subviews.forEach { $0.removeFromSuperview() }
        views.removeAll()
        content.addSubview(titleLabel)

        let cellW: CGFloat = 72, cellH: CGFloat = 78
        let pad: CGFloat = 10, titleH: CGFloat = 26
        let maxCols = 6

        let count = sessions.count
        let cols = min(count, maxCols)
        let rows = count == 0 ? 0 : (count + maxCols - 1) / maxCols

        let winW = max(CGFloat(max(cols, 1)) * cellW + pad * 2, 120)
        var winH = titleH + pad * 2
        if rows > 0 { winH += CGFloat(rows) * cellH }
        if count == 0 { winH += 40 }

        let old = panel.frame
        panel.setFrame(NSRect(x: old.maxX - winW, y: old.maxY - winH, width: winW, height: winH),
                       display: true, animate: true)

        titleLabel.stringValue = count == 0 ? "Claude Monitor" : "Claude (\(count))"
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: (winW - titleLabel.frame.width) / 2, y: winH - titleH - 2)

        if count == 0 {
            let lbl = NSTextField(labelWithString: "No active sessions")
            lbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            lbl.textColor = NSColor(white: 0.4, alpha: 1.0)
            lbl.sizeToFit()
            lbl.frame.origin = NSPoint(x: (winW - lbl.frame.width) / 2, y: winH / 2 - 10)
            content.addSubview(lbl)
            return
        }

        let yOff = winH - titleH - pad
        for (i, s) in sessions.enumerated() {
            let row = i / maxCols
            let col = i % maxCols
            let x = pad + CGFloat(col) * cellW
            let y = yOff - CGFloat(row + 1) * cellH

            let v = ClaudeSessionView(session: s, frame: NSRect(x: x, y: y, width: cellW, height: cellH), sprites: sprites)
            v.onClick = { [weak self] s in self?.jumpTo(s) }
            content.addSubview(v)
            views.append(v)
        }
    }

    func animate() {
        for v in views {
            v.animFrame = frame
            v.needsDisplay = true
        }
    }

    func jumpTo(_ session: ClaudeSession) {
        guard let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first else { return }

        // Prompt for accessibility if not yet granted (required for AXUIElement)
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            ghostty.activate()
            return
        }

        let axApp = AXUIElementCreateApplication(ghostty.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            ghostty.activate()
            return
        }

        // Get session CWD to match against window/tab titles
        let sessionCwd = getProcessCwd(pid: session.pid)
        let dirName = sessionCwd.flatMap { ($0 as NSString).lastPathComponent }

        // Strategy 1: Match window title against session's working directory name
        if let dir = dirName, !dir.isEmpty {
            for window in windows {
                let title = axTitle(of: window)
                if title.localizedCaseInsensitiveContains(dir) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 2: Search tab bar titles inside each window
        if let dir = dirName, !dir.isEmpty {
            for window in windows {
                if selectMatchingTab(in: window, matching: dir) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 3: Match by full CWD path in title (some configs show full path)
        if let cwd = sessionCwd {
            for window in windows {
                let title = axTitle(of: window)
                if title.contains(cwd) {
                    raiseGhosttyWindow(window, app: ghostty)
                    return
                }
            }
        }

        // Strategy 4: Single window — raise it, switch tab via Cmd+N
        let loginTTYs = ghosttyLoginTTYs(ghosttyPid: ghostty.processIdentifier)
        if windows.count == 1 {
            raiseGhosttyWindow(windows[0], app: ghostty)
            if let idx = loginTTYs.firstIndex(of: session.tty), idx < 9 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.pressCommandNumber(idx + 1)
                }
            }
            return
        }

        // Strategy 5: Multiple windows — correlate login process creation order with windows
        // AX windows are typically front-to-back z-order, so this is a heuristic.
        // We build a mapping using CGWindowList (which gives us stable window IDs) and
        // sort those by creation time (window number) to align with login PID order.
        if let ttyIdx = loginTTYs.firstIndex(of: session.tty) {
            let sortedWindows = windowsSortedByCreation(windows)
            if ttyIdx < sortedWindows.count {
                raiseGhosttyWindow(sortedWindows[ttyIdx], app: ghostty)
                return
            }
        }

        // Last resort
        ghostty.activate()
    }

    // MARK: - AX Helpers

    func axTitle(of element: AXUIElement) -> String {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        return ref as? String ?? ""
    }

    func raiseGhosttyWindow(_ window: AXUIElement, app: NSRunningApplication) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }

    /// Sort AX windows by their position (y then x) as a proxy for creation order
    func windowsSortedByCreation(_ windows: [AXUIElement]) -> [AXUIElement] {
        struct WindowPos {
            let element: AXUIElement
            let x: CGFloat
            let y: CGFloat
        }
        var positioned: [WindowPos] = []
        for w in windows {
            var posRef: AnyObject?
            var pos = CGPoint.zero
            if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success {
                AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
            }
            positioned.append(WindowPos(element: w, x: pos.x, y: pos.y))
        }
        // Sort by position as a rough heuristic (left-to-right, top-to-bottom)
        positioned.sort { ($0.y, $0.x) < ($1.y, $1.x) }
        return positioned.map(\.element)
    }

    /// Search a window's tab group for a tab whose title contains `text`, and select it
    func selectMatchingTab(in window: AXUIElement, matching text: String) -> Bool {
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }

        for child in children {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            guard let role = roleRef as? String, role == "AXTabGroup" else { continue }

            var tabsRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTabsAttribute as CFString, &tabsRef)
            guard let tabs = tabsRef as? [AXUIElement] else { continue }

            for tab in tabs {
                let tabTitle = axTitle(of: tab)
                if tabTitle.localizedCaseInsensitiveContains(text) {
                    AXUIElementPerformAction(tab, kAXPressAction as CFString)
                    return true
                }
            }
        }
        return false
    }

    /// Get CWD of a process via lsof
    func getProcessCwd(pid: Int32) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") { return String(line.dropFirst()) }
        }
        return nil
    }

    /// Get TTYs of Ghostty's login child processes, sorted by PID (creation order)
    func ghosttyLoginTTYs(ghosttyPid: pid_t) -> [String] {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-eo", "pid,ppid,tty,command"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var entries: [(pid: Int, tty: String)] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  ppid == Int(ghosttyPid),
                  String(parts[3]).contains("/usr/bin/login") else { continue }
            entries.append((pid: pid, tty: String(parts[2])))
        }
        return entries.sorted { $0.pid < $1.pid }.map(\.tty)
    }

    func pressCommandNumber(_ number: Int) {
        let keyCodes: [Int: UInt16] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25
        ]
        guard let keyCode = keyCodes[number] else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
