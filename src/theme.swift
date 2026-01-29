import Foundation

struct Theme {
    let name: String
    let bg: String
    let fg: String
    let hi: String
    let prompt: String

    static let builtIn: [Theme] = [
        Theme(name: "dark", bg: "#1e1e22", fg: "#a0a0a0", hi: "#3d6a99", prompt: "#666666"),
        Theme(name: "nord", bg: "#2e3440", fg: "#d8dee9", hi: "#5e81ac", prompt: "#4c566a"),
        Theme(name: "dracula", bg: "#282a36", fg: "#f8f8f2", hi: "#bd93f9", prompt: "#6272a4"),
        Theme(name: "gruvbox", bg: "#282828", fg: "#ebdbb2", hi: "#458588", prompt: "#928374"),
        Theme(name: "catppuccin", bg: "#1e1e2e", fg: "#cdd6f4", hi: "#89b4fa", prompt: "#6c7086"),
        Theme(name: "solarized", bg: "#002b36", fg: "#839496", hi: "#268bd2", prompt: "#586e75"),
        Theme(name: "monokai", bg: "#272822", fg: "#f8f8f2", hi: "#a6e22e", prompt: "#75715e"),
        Theme(name: "tokyo", bg: "#1a1b26", fg: "#a9b1d6", hi: "#7aa2f7", prompt: "#565f89")
    ]

    static let path = ("~/.config/menu/themes" as NSString).expandingTildeInPath

    static func all() -> [Theme] {
        var themes = builtIn
        if let custom = loadCustom() {
            themes.append(contentsOf: custom)
        }
        return themes
    }

    static func loadCustom() -> [Theme]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var themes: [Theme] = []
        var current: (name: String, bg: String, fg: String, hi: String, prompt: String)? = nil

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let c = current {
                    themes.append(Theme(name: c.name, bg: c.bg, fg: c.fg, hi: c.hi, prompt: c.prompt))
                }
                let name = String(trimmed.dropFirst().dropLast())
                current = (name: name, bg: "#1e1e22", fg: "#a0a0a0", hi: "#3d6a99", prompt: "#666666")
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, current != nil else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "bg": current?.bg = val
            case "fg": current?.fg = val
            case "hi": current?.hi = val
            case "prompt": current?.prompt = val
            default: break
            }
        }

        if let c = current {
            themes.append(Theme(name: c.name, bg: c.bg, fg: c.fg, hi: c.hi, prompt: c.prompt))
        }

        return themes.isEmpty ? nil : themes
    }

    static func find(_ name: String) -> Theme? {
        all().first { $0.name.lowercased() == name.lowercased() }
    }

    static func apply(_ theme: Theme, to config: inout Config) {
        config.bg = theme.bg
        config.fg = theme.fg
        config.hi = theme.hi
        config.prompt = theme.prompt
        Config.save(config)
    }

    static func createExample() {
        let dir = ("~/.config/menu" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = """
# custom themes
# format: [name] then bg/fg/hi/prompt colors

[custom]
bg=#1a1a1a
fg=#ffffff
hi=#ff6600
prompt=#888888
"""
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
