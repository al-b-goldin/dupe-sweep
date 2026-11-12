import SwiftUI
import DupeEngine

struct ScanningView: View {
    @Bindable var model: AppModel
    var p: ScanProgress { model.progress }

    func step(_ title: String, _ detail: String, _ n: Int) -> some View {
        let cur = p.phase.rawValue
        let state = cur > n ? "done" : cur == n ? "now" : "later"
        return HStack(spacing: 12) {
            Group {
                if state == "done" { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.keepGreen) }
                else if state == "now" { ProgressView().controlSize(.small) }
                else { Image(systemName: "circle").foregroundStyle(.tertiary) }
            }.frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(state == "later" ? .secondary : .primary)
                if state != "later" { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(p.phase == .reading ? "Comparing file contents" : "Looking for duplicates").font(.system(size: 26, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 16) {
                step("Finding files", "\(Display.count(p.filesFound)) files, \(Format.bytes(p.bytesFound)) so far", 0)
                step("Finding files that could match", "\(Display.count(p.candidateFiles)) share a size with another file", 1)
                step("Comparing what is inside", p.readTotal == 0 ? "Starting…" : "\(Format.bytes(p.readBytes)) of \(Format.bytes(p.readTotal))", 2)
                step("Working out what to keep", "Almost there", 3)
            }
            if p.phase == .reading, p.readTotal > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    BrandProgress(value: Double(p.readBytes), total: Double(max(p.readTotal, 1)))
                    HStack {
                        Text("\(Int(100 * Double(p.readBytes) / Double(max(p.readTotal, 1))))%").monospacedDigit()
                        Spacer()
                        if p.bytesPerSecond > 0 { Text("\(Format.bytes(Int64(p.bytesPerSecond)))/s") }
                        if let e = p.etaSeconds { Text("about \(Format.duration(e)) left") }
                    }.font(.callout).foregroundStyle(.secondary)
                    Text(p.currentName).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            } else if p.phase == .finding {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().progressViewStyle(.linear).tint(.brand)
                    Text(p.currentName).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            HStack {
                Text("This runs quietly in the background. You can keep using your Mac.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelScan() }.controlSize(.large)
            }
        }
        .padding(32)
    }
}
