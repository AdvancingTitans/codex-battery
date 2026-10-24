import AppKit
import ServiceManagement
import Darwin

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let translated = NSLocalizedString(key, comment: "")
    return arguments.isEmpty ? translated : String(format: translated, arguments: arguments)
}
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"

struct QuotaWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int? {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        return Int((100 - usedPercent).rounded(.down))
    }
    var title: String {
        guard let minutes = windowDurationMins else { return L("Quota window") }
        if minutes == 10080 { return L("Weekly quota") }
        if minutes % 1440 == 0 { return L("%d-day quota", minutes / 1440) }
        if minutes % 60 == 0 { return L("%d-hour quota", minutes / 60) }
        return L("%d-minute quota", minutes)
    }
}
struct QuotaBucket: Decodable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
    var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
}
struct Usage: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var codex: QuotaBucket? {
        // A supplied bucket map is authoritative; never substitute another model's quota.
        if let map = rateLimitsByLimitId { return map["codex"] }
        return rateLimits
    }
}
struct BatteryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Only this serial worker accesses the app-server connection.
final class UsageClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 10
    static func cliPath() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw BatteryError(message: L("Codex CLI was not found. Install it and reopen the app."))
        }
        // npm's wrapper needs Node on PATH, which Finder does not inherit.
        // Prefer the native executable shipped by that same installed CLI.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        if resolved.pathExtension == "js" {
            let root = resolved.deletingLastPathComponent().deletingLastPathComponent().path
            #if arch(arm64)
            let platform = "darwin-arm64", target = "aarch64-apple-darwin"
            #else
            let platform = "darwin-x64", target = "x86_64-apple-darwin"
            #endif
            let native = [root + "/node_modules/@openai/codex-" + platform + "/vendor/" + target + "/bin/codex",
                          root + "/vendor/" + target + "/bin/codex"]
            if let executable = native.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return executable }
        }
        return path
    }
    func stop() {
        try? input?.close()
        if let p = process, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(1)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
        }
        try? output?.close()
        process = nil; input = nil; output = nil; buffer.removeAll()
    }
    private func send(_ object: [String: Any]) throws {
        guard let input else { throw BatteryError(message: L("The Codex connection was lost.")) }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.write(contentsOf: data)
    }
    private func response(id: Int, timeout: TimeInterval = 25) throws -> Data {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let responseID = object["id"] as? Int, responseID == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    let code = error["code"] as? Int ?? 0
                    throw BatteryError(message: L("Could not read Codex usage (%d). Check CLI sign-in and your network.", code))
                }
                guard let result = object["result"] else { throw BatteryError(message: L("Codex returned no data.")) }
                return try JSONSerialization.data(withJSONObject: result)
            }
            guard let output else { throw BatteryError(message: L("The Codex connection is closed.")) }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = max(1, Int32((end - ProcessInfo.processInfo.systemUptime) * 1000))
            let ready = poll(&descriptor, 1, remaining)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { throw BatteryError(message: L("Request timed out. Check your network and Codex sign-in.")) }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            guard count > 0 else { throw BatteryError(message: L("Codex disconnected. The next refresh will reconnect.")) }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 2_000_000 { throw BatteryError(message: L("The Codex response was too large.")) }
        }
        throw BatteryError(message: L("Request timed out. Try again later."))
    }
    private func connect() throws {
        if process?.isRunning == true { return }
        stop()
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = URL(fileURLWithPath: try Self.cliPath())
        p.arguments = ["app-server", "--stdio"]
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        try p.run()
        process = p; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_battery", "title": "Codex Battery", "version": appVersion]]])
        _ = try response(id: 1)
        try send(["method": "initialized", "params": [:]])
    }
    func fetch() throws -> QuotaBucket {
        do {
            try connect()
            sequence += 1
            try send(["id": sequence, "method": "account/rateLimits/read"])
            let usage = try JSONDecoder().decode(Usage.self, from: response(id: sequence))
            guard let bucket = usage.codex, !bucket.windows.isEmpty else {
                throw BatteryError(message: L("No Codex quota was returned. Sign in to the CLI with a ChatGPT account."))
            }
            return bucket
        } catch {
            stop()
            throw error
        }
    }
    deinit { stop() }
}

enum BatteryBand { case green, orange, red }

struct ColorThresholds {
    let redBelow: Int
    let greenFrom: Int
    static let standard = ColorThresholds(redBelow: 20, greenFrom: 70)!

