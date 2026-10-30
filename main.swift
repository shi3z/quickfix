import Cocoa
import CoreImage
import Vision
import UniformTypeIdentifiers

// MARK: - Model

struct Region {
    var rect: CGRect      // 画像ピクセル座標 (左上原点)
    var isFace: Bool
    var enabled: Bool     // false = モザイク解除済み
}

struct Snapshot {
    var image: CGImage
    var regions: [Region]
}

struct Params {
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var coarseness = 7.0   // 1...10
}

// MARK: - Image processing

let ciContext = CIContext()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func workingSpace(_ cs: CGColorSpace?) -> CGColorSpace {
    if let cs = cs, cs.model == .rgb { return cs }
    return sRGB
}

func loadImage(_ url: URL) -> CGImage? {
    guard let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
    let ext = ci.extent
    guard ext.width > 0, ext.height > 0, ext.width.isFinite else { return nil }
    return ciContext.createCGImage(ci, from: ext, format: .RGBA8, colorSpace: workingSpace(ci.colorSpace))
}

func rotated(_ img: CGImage, clockwise: Bool) -> CGImage {
    let w = CGFloat(img.width), h = CGFloat(img.height)
    let t: CGAffineTransform = clockwise
        ? CGAffineTransform(rotationAngle: -.pi / 2).concatenating(CGAffineTransform(translationX: 0, y: w))
        : CGAffineTransform(rotationAngle: .pi / 2).concatenating(CGAffineTransform(translationX: h, y: 0))
    let out = CIImage(cgImage: img).transformed(by: t)
    return ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: h, height: w),
                                   format: .RGBA8, colorSpace: workingSpace(img.colorSpace)) ?? img
}

func rotate(_ r: CGRect, imageSize: CGSize, clockwise: Bool) -> CGRect {
    if clockwise {
        return CGRect(x: imageSize.height - r.minY - r.height, y: r.minX, width: r.height, height: r.width)
    } else {
        return CGRect(x: r.minY, y: imageSize.width - r.minX - r.width, width: r.height, height: r.width)
    }
}

func compose(base: CGImage, regions: [Region], params p: Params) -> CGImage {
    let W = CGFloat(base.width), H = CGFloat(base.height)
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    let src = CIImage(cgImage: base)
    var result = src

    let cells = 4.0 * pow(1.5, 10.0 - p.coarseness)   // 粗さ10→4分割 … 1→約150分割
    for r in regions where r.enabled {
        let rr = r.rect.intersection(full)
        if rr.isNull || rr.width < 1 || rr.height < 1 { continue }
        let ciRect = CGRect(x: rr.minX, y: H - rr.maxY, width: rr.width, height: rr.height)
        let block = max(1.5, max(rr.width, rr.height) / cells)
        let pix = src.clampedToExtent().applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: block,
            kCIInputCenterKey: CIVector(x: ciRect.minX, y: ciRect.minY),
        ]).cropped(to: ciRect)
        result = pix.composited(over: result)
    }

    if p.brightness != 0 || p.contrast != 1 || p.saturation != 1 {
        result = result.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: p.brightness,
            kCIInputContrastKey: p.contrast,
            kCIInputSaturationKey: p.saturation,
        ])
    }
    if p.warmth != 0 {
        let k = 0.25 * p.warmth
        result = result.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 + k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1 - k, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }
    return ciContext.createCGImage(result, from: full, format: .RGBA8,
                                   colorSpace: workingSpace(base.colorSpace)) ?? base
}

func writeImage(_ img: CGImage, to url: URL) throws {
    let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .png
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
    guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PNGQuickFix", code: 1, userInfo: [NSLocalizedDescriptionKey: "書き込み先を作れません"])
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: tmp)
        throw NSError(domain: "PNGQuickFix", code: 2, userInfo: [NSLocalizedDescriptionKey: "画像の書き出しに失敗しました"])
    }
    _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
}

// MARK: - Canvas

