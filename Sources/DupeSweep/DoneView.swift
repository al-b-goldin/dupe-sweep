import SwiftUI
import DupeEngine

struct DoneView: View {
    @Bindable var model: AppModel
    var report: TrashReport { model.report ?? TrashReport() }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: model.restored == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill").font(.system(size: 60)).foregroundStyle(Color.keepGreen)
            if let n = model.restored {
                Text("Put \(Display.count(n)) files back").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("They are exactly where they were before.").foregroundStyle(.secondary)
            } else {
                Text("Moved \(Display.count(report.moved.count)) files to the Trash").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("\(Format.bytes(report.bytesMoved)) comes back when you empty the Trash.").font(.title3).foregroundStyle(.secondary)
                if !report.skipped.isEmpty {
                    Text("\(report.skipped.count) files were left alone because they changed after the scan.").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button("Show Trash") { model.openTrash() }
                if model.restored == nil && !report.moved.isEmpty { Button("Put Everything Back") { model.undo() } }
                Button("Done") { model.startOver() }.buttonStyle(PrimaryButtonStyle())
            }.controlSize(.large).padding(.top, 6)
            Spacer()
            VStack(spacing: 6) {
                Text("Dupe Sweep is free. If it saved you some space and some time, a coffee is lovely.").font(.callout).foregroundStyle(.secondary)
                Link(destination: Config.coffeeURL) { Label("Buy me a coffee", systemImage: "cup.and.saucer.fill") }
            }.padding(.bottom, 8)
        }
        .padding(28)
    }
}