    init?(redBelow: Int, greenFrom: Int) {
        guard (0...100).contains(redBelow), (0...100).contains(greenFrom), redBelow < greenFrom else { return nil }
        self.redBelow = redBelow; self.greenFrom = greenFrom
    }
    init(defaults: UserDefaults) {
        self = ColorThresholds(redBelow: defaults.object(forKey: "redBelow") as? Int ?? 20,
                               greenFrom: defaults.object(forKey: "greenFrom") as? Int ?? 70) ?? .standard
    }
    func band(for percent: Int) -> BatteryBand {
        if percent >= greenFrom { return .green }
        return percent < redBelow ? .red : .orange
    }
    func color(for percent: Int, dark: Bool) -> NSColor {
        switch band(for: percent) {
        case .green: return dark ? NSColor(srgbRed: 0.28, green: 0.90, blue: 0.49, alpha: 1) : NSColor(srgbRed: 0.04, green: 0.45, blue: 0.18, alpha: 1)
        case .orange: return dark ? NSColor(srgbRed: 1, green: 0.70, blue: 0.25, alpha: 1) : NSColor(srgbRed: 0.67, green: 0.30, blue: 0, alpha: 1)
        case .red: return dark ? NSColor(srgbRed: 1, green: 0.40, blue: 0.44, alpha: 1) : NSColor(srgbRed: 0.78, green: 0.10, blue: 0.16, alpha: 1)
        }
    }
}

