import AppKit

// MARK: - Color Palette

struct Clr {
    let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
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

// MARK: - Sprite Parsing

typealias P = Clr?

private let spritePalette: [Character: P] = [
    ".": nil, "O": .O, "F": .C, "f": .c, "L": .L, "E": .E, "W": .W, "X": .X,
    "G": .G, "g": .g, "K": .K, "k": .k, "B": .B, "D": .D, "A": .A, "a": .a,
    "M": .M, "m": .m,
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

// MARK: - Idle Frames (16x16)

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

// MARK: - Working Frames (18x16)

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

// MARK: - Done Frames (16x16)

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

// MARK: - Sprite Cache

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
