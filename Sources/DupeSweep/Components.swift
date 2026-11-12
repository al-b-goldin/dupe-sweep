import SwiftUI
import AppKit
import DupeEngine

extension Color {
    static let brand = Color(red: 0.12, green: 0.55, blue: 0.62)
    static let keepGreen = Color(red: 0.16, green: 0.60, blue: 0.34)
    static let removeRed = Color(red: 0.80, green: 0.27, blue: 0.22)
}

struct Tile: View {
    let value: String, label: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Badge: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct FolderChip: View {
    let path: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").foregroundStyle(Color.brand)
            Text(Display.short(path)).lineLimit(1).truncationMode(.middle)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Remove")
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

struct CoffeeFooter: View {
    var body: some View {
        HStack {
            Label("Everything stays on your Mac. Nothing is uploaded.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Link(destination: Config.coffeeURL) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill").font(.caption.weight(.medium))
            }
        }
    }
}

enum Display {
    static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
    static let date: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f }()
    static func icon(_ path: String) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 28, height: 28); return i
    }
    static func count(_ n: Int) -> String { n.formatted() }
}

/// The big colored button. Drawn by hand so it looks the same everywhere, including in screenshots.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .brand
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 9).padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 10).fill(enabled ? color : Color.gray.opacity(0.45)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A progress bar drawn by hand in the brand color.
struct BrandProgress: View {
    let value: Double, total: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.brand).frame(width: max(8, g.size.width * min(1, value / max(total, 1))))
            }
        }
        .frame(height: 10)
    }
}
