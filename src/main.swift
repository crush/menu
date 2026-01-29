import AppKit
import Carbon

class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum Mode { case apps, files, folder(String, String), themes }

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
    var appNames: [URL: String] = [:]
    var files: [URL] = []
    var folders: [URL] = []
    var items: [URL] = []
    var selected = 0

    var bgColor: NSColor!
    var fgColor: NSColor!
    var hiColor: NSColor!
    var promptCol: NSColor!

    func cacheColors() {
        let b = config.color(config.bg)
        let f = config.color(config.fg)
        let h = config.color(config.hi)
        let p = config.color(config.prompt)
        bgColor = NSColor(red: b.r, green: b.g, blue: b.b, alpha: 1)
        fgColor = NSColor(red: f.r, green: f.g, blue: f.b, alpha: 1)
        hiColor = NSColor(red: h.r, green: h.g, blue: h.b, alpha: 1)
        promptCol = NSColor(red: p.r, green: p.g, blue: p.b, alpha: 1)
    }
    var themes: [Theme] = []
    var originalConfig: Config?
    var previousMode: Mode = .apps
    var searchWork: DispatchWorkItem?
    var w: CGFloat { CGFloat(config.width) }
    var h: CGFloat = 28
    var p: CGFloat { CGFloat(config.padding) }
    var r: CGFloat { CGFloat(config.radius) }
    var maxrows: Int { config.rows }

    func applicationDidFinishLaunching(_ n: Notification) {
        if !Config.exists() { Config.create() }
        cacheColors()
        loadApps()
        loadFolders()
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
        for app in apps {
            appNames[app] = name(app).lowercased()
        }
        apps.sort { (appNames[$0] ?? "") < (appNames[$1] ?? "") }
    }

    func loadFolders() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            var result: [URL] = []
            let skip = Set([".git", "node_modules", ".build", "Pods", "DerivedData", ".svn", "vendor", "Library", ".Trash", "Caches", "__pycache__", ".venv", "venv", ".npm", ".cache"])
            let paths = self.config.folders.values.map { ($0 as NSString).expandingTildeInPath }
            for path in paths {
                let url = URL(fileURLWithPath: path)
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                while let u = enumerator.nextObject() as? URL {
                    let name = u.lastPathComponent
                    if skip.contains(name) { enumerator.skipDescendants(); continue }
                    guard u.hasDirectoryPath && u.pathExtension != "app" else { continue }
                    result.append(u)
                }
            }
            DispatchQueue.main.async {
                self.folders = result
            }
        }
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
            case 53:
                if self.config.escback {
                    if case .themes = self.mode {
                        self.restoreAndGoBack()
                        return nil
                    }
                    if case .folder = self.mode {
                        self.switchApps()
                        return nil
                    }
                }
                self.hide()
                return nil
            case 125: self.move(1); return nil
            case 126: self.move(-1); return nil
            case 36, 76: self.launch(); return nil
            case 48: self.complete(); return nil
            case 51:
                if self.input.stringValue.isEmpty {
                    if case .themes = self.mode {
                        self.restoreAndGoBack()
                        return nil
                    }
                    if case .folder = self.mode {
                        self.switchApps()
                        return nil
                    }
                }
                return e
            case 44:
                if e.characters == "/" {
                    if self.input.stringValue.isEmpty {
                        if case .apps = self.mode {
                            self.switchFolder()
                            return nil
                        }
                        if case .themes = self.mode {
                            self.restoreConfig()
                            self.switchFolder()
                            return nil
                        }
                    }
                }
                return e
            case 47:
                if e.characters == ">" {
                    if self.input.stringValue.isEmpty {
                        if case .folder(let name, _) = self.mode, name.isEmpty {
                            self.switchApps()
                            return nil
                        }
                        if case .themes = self.mode {
                            self.restoreConfig()
                            self.switchApps()
                            return nil
                        }
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

    func switchThemes() {
        originalConfig = config
        previousMode = mode
        mode = .themes
        prompt.stringValue = ":"
        input.stringValue = ""
        input.placeholderString = "select theme"
        themes = Theme.all()
        items = []
        selected = 0
        table.reloadData()
        count.stringValue = "\(themes.count)"
        resize()
    }

    func applyTheme() {
        cacheColors()
        container.layer?.backgroundColor = bgColor.cgColor
        prompt.textColor = promptCol
        table.reloadData()
    }

    func restoreConfig() {
        if let orig = originalConfig {
            config = orig
            applyTheme()
        }
        originalConfig = nil
    }

    func restoreAndGoBack() {
        restoreConfig()
        switch previousMode {
        case .apps: switchApps()
        case .folder(let n, let p):
            if n.isEmpty { switchFolder() }
            else {
                mode = .folder(n, p)
                prompt.stringValue = "/" + n
                input.stringValue = ""
                input.placeholderString = nil
                loadFolder(p, query: "")
                selected = 0
                table.reloadData()
                count.stringValue = "\(items.count)"
                resize()
            }
        case .files: switchApps()
        case .themes: switchApps()
        }
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
        container.layer?.backgroundColor = bgColor.cgColor
        container.layer?.cornerRadius = r
        container.layer?.masksToBounds = true
        window.contentView = container

        let header = NSView()
        container.addSubview(header)

        prompt = NSTextField(labelWithString: ">")
        prompt.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        prompt.textColor = promptCol
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
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        container.addSubview(scroll)

        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMouse(e)
            return e
        }

        header.frame = NSRect(x: 0, y: CGFloat(maxrows) * h, width: w, height: h)
    }

    @objc func clicked() {
        if table.clickedRow >= 0 && table.clickedRow < itemCount() {
            selected = table.clickedRow
            launch()
        }
    }

    func handleMouse(_ event: NSEvent) {
        guard window.isVisible else { return }
        let loc = scroll.convert(event.locationInWindow, from: nil)
        let tableLoc = table.convert(loc, from: scroll)
        let row = table.row(at: tableLoc)
        if row >= 0 && row < itemCount() && row != selected {
            selected = row
            table.reloadData()
            if case .themes = mode, selected < themes.count {
                let theme = themes[selected]
                config.bg = theme.bg
                config.fg = theme.fg
                config.hi = theme.hi
                config.prompt = theme.prompt
                applyTheme()
            }
        }
    }

    func move(_ d: Int) {
        let total = itemCount()
        guard total > 0 else { return }
        selected = max(0, min(selected + d, total - 1))
        table.reloadData()
        table.scrollRowToVisible(selected)
        if case .themes = mode, selected < themes.count {
            let theme = themes[selected]
            config.bg = theme.bg
            config.fg = theme.fg
            config.hi = theme.hi
            config.prompt = theme.prompt
            applyTheme()
        }
    }

    func itemCount() -> Int {
        if case .themes = mode { return themes.count }
        return items.count
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
        input.placeholderString = nil
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
        if case .themes = mode, let orig = originalConfig {
            config = orig
            applyTheme()
        }
        originalConfig = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }) {
            self.window.orderOut(nil)
        }
    }

    func resize() {
        let rows = min(itemCount(), maxrows)
        let lh = CGFloat(rows) * h
        let inset: CGFloat = 12
        let total = h + lh + inset
        container.subviews[0].frame = NSRect(x: 0, y: lh + inset, width: w, height: h)
        scroll.frame = NSRect(x: 0, y: 0, width: w, height: lh + inset)
        window.setContentSize(NSSize(width: w, height: total))
        window.invalidateShadow()
    }

    @objc func launch() {
        if case .themes = mode {
            guard selected >= 0, selected < themes.count else { return }
            let theme = themes[selected]
            config.theme = theme.name
            Theme.apply(theme, to: &config)
            originalConfig = nil
            hide()
            return
        }

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
        let cmd = q.trimmingCharacters(in: .whitespaces)

        if cmd == ":setup" {
            Config.create()
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.path))
            hide()
            return
        }

        if cmd == ":reload" {
            config = Config.load()
            applyTheme()
            hide()
            return
        }

        if cmd == ":theme" {
            switchThemes()
            return
        }

        if case .themes = mode {
            themes = q.isEmpty ? Theme.all() : Theme.all().filter { fuzzy(q, $0.name.lowercased()) }
            selected = 0
            table.reloadData()
            count.stringValue = "\(themes.count)"
            resize()
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
            if q.isEmpty {
                items = apps
            } else {
                let scored = apps.compactMap { url -> (URL, Int)? in
                    guard let n = appNames[url] else { return nil }
                    guard n.contains(q) || fuzzy(q, n) else { return nil }
                    return (url, score(q, n))
                }
                items = scored.sorted { $0.1 > $1.1 }.map { $0.0 }
            }
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
        folderKeys = config.folders.keys.filter { $0.lowercased().contains(query) }.sorted()
        for key in folderKeys {
            if let path = config.folders[key] {
                results.append(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            }
        }
        let matched = folders.filter { $0.lastPathComponent.lowercased().contains(query) }
        results.append(contentsOf: matched.prefix(50))
        items = results
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

    func numberOfRows(in t: NSTableView) -> Int { itemCount() }

    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let v: NSTableCellView
        if let reused = t.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            v = reused
        } else {
            v = NSTableCellView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            v.identifier = id
            v.wantsLayer = true
            let l = NSTextField(labelWithString: "")
            l.frame = NSRect(x: p, y: 6, width: w - p * 2, height: 16)
            l.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            l.isBordered = false
            l.drawsBackground = false
            l.isEditable = false
            l.tag = 1
            v.addSubview(l)
        }

        let sel = row == selected
        v.layer?.backgroundColor = sel ? hiColor.cgColor : nil

        var label: String
        if case .themes = mode {
            label = themes[row].name
        } else {
            let url = items[row]
            label = name(url)
            if case .folder(let n, _) = mode {
                if n.isEmpty && input.stringValue.isEmpty && row < folderKeys.count {
                    label = folderKeys[row]
                }
            }
            if case .files = mode, url.hasDirectoryPath { label = "/" + label }
        }

        if let l = v.viewWithTag(1) as? NSTextField {
            l.stringValue = label
            l.textColor = sel ? .white : fgColor
        }
        return v
    }
}

let app = NSApplication.shared
let handler = Handler()
app.delegate = handler
app.run()
