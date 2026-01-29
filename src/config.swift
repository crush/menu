import Foundation

struct Config {
    var bg: String = "#1e1e22"
    var fg: String = "#a0a0a0"
    var hi: String = "#3d6a99"
    var prompt: String = "#666666"
    var theme: String = "dark"
    var radius: Int = 10
    var padding: Int = 8
    var rows: Int = 12
    var width: Int = 500
    var icons: Bool = false
    var hotkey: String = "ctrl+space"
    var escback: Bool = true
    var folders: [String: String] = [
        "apps": "/Applications",
        "downloads": "~/Downloads",
        "documents": "~/Documents",
        "desktop": "~/Desktop"
    ]
    var search: [String] = ["~/code", "~/Documents", "~/Desktop"]

    static let path = ("~/.config/menu/config" as NSString).expandingTildeInPath

    static func load() -> Config {
        var config = Config()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return config
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "bg": config.bg = val
            case "fg": config.fg = val
            case "hi": config.hi = val
            case "prompt": config.prompt = val
            case "theme": config.theme = val
            case "radius": config.radius = Int(val) ?? config.radius
            case "padding": config.padding = Int(val) ?? config.padding
            case "rows": config.rows = Int(val) ?? config.rows
            case "width": config.width = Int(val) ?? config.width
            case "icons": config.icons = val == "true"
            case "hotkey": config.hotkey = val
            case "escback": config.escback = val == "true"
            case "search": config.search.append((val as NSString).expandingTildeInPath)
            default:
                if key.hasPrefix("folder.") {
                    let name = String(key.dropFirst(7))
                    config.folders[name] = val
                }
            }
        }
        return config
    }

    static func create() {
        let dir = ("~/.config/menu" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = """
# menu config

# theme (dark, nord, dracula, gruvbox, catppuccin, solarized, monokai, tokyo)
theme=dark

# colors (hex) - override theme colors
bg=#1e1e22
fg=#a0a0a0
hi=#3d6a99
prompt=#666666

# ui
radius=10
padding=8
rows=12
width=500

# features
icons=false

# hotkey
hotkey=ctrl+space

# escape behavior (true = go back first, false = always close)
escback=true

# folders (access with /name)
folder.apps=/Applications
folder.downloads=~/Downloads
folder.documents=~/Documents
folder.desktop=~/Desktop

# file search paths (access with f query)
search=~/code
search=~/Documents
search=~/Desktop
"""
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func save(_ config: Config) {
        let content = """
# menu config

# theme
theme=\(config.theme)

# colors (hex)
bg=\(config.bg)
fg=\(config.fg)
hi=\(config.hi)
prompt=\(config.prompt)

# ui
radius=\(config.radius)
padding=\(config.padding)
rows=\(config.rows)
width=\(config.width)

# features
icons=\(config.icons)

# hotkey
hotkey=\(config.hotkey)

# escape behavior
escback=\(config.escback)

# folders (access with /name)
\(config.folders.map { "folder.\($0.key)=\($0.value)" }.joined(separator: "\n"))

# file search paths (access with f query)
\(config.search.map { "search=\($0)" }.joined(separator: "\n"))
"""
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func color(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let n = UInt64(h, radix: 16) else {
            return (0.12, 0.12, 0.14)
        }
        return (
            CGFloat((n >> 16) & 0xFF) / 255,
            CGFloat((n >> 8) & 0xFF) / 255,
            CGFloat(n & 0xFF) / 255
        )
    }
}