final class Canvas: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var regions: [Region] = [] { didSet { needsDisplay = true } }
    var onClickRegion: ((Int) -> Void)?
    var onNewRect: ((CGRect) -> Void)?

    private var dragStart: NSPoint?
    private var dragCur: NSPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var imgSize: CGSize { image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }

    private func imageRect() -> CGRect {
        let s = imgSize
        guard s.width > 0 else { return .zero }
        let avail = bounds.insetBy(dx: 8, dy: 8)
        let k = min(avail.width / s.width, avail.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: avail.midX - w / 2, y: avail.midY - h / 2, width: w, height: h)
    }

    private func toImage(_ p: NSPoint) -> CGPoint {
        let ir = imageRect()
        return CGPoint(x: (p.x - ir.minX) / ir.width * imgSize.width,
                       y: (p.y - ir.minY) / ir.height * imgSize.height)
    }

    private func toView(_ r: CGRect) -> CGRect {
        let ir = imageRect()
        let k = ir.width / imgSize.width
        return CGRect(x: ir.minX + r.minX * k, y: ir.minY + r.minY * k, width: r.width * k, height: r.height * k)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.16, alpha: 1).setFill()
        bounds.fill()
        guard let image = image else { return }
        let ir = imageRect()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: imgSize).draw(in: ir, from: .zero, operation: .sourceOver,
                                                    fraction: 1, respectFlipped: true, hints: nil)
        for r in regions {
            let v = toView(r.rect)
            let path = NSBezierPath(rect: v)
            if r.isFace {
                if r.enabled {
                    NSColor.systemOrange.setStroke(); path.lineWidth = 2
                } else {
                    NSColor.systemGreen.setStroke(); path.lineWidth = 2
                    path.setLineDash([5, 4], count: 2, phase: 0)
                }
            } else {
                NSColor.systemCyan.setStroke(); path.lineWidth = 2
            }
            path.stroke()
        }
        if let a = dragStart, let b = dragCur {
            let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            NSColor.white.withAlphaComponent(0.15).setFill()
            rect.fill()
            let path = NSBezierPath(rect: rect)
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.white.setStroke()
            path.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) {
        dragStart = convert(e.locationInWindow, from: nil)
        dragCur = dragStart
    }

    override func mouseDragged(with e: NSEvent) {
        dragCur = convert(e.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { dragStart = nil; dragCur = nil; needsDisplay = true }
        guard let a = dragStart, image != nil else { return }
        let b = convert(e.locationInWindow, from: nil)
        if hypot(b.x - a.x, b.y - a.y) < 4 {
            let p = toImage(b)
            if let i = regions.lastIndex(where: { $0.rect.contains(p) }) { onClickRegion?(i) }
        } else {
            let p1 = toImage(a), p2 = toImage(b)
            let r = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                .intersection(CGRect(origin: .zero, size: imgSize))
            if !r.isNull, r.width >= 4, r.height >= 4 { onNewRect?(r) }
        }
    }
}

// MARK: - Editor window

final class EditorController: NSObject, NSWindowDelegate {
    let url: URL
    var window: NSWindow!
    let canvas = Canvas()
    var base: CGImage
    var regions: [Region] = []
    var undoStack: [Snapshot] = []
    var onClose: ((EditorController) -> Void)?
    let status = NSTextField(labelWithString: "")

    let sBright = NSSlider(value: 0, minValue: -0.5, maxValue: 0.5, target: nil, action: nil)
    let sContrast = NSSlider(value: 1, minValue: 0.5, maxValue: 1.5, target: nil, action: nil)
    let sSat = NSSlider(value: 1, minValue: 0, maxValue: 2, target: nil, action: nil)
    let sWarm = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let sCoarse = NSSlider(value: 7, minValue: 1, maxValue: 10, target: nil, action: nil)

    init?(url: URL) {
        guard let img = loadImage(url) else { return nil }
        self.url = url
        self.base = img
        super.init()
        buildWindow()
        refresh()
        detectFaces(undoable: false)
    }

    var params: Params {
        Params(brightness: sBright.doubleValue, contrast: sContrast.doubleValue,
               saturation: sSat.doubleValue, warmth: sWarm.doubleValue, coarseness: sCoarse.doubleValue)
    }

