import Cocoa
import WebKit

// ConceptShots: one press takes screenshots of a page on desktop and on phone, plus any custom sizes.
// Files: <name>_desktop.jpg, <name>_phone.jpg, <name>_<W>x<H>.jpg. A second page (for example the current site)
// gives <name>_old_* and <name>_new_*. --names cs uses Czech names (stary_web, koncept, telefon, pocitac).
//
//   shots capture --url U --device phone|desktop --out F [--scroll Y] [--wait S] [--lang en-US]
//   shots pick    --url U --device phone|desktop --out F
//   shots lead    --concept U [--old U] [--slug S] [--dir D] [--sizes 768x1024,1920x1080] [--names en|cs] [--lang en-US] [--pick] [--force] [--wait S]
//   shots                     (no arguments: dialog window)
//
// Every capture prints one JSON line to stdout: {"ok":true,"path":...} or {"ok":false,"error":...}.

let fallbackDir = NSString(string: "~/Pictures/ConceptShots").expandingTildeInPath
var defaultDir: String { UserDefaults.standard.string(forKey: "outDir") ?? fallbackDir }

struct Device {
    let name: String, cs: String, w: CGFloat, h: CGFloat, outW: Int, outH: Int, ua: String?
    static let phone = Device(name: "phone", cs: "telefon", w: 375, h: 812, outW: 750, outH: 1624,
        ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
    static let desktop = Device(name: "desktop", cs: "pocitac", w: 1440, h: 900, outW: 800, outH: 500, ua: nil)
    static func named(_ s: String) -> Device? {
        switch s { case "phone", "telefon": return .phone; case "desktop", "pocitac": return .desktop; default: return custom(s) }
    }
    /// "WxH" in CSS pixels, saved at exactly that size
    static func custom(_ s: String) -> Device? {
        let p = s.lowercased().split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, (200...5000).contains(p[0]), (200...5000).contains(p[1]) else { return nil }
        let n = "\(p[0])x\(p[1])"
        return Device(name: n, cs: n, w: CGFloat(p[0]), h: CGFloat(p[1]), outW: p[0], outH: p[1], ua: nil)
    }
    static func list(_ s: String?) -> [Device] {
        (s ?? "").split(whereSeparator: { ", ;".contains($0) }).compactMap { custom(String($0)) }
    }
}

struct Job {
    let url: URL, device: Device, out: String
    var scrollY: Double = 0, wait: Double = 5, pick = false, label = "", lang = "en-US"
}

func emit(_ d: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: d), let s = String(data: data, encoding: .utf8) {
        print(s); fflush(stdout)
    }
}

// Lazy-loaded and scroll-revealed content only appears after a real scroll, so scroll through the page first.
let scrollThrough = """
const h = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0);
for (let y = 0; y < h; y += Math.round(innerHeight * 0.7)) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 140)); }
window.scrollTo(0, target);
await new Promise(r => setTimeout(r, 300));
window.scrollTo(0, target);
return true;
"""

final class Runner: NSObject, WKNavigationDelegate, NSWindowDelegate {
    var jobs: [Job]
    var results: [[String: Any]] = []
    var window: NSWindow?
    var web: WKWebView?
    var current: Job?
    var keyMonitor: Any?
    var timeout: DispatchWorkItem?
    let onDone: ([[String: Any]]) -> Void

    init(jobs: [Job], onDone: @escaping ([[String: Any]]) -> Void) {
        self.jobs = jobs; self.onDone = onDone
    }

