import SwiftUI
import DupeEngine

struct DoneView: View {
    @Bindable var model: AppModel
    var report: TrashReport { model.report ?? TrashReport() }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: model.restored != nil ? "arrow.uturn.backward.circle.fill" : model.nothingMoved ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundStyle(model.restored == nil && model.nothingMoved ? Color.orange : Color.keepGreen)
            if let n = model.restored {
                Text("Put \(Display.count(n)) files back").font(.system(size: 26, weight: .semibold, design: .rounded))
                if n > 0 { Text("They are exactly where they were before.").foregroundStyle(.secondary) }
                if model.restoreFailed > 0 {
                    Text("\(Display.count(model.restoreFailed)) \(model.restoreFailed == 1 ? "file" : "files") could not be put back: a file with the same name is in that place now, or the Trash was emptied. Click Show Trash to look for \(model.restoreFailed == 1 ? "it" : "them").")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            } else if model.nothingMoved {
                Text("No files were moved").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("\(report.skipped.count) files were left alone because they changed after the scan. Scan again to see the folders as they are now.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("Moved \(Display.count(report.moved.count)) files to the Trash").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("\(Format.bytes(report.bytesMoved)) comes back when you empty the Trash.").font(.title3).foregroundStyle(.secondary)
                if !report.skipped.isEmpty {
                    Text("\(report.skipped.count) files were left alone because they changed after the scan.").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                if !model.nothingMoved { Button("Show Trash") { model.openTrash() } }
                if model.restored == nil && !report.moved.isEmpty { Button("Put Everything Back") { model.undo() } }
                Button(model.nothingMoved ? "Scan Again" : "Done") { if model.nothingMoved { model.scanAgain() } else { model.startOver() } }.buttonStyle(PrimaryButtonStyle())
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