    // MARK: UI

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func sliderGroup(_ title: String, _ s: NSSlider) -> NSStackView {
        s.target = self
        s.action = #selector(slidersChanged)
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12)
        let g = NSStackView(views: [l, s])
        g.spacing = 4
        return g
    }

    private func buildWindow() {
        let row1 = NSStackView(views: [
            button("⟲ 左回転", #selector(rotateLeft)),
            button("⟳ 右回転", #selector(rotateRight)),
            button("顔を再検出", #selector(redetect)),
            button("取り消し", #selector(undo)),
            NSView(),
            button("上書き保存", #selector(save)),
        ])
        row1.spacing = 8
        (row1.views.last as? NSButton)?.keyEquivalent = "\r"

        let row2 = NSStackView(views: [
            sliderGroup("明るさ", sBright), sliderGroup("コントラスト", sContrast),
            sliderGroup("彩度", sSat), sliderGroup("色温度", sWarm),
            button("色リセット", #selector(resetColor)),
            sliderGroup("モザイク粗さ", sCoarse),
        ])
        row2.spacing = 12

        let bar = NSStackView(views: [row1, row2])
        bar.orientation = .vertical
        bar.alignment = .leading
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        row1.translatesAutoresizingMaskIntoConstraints = false
        row1.widthAnchor.constraint(equalTo: bar.widthAnchor).isActive = true

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onClickRegion = { [weak self] i in self?.clickRegion(i) }
        canvas.onNewRect = { [weak self] r in self?.addManual(r) }

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        status.lineBreakMode = .byTruncatingTail

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let iw = CGFloat(base.width), ih = CGFloat(base.height)
        let k = min(1, screen.width * 0.85 / iw, (screen.height * 0.85 - 110) / ih)
        let cw = max(900, iw * k + 16), ch = max(420, ih * k + 16)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: cw, height: ch + 110))
        content.addSubview(bar); content.addSubview(canvas); content.addSubview(status)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            canvas.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        window = NSWindow(contentRect: content.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.contentView = content
        window.minSize = NSSize(width: 900, height: 480)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = url.lastPathComponent
        window.representedURL = url
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: State

    private func pushUndo() {
        undoStack.append(Snapshot(image: base, regions: regions))
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    func refresh() {
        canvas.image = compose(base: base, regions: regions, params: params)
        canvas.regions = regions
        let faces = regions.filter { $0.isFace }
        let on = faces.filter { $0.enabled }.count
        let manual = regions.count - faces.count
        status.stringValue = "\(base.width)×\(base.height)   顔 \(faces.count) 件中 \(on) 件モザイク / 手動 \(manual) 件   ー  ドラッグ: 範囲モザイク  /  枠をクリック: 顔のモザイク解除・再適用 (手動枠は削除)"
    }

    func detectFaces(undoable: Bool) {
        let img = base
        status.stringValue = "顔を検出中…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
            let W = CGFloat(img.width), H = CGFloat(img.height)
            let bounds = CGRect(x: 0, y: 0, width: W, height: H)
            let rects: [CGRect] = (req.results ?? []).map { f in
                let bb = f.boundingBox
                let r = CGRect(x: bb.minX * W, y: (1 - bb.maxY) * H, width: bb.width * W, height: bb.height * H)
                return r.insetBy(dx: -r.width * 0.15, dy: -r.height * 0.2).intersection(bounds)
            }
            DispatchQueue.main.async {
                guard let self = self, self.base === img else { return }
                if undoable { self.pushUndo() }
                self.regions = self.regions.filter { !$0.isFace } + rects.map { Region(rect: $0, isFace: true, enabled: true) }
                self.refresh()
            }
        }
    }

    // MARK: Actions

    @objc func slidersChanged() { refresh() }

    @objc func resetColor() {
        sBright.doubleValue = 0; sContrast.doubleValue = 1; sSat.doubleValue = 1; sWarm.doubleValue = 0
        refresh()
    }

    @objc func rotateLeft() { rotateImage(clockwise: false) }
    @objc func rotateRight() { rotateImage(clockwise: true) }

    private func rotateImage(clockwise: Bool) {
        pushUndo()
        let size = CGSize(width: base.width, height: base.height)
        base = rotated(base, clockwise: clockwise)
        for i in regions.indices { regions[i].rect = rotate(regions[i].rect, imageSize: size, clockwise: clockwise) }
        refresh()
    }

    @objc func redetect() { detectFaces(undoable: true) }

    @objc func undo() {
        guard let s = undoStack.popLast() else { NSSound.beep(); return }
        base = s.image
        regions = s.regions
        refresh()
    }

    private func clickRegion(_ i: Int) {
        guard regions.indices.contains(i) else { return }
        pushUndo()
        if regions[i].isFace { regions[i].enabled.toggle() } else { regions.remove(at: i) }
        refresh()
    }

    private func addManual(_ r: CGRect) {
        pushUndo()
        regions.append(Region(rect: r, isFace: false, enabled: true))
        refresh()
    }

    @objc func save() {
        let out = compose(base: base, regions: regions, params: params)
        do {
            try writeImage(out, to: url)
            // 保存した内容を新しい元画像にする
            base = out
            regions = []
            undoStack.removeAll()
            sBright.doubleValue = 0; sContrast.doubleValue = 1; sSat.doubleValue = 1; sWarm.doubleValue = 0
            refresh()
            status.stringValue = "保存しました: \(url.path)"
        } catch {
            let a = NSAlert(error: error)
            a.beginSheetModal(for: window)
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?(self) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var editors: [EditorController] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !args.isEmpty { open(args.map { URL(fileURLWithPath: $0) }) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            if editors.isEmpty { openPanel() }
        }
    }

    func application(_ app: NSApplication, open urls: [URL]) { open(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }
    func applicationShouldOpenUntitledFile(_ a: NSApplication) -> Bool { false }

    func open(_ urls: [URL]) {
        for u in urls {
            if let ex = editors.first(where: { $0.url == u }) { ex.window.makeKeyAndOrderFront(nil); continue }
            guard let ed = EditorController(url: u) else {
                let a = NSAlert()
                a.messageText = "画像を開けません"
                a.informativeText = u.path
                a.runModal()
                continue
            }
            ed.onClose = { [weak self] e in self?.editors.removeAll { $0 === e } }
            editors.append(ed)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg]
        p.allowsMultipleSelection = true
        if p.runModal() == .OK { open(p.urls) }
    }

    private var current: EditorController? {
        editors.first { $0.window === NSApp.keyWindow }
    }
    @objc func doSave() { current?.save() }
    @objc func doUndo() { current?.undo() }
    @objc func doRotL() { current?.rotateLeft() }
    @objc func doRotR() { current?.rotateRight() }

    private func buildMenu() {
        let main = NSMenu()
        func add(_ menu: NSMenu, _ title: String, _ sel: Selector?, _ key: String, target: AnyObject? = nil,
                 mods: NSEvent.ModifierFlags = .command) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.keyEquivalentModifierMask = mods
            it.target = target
            menu.addItem(it)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let m = NSMenu(title: title); item.submenu = m
            return m
        }
        let app = submenu("PNG Quick Fix")
        add(app, "PNG Quick Fix を終了", #selector(NSApplication.terminate(_:)), "q")
        let file = submenu("ファイル")
        add(file, "開く…", #selector(openPanel), "o", target: self)
        add(file, "上書き保存", #selector(doSave), "s", target: self)
        add(file, "閉じる", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("編集")
        add(edit, "取り消し", #selector(doUndo), "z", target: self)
        let img = submenu("画像")
        add(img, "左に回転", #selector(doRotL), "[", target: self)
        add(img, "右に回転", #selector(doRotR), "]", target: self)
        NSApp.mainMenu = main
    }
}

// `PNGQuickFix --set-default` : .png の既定アプリにする
if CommandLine.arguments.contains("--set-default") {
    let bundle = Bundle.main.bundleURL
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: bundle, toOpen: UTType.png)
            print("PNG の既定アプリに設定しました")
        } catch {
            print("失敗: \(error.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