    func next() {
        cleanup()
        guard !jobs.isEmpty else { onDone(results); return }
        let job = jobs.removeFirst()
        current = job
        let d = job.device
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        // sites that pick the language from the browser see a visitor with this language
        let langs = [job.lang, String(job.lang.prefix(2)), "en"]
        let js = "Object.defineProperty(navigator,'language',{get:()=>'\(job.lang)'});" +
                 "Object.defineProperty(navigator,'languages',{get:()=>\(langs)});"
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: d.w, height: d.h), configuration: cfg)
        wv.customUserAgent = d.ua
        wv.navigationDelegate = self
        // keep timers and animations running even when the window is not visible on screen
        if wv.responds(to: NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")) {
            wv.setValue(false, forKey: "windowOcclusionDetectionEnabled")
        }
        let win: NSWindow
        if job.pick {
            win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: d.w, height: d.h),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "\(job.label): scroll to the frame, Enter saves, Esc skips"
            win.center()
            win.delegate = self
        } else {
            win = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: d.w, height: d.h),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        }
        win.isReleasedWhenClosed = false
        win.contentView = wv
        if job.pick {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self = self else { return e }
                if e.keyCode == 36 || e.keyCode == 76 { self.snapshot(); return nil }
                if e.keyCode == 53 { self.fail("skipped"); return nil }
                return e
            }
        } else {
            win.orderFrontRegardless()
        }
        window = win; web = wv
        let t = DispatchWorkItem { [weak self] in self?.fail("page did not load in 45 s") }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: t)
        var req = URLRequest(url: job.url)
        req.setValue("\(job.lang),\(job.lang.prefix(2));q=0.9,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        wv.load(req)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        timeout?.cancel()
        guard let job = current else { return }
        if job.pick { return }   // the user scrolls and presses Enter
        webView.callAsyncJavaScript(scrollThrough, arguments: ["target": job.scrollY], in: nil, in: .page) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + job.wait) { self?.snapshot() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func windowWillClose(_ notification: Notification) {
        if current != nil { fail("window closed") }
    }

    func snapshot() {
        guard let wv = web, let job = current else { return }
        let scale = window?.backingScaleFactor ?? 2
        let cfg = WKSnapshotConfiguration()
        cfg.rect = wv.bounds
        cfg.afterScreenUpdates = true
        cfg.snapshotWidth = NSNumber(value: Double(job.device.outW) / Double(scale))
        wv.takeSnapshot(with: cfg) { [weak self] image, error in
            guard let self = self else { return }
            guard let image = image else { self.fail(error?.localizedDescription ?? "snapshot failed"); return }
            do {
                try self.writeJPEG(image, w: job.device.outW, h: job.device.outH, to: job.out)
                self.results.append(["ok": true, "path": job.out, "url": job.url.absoluteString, "device": job.device.name])
                emit(self.results.last!)
                self.current = nil
                self.next()
            } catch { self.fail(error.localizedDescription) }
        }
    }

    func writeJPEG(_ image: NSImage, w: Int, h: Int, to path: String) throws {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "shots", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap"])
        }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw NSError(domain: "shots", code: 2, userInfo: [NSLocalizedDescriptionKey: "jpeg"])
        }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }

    func fail(_ msg: String) {
        timeout?.cancel()
        guard let job = current else { return }
        current = nil
        results.append(["ok": false, "path": job.out, "url": job.url.absoluteString, "device": job.device.name, "error": msg])
        emit(results.last!)
        next()
    }

    func cleanup() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        web?.navigationDelegate = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil; web = nil
    }
}

// ---------- arguments ----------
func arg(_ name: String, _ a: [String]) -> String? {
    guard let i = a.firstIndex(of: "--" + name), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func flag(_ name: String, _ a: [String]) -> Bool { a.contains("--" + name) }

func normalizedURL(_ s: String) -> URL? {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    if !t.contains("://") { t = "https://" + t }
    return URL(string: t)
}

func slugFrom(_ url: URL) -> String {
    let parts = url.path.split(separator: "/").map(String.init)
    if let last = parts.last, !last.isEmpty { return last }
    var host = url.host ?? "site"
    if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
    return host.split(separator: ".").first.map(String.init) ?? "site"
}

func leadJobs(old: URL?, concept: URL, slug: String, dir: String, pick: Bool, wait: Double,
              lang: String = "en-US", names: String = "en", extra: [Device] = []) -> [Job] {
    var jobs: [Job] = []
    let cs = names == "cs"
    let pairs: [(URL?, String, String)]
    if cs { pairs = [(old, "stary_web", "Current site"), (concept, "koncept", "New design")] }
    else if old != nil { pairs = [(old, "old", "Current site"), (concept, "new", "New design")] }
    else { pairs = [(concept, "", "Page")] }
    for (u, kind, label) in pairs {
        guard let u = u else { continue }
        for d in [Device.phone, Device.desktop] + extra {
            let part = kind.isEmpty ? "" : "_\(kind)"
            var j = Job(url: u, device: d, out: "\(dir)/\(slug)\(part)_\(cs ? d.cs : d.name).jpg")
            j.pick = pick; j.wait = wait; j.lang = lang; j.label = "\(label), \(d.name)"
            jobs.append(j)
        }
    }
    return jobs
}

// ---------- dialog for people ----------
final class LinkOpener: NSObject {
    static let shared = LinkOpener()
    @objc func open() { NSWorkspace.shared.open(URL(string: "https://productive.studio")!) }
}

final class FolderPicker: NSObject {
    static let shared = FolderPicker()
    var label: NSTextField?
    @objc func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Choose"
        if p.runModal() == .OK, let u = p.url {
            label?.stringValue = u.path
            UserDefaults.standard.set(u.path, forKey: "outDir")
        }
    }
}