func batteryImage(percent: Int?, stale: Bool = false, thresholds: ColorThresholds = .standard, dark: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: 43, height: 22), flipped: false) { _ in
        let foreground = NSColor(calibratedWhite: dark ? 0.94 : 0.12, alpha: 1)
        let body = NSRect(x: 1, y: 3, width: 37, height: 16)
        foreground.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
        outline.lineWidth = 1.3; outline.stroke()
        foreground.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: NSRect(x: 39.5, y: 8, width: 2.2, height: 6), xRadius: 1, yRadius: 1).fill()
        let inside = body.insetBy(dx: 2, dy: 2)
        let fill = NSRect(x: inside.minX, y: inside.minY, width: inside.width * CGFloat(stale ? 0 : percent ?? 0) / 100, height: inside.height)
        let fillPath = NSBezierPath(roundedRect: fill, xRadius: 1.2, yRadius: 1.2)
        if let percent, !stale, fill.width > 0 {
            thresholds.color(for: percent, dark: dark).setFill()
            fillPath.fill()
        }
        let text = stale ? "?" : percent.map { "\($0)%" } ?? "—"
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold), .foregroundColor: foreground]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2)
        // Keep digits neutral, with contrasting text over the colored charge bar.
        NSGraphicsContext.saveGraphicsState()
        let empty = NSBezierPath(rect: body)
        empty.append(fillPath); empty.windingRule = .evenOdd; empty.addClip()
        text.draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        if fill.width > 0 {
            NSGraphicsContext.saveGraphicsState()
            fillPath.addClip()
            attributes[.foregroundColor] = dark ? NSColor.black : NSColor.white
            text.draw(at: origin, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
    image.isTemplate = false
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var status: NSStatusItem!
    private let menu = NSMenu()
    private let client = UsageClient()
    private let worker = DispatchQueue(label: "local.codexbattery.usage", qos: .utility)
    private var timer: Timer?
    private var bucket: QuotaBucket?
    private var lastUpdated: Date?
    private var lastError: String?
    private var loading = false
    private var quitting = false
    private var appearanceObservation: NSKeyValueObservation?
    private let defaults = UserDefaults.standard
    private var interval: TimeInterval {
        let value = defaults.double(forKey: "refreshInterval")
        return [15.0, 30.0, 60.0, 300.0].contains(value) ? value : 30
    }
    private var displayMode: Int { defaults.integer(forKey: "displayMode") }
    private var selected: QuotaWindow? {
        guard let windows = bucket?.windows else { return nil }
        if displayMode == 2 { return windows.filter { $0.remaining != nil }.min { $0.remaining! < $1.remaining! } }
        let minutes = displayMode == 1 ? 10080 : 300
        return windows.first { $0.windowDurationMins == minutes }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.advancingtitans.codexbattery")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        // Preserve settings from the local prototype when upgrading to the public release.
        if !defaults.bool(forKey: "migratedPrototypeSettings") {
            let previous = defaults.persistentDomain(forName: "local.yjw.codexbattery") ?? [:]
            for key in ["redBelow", "greenFrom", "displayMode", "refreshInterval"] where defaults.object(forKey: key) == nil {
                if let value = previous[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedPrototypeSettings")
        }
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: 47)
        status.menu = menu; menu.delegate = self
        appearanceObservation = status.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        updateIcon(); rebuildMenu(); schedule(); refresh()
        if CommandLine.arguments.contains("--settings") { DispatchQueue.main.async { self.configureColors() } }
    }
    private func schedule() {
        timer?.invalidate()
        timer = Timer(timeInterval: interval, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }
    @objc private func wake() { refresh() }
    @objc private func refresh() {
        guard !loading && !quitting else { return }
        loading = true; rebuildMenu()
        worker.async { [self] in
            let result = Result { try client.fetch() }
            DispatchQueue.main.async { [self] in
                guard !quitting else { return }
                loading = false
                switch result {
                case .success(let value): bucket = value; lastUpdated = Date(); lastError = nil
                case .failure(let error): lastError = error.localizedDescription
                }
                updateIcon(); rebuildMenu()
            }
        }
    }
    private func updateIcon() {
        let percent = selected?.remaining
        let dark = status.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        status.button?.image = batteryImage(percent: lastError == nil ? percent : nil, stale: lastError != nil,
                                           thresholds: ColorThresholds(defaults: defaults), dark: dark)
        let label = selected?.title ?? L("No data for this window")
        let summary = percent.map { L("%@: %d%% remaining", label, $0) } ?? label
        status.button?.toolTip = "Codex · " + (lastError ?? summary)
        status.button?.setAccessibilityLabel(L("Codex usage: ") + (lastError ?? summary))
    }
    @discardableResult
    private func add(_ title: String, action: Selector? = nil, to parent: NSMenu? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.tag = tag
        (parent ?? menu).addItem(item)
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        if lastUpdated == nil || Date().timeIntervalSince(lastUpdated!) > 10 { refresh() }
    }
    private func rebuildMenu() {
        menu.removeAllItems()
        add("Codex Battery" + (bucket?.planType.map { " · " + $0.capitalized } ?? ""))
        menu.addItem(.separator())
        if let bucket {
            let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
            for window in bucket.windows {
                let remaining = window.remaining.map { "\($0)%" } ?? L("Unknown")
                add(L("%@: %@ remaining", window.title, remaining) + (lastError == nil ? "" : L(" (previous data)")))
                if let reset = window.resetsAt { add(L("    Resets: ") + formatter.string(from: Date(timeIntervalSince1970: reset))) }
            }
        } else { add(lastError == nil ? L("Reading Codex usage…") : L("No usage data available")) }
        if let lastError { add(lastError) }
        if let date = lastUpdated {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            add(L("Last updated: ") + formatter.string(from: date))
        }
        menu.addItem(.separator())
        add(loading ? L("Refreshing…") : L("Refresh now"), action: loading ? nil : #selector(refresh))
        let display = NSMenu()
        let labels = [L("5-hour remaining quota"), L("Weekly remaining quota"), L("Lower remaining quota")]
        for (index, label) in labels.enumerated() {
            let item = add(label, action: #selector(changeMode(_:)), to: display, tag: index)
            item.state = displayMode == index ? .on : .off
        }
        add(L("Battery display")).submenu = display
        add(L("Charge color thresholds…"), action: #selector(configureColors))
        let frequency = NSMenu()
        for seconds in [15, 30, 60, 300] {
            let item = add(L("Every %d seconds", seconds), action: #selector(changeInterval(_:)), to: frequency, tag: seconds)
            item.state = Int(interval) == seconds ? .on : .off
        }
        add(L("Refresh interval")).submenu = frequency
        let loginItem = add(L("Launch at login"), action: #selector(toggleLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { add(L("Login item needs approval: open Settings"), action: #selector(loginSettings)) }
        menu.addItem(.separator())
        add(L("Open Codex"), action: #selector(openCodex))
        add(L("Quit Codex Battery"), action: #selector(quit)).keyEquivalent = "q"
    }
    @objc private func changeMode(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "displayMode"); updateIcon(); rebuildMenu()
    }
    @objc private func changeInterval(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "refreshInterval"); schedule(); rebuildMenu()
    }
    @objc private func configureColors() {
        let current = ColorThresholds(defaults: defaults)
        let alert = NSAlert()
        alert.messageText = L("Charge color thresholds")
        let explanation = L("Battery charge fill:\nRemaining ≥ green threshold: green\nRemaining < red threshold: red\nIn between: orange")
        alert.informativeText = explanation
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.addButton(withTitle: L("Restore defaults"))
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 80))
        let green = NSTextField(string: String(current.greenFrom))
        let red = NSTextField(string: String(current.redBelow))
        for (title, field, y) in [(L("Green starts at (%)"), green, 44.0), (L("Red below (%)"), red, 8.0)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 0, y: y + 2, width: 150, height: 22)
            field.frame = NSRect(x: 170, y: y, width: 90, height: 26)
            field.setAccessibilityLabel(title)
            form.addSubview(label); form.addSubview(field)
        }
        green.nextKeyView = red; red.nextKeyView = green
        alert.accessoryView = form
        alert.window.initialFirstResponder = green
        NSApp.activate(ignoringOtherApps: true)
        while true {
            let response = alert.runModal()
            if response == .alertThirdButtonReturn {
                green.stringValue = "70"; red.stringValue = "20"
                alert.informativeText = explanation
                continue
            }
            guard response == .alertFirstButtonReturn else { return }
            guard let redValue = Int(red.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let greenValue = Int(green.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let thresholds = ColorThresholds(redBelow: redValue, greenFrom: greenValue) else {
                alert.informativeText = L("Enter whole numbers from 0 to 100. The red threshold must be lower than the green threshold.\n\n") + explanation
                continue
            }
            defaults.set(thresholds.redBelow, forKey: "redBelow")
            defaults.set(thresholds.greenFrom, forKey: "greenFrom")
            updateIcon(); rebuildMenu()
            return
        }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = L("Could not change launch at login"); alert.informativeText = error.localizedDescription; alert.runModal()
        }
        rebuildMenu()
    }
    @objc private func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func openCodex() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
        else { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex")!) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateNow }
        quitting = true; timer?.invalidate()
        worker.async { [self] in
            client.stop()
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}

func runChecks() throws {
    func check(_ value: Bool) { precondition(value) }
    func decode(_ json: String) throws -> QuotaBucket? { try JSONDecoder().decode(Usage.self, from: Data(json.utf8)).codex }
    let fixture = #"{"rateLimits":{"primary":{"usedPercent":99},"secondary":null},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":2,"windowDurationMins":300,"resetsAt":1792866477},"secondary":{"usedPercent":25,"windowDurationMins":10080}}}}"#
    let bucket = try decode(fixture)!
    precondition(bucket.windows.map(\.remaining) == [98, 75])
    precondition(bucket.windows.map(\.title) == [L("%d-hour quota", 5), L("Weekly quota")])
    check(try decode(#"{"rateLimits":{"primary":{"usedPercent":0}}}"#)?.primary?.remaining == 100)
    check(try decode(#"{"rateLimits":{"primary":{"usedPercent":100}}}"#)?.primary?.remaining == 0)
    check(try decode(#"{"rateLimits":{"primary":{"usedPercent":101}}}"#)?.primary?.remaining == nil)
    check(try decode(#"{"rateLimits":{"primary":{"usedPercent":2}},"rateLimitsByLimitId":{}}"#) == nil)
    check(try decode(#"{"rateLimits":{"primary":null,"secondary":{"usedPercent":31,"windowDurationMins":10080}}}"#)?.windows.first?.remaining == 69)
    let colors = ColorThresholds.standard
    precondition([0, 19, 20, 69, 70, 100].map(colors.band) == [.red, .red, .orange, .orange, .green, .green])
    let custom = ColorThresholds(redBelow: 30, greenFrom: 80)!
    precondition([29, 30, 79, 80].map(custom.band) == [.red, .orange, .orange, .green])
    precondition(ColorThresholds(redBelow: 70, greenFrom: 20) == nil)
    precondition(ColorThresholds(redBelow: 20, greenFrom: 20) == nil)
    precondition(ColorThresholds(redBelow: -1, greenFrom: 70) == nil)
    precondition(ColorThresholds(redBelow: 20, greenFrom: 101) == nil)
    print("PASS: default/custom color boundaries and invalid thresholds")
    precondition(L("Green starts at (%)").contains("%"))
    switch Bundle.main.preferredLocalizations.first {
    case "zh-Hans": precondition(L("Weekly quota") == "每周额度")
    case "ja": precondition(L("Weekly quota") == "週間利用枠")
    default: precondition(L("Weekly quota") == "Weekly quota")
    }
    print("PASS: localized labels and literal percent signs")
    print("PASS: bucket selection, window labels, remaining %, missing data and bounds")
}

if CommandLine.arguments.contains("--self-test") {
    do { try runChecks() } catch { fputs("Check failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--check") {
    let client = UsageClient()
    do {
        for _ in 0..<2 {
            let bucket = try client.fetch()
            for window in bucket.windows { print(L("%@: %@ remaining", window.title, window.remaining.map { "\($0)%" } ?? L("Unknown"))) }
        }
        client.stop()
    } catch { client.stop(); fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
    let _ = NSApplication.shared
    let image = NSImage(size: NSSize(width: 370, height: 100), flipped: false) { _ in
        for dark in [false, true] {
            let y = dark ? 0 : 50
            NSColor(calibratedWhite: dark ? 0.10 : 0.96, alpha: 1).setFill()
            NSRect(x: 0, y: y, width: 370, height: 50).fill()
            for (i, value) in [100, 70, 69, 20, 19, 0].enumerated() {
                batteryImage(percent: value, dark: dark).draw(in: NSRect(x: 13 + i * 60, y: y + 14, width: 43, height: 22))
            }
        }
        return true
    }
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2220, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.cgContext.scaleBy(x: 6, y: 6)
    image.draw(in: NSRect(x: 0, y: 0, width: 370, height: 100))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
