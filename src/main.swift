import AppKit
import Carbon

class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum Mode { case apps, files, folder(String, String) }

class Handler: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: Panel!
    var container: NSView!
    var prompt: NSTextField!
    var input: NSTextField!
    var count: NSTextField!
    var scroll: NSScrollView!
    var table: NSTableView!
    var monitor: Any?

    var config = Config.load()
    var mode: Mode = .apps
    var apps: [URL] = []
    var files: [URL] = []
    var items: [URL] = []
    var selected = 0

    var bg: NSColor { let c = config.color(config.bg); return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    var fg: NSColor { let c = config.color(config.fg); return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    var hi: NSColor { let c = config.color(config.hi); return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    var w: CGFloat { CGFloat(config.width) }
    var h: CGFloat = 28
    var p: CGFloat { CGFloat(config.padding) }
    var r: CGFloat { CGFloat(config.radius) }
    var maxrows: Int { config.rows }

    func applicationDidFinishLaunching(_ n: Notification) {
        if !Config.exists() { Config.create() }
        loadApps()
        setupWindow()
        setupHotkey()
        setupKeys()
        setupGlobal()
        NSApp.setActivationPolicy(.accessory)
    }

    func setupGlobal() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func loadApps() {
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { continue }
            apps.append(contentsOf: urls.filter { $0.pathExtension == "app" })
        }
        apps.sort { name($0).lowercased() < name($1).lowercased() }
    }

    func name(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    func setupHotkey() {
        let id = EventHotKeyID(signature: 0x4D454E55, id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(49, UInt32(controlKey), id, GetApplicationEventTarget(), 0, &ref)
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ptr -> OSStatus in
            Unmanaged<Handler>.fromOpaque(ptr!).takeUnretainedValue().toggle()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    var folderKeys: [String] = []

    func setupKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.window.isVisible else { return e }
            switch e.keyCode {
            case 53: self.hide(); return nil
            case 125: self.move(1); return nil
            case 126: self.move(-1); return nil
            case 36, 76: self.launch(); return nil
            case 48: self.complete(); return nil
            case 51:
                if self.input.stringValue.isEmpty {
                    if case .folder = self.mode {
                        self.switchApps()
                        return nil
                    }
                }
                return e
            case 44:
                if e.characters == "/" {
                    if case .apps = self.mode, self.input.stringValue.isEmpty {
                        self.switchFolder()
                        return nil
                    }
                }
                return e
            case 47:
                if e.characters == ">" {
                    if case .folder(let name, _) = self.mode, name.isEmpty, self.input.stringValue.isEmpty {
                        self.switchApps()
                        return nil
                    }
                }
                return e
            default: return e
            }
        }
    }

    func switchApps() {
        mode = .apps
        prompt.stringValue = ">"
        input.stringValue = ""
        input.placeholderString = nil
        items = apps
        folderKeys = []
        selected = 0
        table.reloadData()
        count.stringValue = "\(items.count)"
        resize()
    }

    func switchFolder() {
        mode = .folder("", "")
        prompt.stringValue = "/"
        input.stringValue = ""
        input.placeholderString = "search folders"
        folderKeys = config.folders.keys.sorted()
        items = folderKeys.compactMap { key in
            guard let path = config.folders[key] else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        selected = 0
        table.reloadData()
        count.stringValue = "\(items.count)"
        resize()
    }

    func setupWindow() {
        window = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .utilityWindow

        container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = bg.cgColor
        container.layer?.cornerRadius = r
        container.layer?.masksToBounds = true
        window.contentView = container

        let header = NSView()
        container.addSubview(header)

        prompt = NSTextField(labelWithString: ">")
        prompt.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        prompt.textColor = NSColor(white: 0.5, alpha: 1)
        prompt.frame = NSRect(x: p, y: 4, width: 14, height: 16)
        header.addSubview(prompt)

        input = NSTextField()
        input.delegate = self
        input.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        input.textColor = .white
        input.backgroundColor = .clear
        input.isBordered = false
        input.focusRingType = .none
        input.frame = NSRect(x: p + 14, y: 4, width: w - p - 60, height: 16)
        header.addSubview(input)

        count = NSTextField(labelWithString: "")
        count.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        count.textColor = NSColor(white: 0.35, alpha: 1)
        count.alignment = .right
        count.frame = NSRect(x: w - 44 - p, y: 5, width: 44, height: 14)
        header.addSubview(count)

        table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = nil
        table.rowHeight = h
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.target = self
        table.action = #selector(clicked)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("n")))
        table.tableColumns[0].width = w
        table.dataSource = self
        table.delegate = self

        scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        container.addSubview(scroll)

        header.frame = NSRect(x: 0, y: CGFloat(maxrows) * h, width: w, height: h)
    }

    @objc func clicked() {
        if table.clickedRow >= 0 {
            selected = table.clickedRow
            launch()
        }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selected = max(0, min(selected + d, items.count - 1))
        table.reloadData()
        table.scrollRowToVisible(selected)
    }

    func complete() {
        guard selected >= 0, selected < items.count else { return }
        let url = items[selected]
        if url.hasDirectoryPath {
            input.stringValue = "/" + name(url) + "/"
            parse()
        }
    }

    func toggle() { window.isVisible ? hide() : show() }

    func show() {
        input.stringValue = ""
        mode = .apps
        items = apps
        selected = 0
        prompt.stringValue = ">"
        table.reloadData()
        count.stringValue = "\(items.count)"
        resize()

        let screen = NSScreen.main!
        let wh = window.frame.height
        let x = screen.frame.midX - w / 2
        let y = screen.frame.midY - wh / 2 + 100
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(input)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }) {
            self.window.orderOut(nil)
        }
    }

    func resize() {
        let rows = min(items.count, maxrows)
        let lh = CGFloat(rows) * h
        let pad: CGFloat = rows < 3 ? r : 0
        let total = h + lh + pad
        container.subviews[0].frame = NSRect(x: 0, y: lh + pad, width: w, height: h)
        scroll.frame = NSRect(x: 0, y: pad, width: w, height: lh)
        window.setContentSize(NSSize(width: w, height: total))
        window.invalidateShadow()
    }

    @objc func launch() {
        guard selected >= 0, selected < items.count else { return }
        let url = items[selected]

        if case .folder(let name, _) = mode, name.isEmpty {
            if selected < folderKeys.count {
                let key = folderKeys[selected]
                if let path = config.folders[key] {
                    let expanded = (path as NSString).expandingTildeInPath
                    mode = .folder(key, expanded)
                    prompt.stringValue = "/" + key
                    input.stringValue = ""
                    input.placeholderString = nil
                    loadFolder(expanded, query: "")
                    selected = 0
                    table.reloadData()
                    count.stringValue = "\(items.count)"
                    resize()
                    return
                }
            } else if url.hasDirectoryPath {
                let folderName = url.lastPathComponent
                mode = .folder(folderName, url.path)
                prompt.stringValue = "/" + folderName
                input.stringValue = ""
                input.placeholderString = nil
                loadFolder(url.path, query: "")
                selected = 0
                table.reloadData()
                count.stringValue = "\(items.count)"
                resize()
                return
            }
        }

        if url.hasDirectoryPath {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        } else {
            NSWorkspace.shared.open(url)
        }
        hide()
    }

    func controlTextDidChange(_ n: Notification) {
        parse()
    }

    func parse() {
        let raw = input.stringValue
        let q = raw.lowercased()

        if q == "/setup" {
            Config.create()
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.path))
            hide()
            return
        }

        if q == "/reload" {
            config = Config.load()
            container.layer?.backgroundColor = bg.cgColor
            hide()
            return
        }

        if case .folder(let name, let path) = mode {
            if name.isEmpty {
                if q.isEmpty {
                    folderKeys = config.folders.keys.sorted()
                    items = folderKeys.compactMap { key in
                        guard let p = config.folders[key] else { return nil }
                        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                    }
                } else {
                    searchFolders(q)
                }
            } else {
                loadFolder(path, query: q)
            }
        } else if q.hasPrefix("f ") {
            let query = String(q.dropFirst(2))
            mode = .files
            prompt.stringValue = "f"
            searchFiles(query)
        } else {
            mode = .apps
            prompt.stringValue = ">"
            items = q.isEmpty ? apps : apps.filter { fuzzy(q, name($0).lowercased()) }.sorted { score(q, name($0).lowercased()) > score(q, name($1).lowercased()) }
        }

        selected = 0
        table.reloadData()
        count.stringValue = "\(items.count)"
        resize()
    }

    func loadFolder(_ path: String, query: String) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey]) else {
            items = []
            return
        }
        let sorted = urls.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { name($0).lowercased() < name($1).lowercased() }
        items = query.isEmpty ? sorted : sorted.filter { fuzzy(query, name($0).lowercased()) }.sorted { score(query, name($0).lowercased()) > score(query, name($1).lowercased()) }
    }

    func searchFolders(_ query: String) {
        var results: [URL] = []
        folderKeys = []
        let paths = config.folders.values.map { ($0 as NSString).expandingTildeInPath }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
                for u in urls where u.hasDirectoryPath && !u.lastPathComponent.hasPrefix(".") && u.pathExtension != "app" {
                    if fuzzy(query, u.lastPathComponent.lowercased()) {
                        results.append(u)
                    }
                }
            }
        }
        items = results.sorted { score(query, $0.lastPathComponent.lowercased()) > score(query, $1.lastPathComponent.lowercased()) }
    }

    func searchFiles(_ query: String) {
        guard !query.isEmpty else { items = []; return }
        var results: [URL] = []
        for path in config.search {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if results.count > 100 { break }
                    if fuzzy(query, fileURL.lastPathComponent.lowercased()) {
                        results.append(fileURL)
                    }
                }
            }
        }
        items = results.sorted { score(query, $0.lastPathComponent.lowercased()) > score(query, $1.lastPathComponent.lowercased()) }
    }

    func fuzzy(_ n: String, _ h: String) -> Bool {
        var i = h.startIndex
        for c in n { guard let f = h[i...].firstIndex(of: c) else { return false }; i = h.index(after: f) }
        return true
    }

    func score(_ n: String, _ h: String) -> Int {
        var s = 0, i = h.startIndex, p: Character? = nil
        for c in n {
            guard let f = h[i...].firstIndex(of: c) else { return 0 }
            if f == h.startIndex || p == " " || p == "-" || p == "_" { s += 10 }
            if f == i { s += 5 }
            s += 1; p = h[f]; i = h.index(after: f)
        }
        return s
    }

    func numberOfRows(in t: NSTableView) -> Int { items.count }

    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let sel = row == selected
        let url = items[row]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        if sel {
            v.wantsLayer = true
            v.layer?.backgroundColor = hi.cgColor
        }
        var label = name(url)
        if case .folder(let n, _) = mode {
            if n.isEmpty {
                if row < folderKeys.count {
                    label = folderKeys[row]
                } else {
                    label = "/" + label
                }
            } else if url.hasDirectoryPath {
                label = "/" + label
            }
        }
        if case .files = mode, url.hasDirectoryPath { label = "/" + label }
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: p, y: 6, width: w - p * 2, height: 16)
        l.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        l.textColor = sel ? .white : fg
        v.addSubview(l)
        return v
    }
}

let app = NSApplication.shared
let handler = Handler()
app.delegate = handler
app.run()