func askLead() -> (URL?, URL, String, String, Bool, String, [Device])? {
    let alert = NSAlert()
    alert.messageText = "ConceptShots"
    alert.informativeText = "One click: your page on desktop and on phone, plus any sizes you add."
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 350))
    var y: CGFloat = 326
    func field(_ label: String, _ value: String) -> NSTextField {
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: 0, y: y, width: 460, height: 16)
        box.addSubview(l)
        y -= 26
        let f = NSTextField(frame: NSRect(x: 0, y: y, width: 460, height: 22))
        f.stringValue = value
        box.addSubview(f)
        y -= 32
        return f
    }
    let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let urlF = field("Page URL", clip.hasPrefix("http") ? clip : "")
    let sizesF = field("Extra sizes, optional (for example 768x1024, 1920x1080)", UserDefaults.standard.string(forKey: "sizes") ?? "")
    let slugF = field("Name for the files (taken from the URL if empty)", "")
    let oldF = field("Second page, optional (for example the current site, for before and after)", "")
    let langF = field("Browser language", UserDefaults.standard.string(forKey: "lang") ?? "en-US")

    let folderLabel = NSTextField(labelWithString: defaultDir)
    folderLabel.lineBreakMode = .byTruncatingMiddle
    folderLabel.frame = NSRect(x: 0, y: y + 4, width: 370, height: 18)
    box.addSubview(folderLabel)
    FolderPicker.shared.label = folderLabel
    let choose = NSButton(title: "Folder…", target: FolderPicker.shared, action: #selector(FolderPicker.choose))
    choose.bezelStyle = .rounded
    choose.frame = NSRect(x: 376, y: y, width: 84, height: 24)
    box.addSubview(choose)
    y -= 32

    let pick = NSButton(checkboxWithTitle: "I scroll to each frame myself (Enter saves)", target: nil, action: nil)
    pick.state = .off
    pick.frame = NSRect(x: 0, y: y, width: 460, height: 22)
    box.addSubview(pick)
    y -= 28
    let by = NSButton(title: "Made by productive.studio", target: LinkOpener.shared, action: #selector(LinkOpener.open))
    by.isBordered = false
    by.attributedTitle = NSAttributedString(string: "Made by productive.studio", attributes: [
        .foregroundColor: NSColor.secondaryLabelColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
        .font: NSFont.systemFont(ofSize: 12)])
    by.frame = NSRect(x: 0, y: y, width: 200, height: 20)
    box.addSubview(by)
    alert.accessoryView = box
    alert.addButton(withTitle: "Take shots")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = urlF
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn, let page = normalizedURL(urlF.stringValue) else { return nil }
    let s = slugF.stringValue.trimmingCharacters(in: .whitespaces)
    let lang = langF.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "en-US" : langF.stringValue.trimmingCharacters(in: .whitespaces)
    UserDefaults.standard.set(lang, forKey: "lang")
    UserDefaults.standard.set(sizesF.stringValue, forKey: "sizes")
    return (normalizedURL(oldF.stringValue), page, s.isEmpty ? slugFrom(page) : s, folderLabel.stringValue,
            pick.state == .on, lang, Device.list(sizesF.stringValue))
}

func confirmOverwrite(_ files: [String]) -> Bool {
    let a = NSAlert()
    a.messageText = "These files already exist"
    a.informativeText = files.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n") + "\n\nReplace them?"
    a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
}

// ---------- main ----------
let app = NSApplication.shared
var argv = Array(CommandLine.arguments.dropFirst())
argv.removeAll { $0.hasPrefix("-psn_") }
let cmd = argv.first ?? "gui"
let gui = cmd == "gui"
app.setActivationPolicy((gui || cmd == "pick" || flag("pick", argv)) ? .regular : .accessory)

var jobs: [Job] = []
func usage() -> Never {
    FileHandle.standardError.write("usage: shots capture|pick --url U --device phone|desktop --out F | shots lead --concept U [--old U] [--slug S] [--dir D] [--sizes 768x1024,1920x1080] [--names en|cs] [--lang en-US] [--pick] [--force]\n".data(using: .utf8)!)
    exit(64)
}

switch cmd {
case "capture", "pick":
    guard let u = arg("url", argv).flatMap(normalizedURL), let d = arg("device", argv).flatMap(Device.named),
          let out = arg("out", argv) else { usage() }
    var j = Job(url: u, device: d, out: NSString(string: out).expandingTildeInPath)
    j.scrollY = Double(arg("scroll", argv) ?? "0") ?? 0
    j.wait = Double(arg("wait", argv) ?? "5") ?? 5
    j.pick = cmd == "pick"; j.label = d.name
    j.lang = arg("lang", argv) ?? "en-US"
    jobs = [j]
case "lead":
    guard let concept = arg("concept", argv).flatMap(normalizedURL) else { usage() }
    let dir = NSString(string: arg("dir", argv) ?? fallbackDir).expandingTildeInPath
    let slug = arg("slug", argv) ?? slugFrom(concept)
    jobs = leadJobs(old: arg("old", argv).flatMap(normalizedURL), concept: concept, slug: slug, dir: dir,
                    pick: flag("pick", argv), wait: Double(arg("wait", argv) ?? "5") ?? 5,
                    lang: arg("lang", argv) ?? "en-US", names: arg("names", argv) ?? "en",
                    extra: Device.list(arg("sizes", argv)))
    let existing = jobs.map(\.out).filter { FileManager.default.fileExists(atPath: $0) }
    if !existing.isEmpty && !flag("force", argv) {
        emit(["ok": false, "error": "files already exist, pass --force to replace", "existing": existing])
        exit(3)
    }
case "gui":
    break
default:
    usage()
}

var runner: Runner?
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        if gui {
            guard let (old, concept, slug, dir, pick, lang, extra) = askLead() else { NSApp.terminate(nil); return }
            jobs = leadJobs(old: old, concept: concept, slug: slug, dir: dir, pick: pick, wait: 5, lang: lang, extra: extra)
            let existing = jobs.map(\.out).filter { FileManager.default.fileExists(atPath: $0) }
            if !existing.isEmpty && !confirmOverwrite(existing) { NSApp.terminate(nil); return }
        }
        runner = Runner(jobs: jobs) { results in
            let ok = results.filter { ($0["ok"] as? Bool) == true }.compactMap { $0["path"] as? String }
            if gui {
                if !ok.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(ok.map { URL(fileURLWithPath: $0) }) }
                let failed = results.filter { ($0["ok"] as? Bool) != true }
                if !failed.isEmpty {
                    let a = NSAlert()
                    a.messageText = "\(ok.count) saved, \(failed.count) not saved"
                    a.informativeText = failed.map { "\(($0["path"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""): \($0["error"] ?? "")" }.joined(separator: "\n")
                    a.runModal()
                }
            }
            exit(results.allSatisfy { ($0["ok"] as? Bool) == true } ? 0 : 1)
        }
        runner?.next()
    }
}
let delegate = Delegate()
app.delegate = delegate
app.run()
