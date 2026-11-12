import SwiftUI
import DupeEngine

struct ResultsView: View {
    @Bindable var model: AppModel
    @State private var confirm = false
    var r: ScanResult { model.result ?? ScanResult(sets: [], filesScanned: 0, bytesScanned: 0) }

    var body: some View {
        VStack(spacing: 0) {
            if model.plans.isEmpty { empty } else { content }
        }
        .alert("Move \(Display.count(model.removeCount)) files to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { model.moveToTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("That is \(Format.bytes(model.removeBytes)). Nothing is deleted for good: you can put the files back from the Trash. At least one copy of every file stays where it is.")
        }
        .overlay { if let t = model.trashProgress { TrashingOverlay(done: t.done, total: t.total) } }
    }

    var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Color.keepGreen)
            Text("No duplicates found").font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Checked \(Display.count(r.filesScanned)) files (\(Format.bytes(r.bytesScanned))) and none of them were copies of each other.").foregroundStyle(.secondary)
            if r.iCloudOnlySkipped > 0 { Text("\(r.iCloudOnlySkipped) files that live only in iCloud were not compared.").font(.callout).foregroundStyle(.secondary) }
            Button("Check Something Else") { model.startOver() }.controlSize(.large)
            Spacer()
            CoffeeFooter().padding(.horizontal, 28).padding(.bottom, 16)
        }
    }

    var content: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Found \(Display.count(model.plans.count)) sets of duplicates").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Start Over") { model.startOver() }
                }
                Text("Checked \(Display.count(r.filesScanned)) files (\(Format.bytes(r.bytesScanned))) in \(Format.duration(r.seconds)).")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Tile(value: Format.bytes(model.freedBytes), label: "you get back", tint: .keepGreen)
                    Tile(value: Display.count(model.removeCount), label: "extra copies go to the Trash")
                    Tile(value: Display.count(model.activeSets), label: "originals stay put")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Which copy should stay?").font(.headline)
                        Picker("", selection: $model.rule) { ForEach(KeepRule.allCases) { Text($0.title).tag($0) } }
                            .labelsHidden().frame(maxWidth: 330)
                    }
                    Text(model.rule.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                pinnedRow
                if model.freedBytes < model.removeBytes {
                    Label("Some copies share disk space with their originals, so removing them returns less than their size.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.plans) { p in SetRow(model: model, plan: p); Divider() }
                }
            }
            Divider()
            bottomBar
        }
    }

    var pinnedRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Always keep copies in:").font(.callout).foregroundStyle(.secondary).padding(.top, 5)
            FlowLayout(spacing: 6) {
                ForEach(model.pinned, id: \.self) { path in FolderChip(path: path) { model.unpin(path) } }
                Button { model.pick() } label: { Label(model.pinned.isEmpty ? "Choose a folder…" : "Add", systemImage: "plus.circle") }.buttonStyle(.borderless)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in model.pin(urls); return true }
    }

    var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Display.count(model.removeCount)) files · \(Format.bytes(model.removeBytes)) will move to the Trash").font(.headline)
                Text("Click a copy in the list to keep that one instead.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.overrides.isEmpty || !model.skipped.isEmpty { Button("Reset My Choices") { model.resetChoices() } }
            Button { confirm = true } label: { Text("Move to Trash…").font(.headline).padding(.horizontal, 10) }
                .buttonStyle(PrimaryButtonStyle(color: .removeRed)).disabled(model.removeCount == 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.bar)
    }
}

struct TrashingOverlay: View {
    let done: Int, total: Int
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 12) {
                Text("Moving to the Trash…").font(.headline)
                BrandProgress(value: Double(done), total: Double(max(total, 1))).frame(width: 260)
                Text("\(done) of \(total)").font(.callout).foregroundStyle(.secondary)
            }
            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct SetRow: View {
    @Bindable var model: AppModel
    let plan: SetPlan
    var open: Bool { model.expanded.contains(plan.id) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if open { model.expanded.remove(plan.id) } else { model.expanded.insert(plan.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 12)
                    Image(nsImage: Display.icon(plan.set.copies[0].path))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.set.copies[0].name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text("\(plan.set.copies.count) copies · \(Format.bytes(plan.set.size)) each").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if plan.skipped { Badge(text: "LEAVING ALONE", color: .secondary) }
                    else { Text("frees \(Format.bytes(plan.freed))").font(.callout).foregroundStyle(plan.freed == 0 ? .secondary : Color.keepGreen).monospacedDigit() }
                }
                .padding(.horizontal, 28).padding(.vertical, 9).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 0) {
                    ForEach(plan.set.copies) { c in CopyRow(model: model, plan: plan, copy: c) }
                    HStack {
                        Spacer()
                        Button(plan.skipped ? "Include this set again" : "Leave this set alone") { model.toggleSkip(plan.set) }.buttonStyle(.link).font(.callout)
                    }.padding(.horizontal, 28).padding(.vertical, 6)
                }
                .background(.quaternary.opacity(0.25))
            }
        }
    }
}

struct CopyRow: View {
    @Bindable var model: AppModel
    let plan: SetPlan
    let copy: FileItem
    var keeping: Bool { plan.skipped || plan.keepIDs.contains(copy.id) }

    var body: some View {
        HStack(spacing: 10) {
            Badge(text: plan.skipped ? "STAYS" : keeping ? "KEEP" : "TRASH", color: keeping ? .keepGreen : .removeRed).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(Display.short(copy.folder)).lineLimit(1).truncationMode(.middle)
                Text("Modified \(Display.date.string(from: copy.modified)) · \(Display.count(model.result?.folderFileCount[copy.folder] ?? 0)) files in this folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !keeping || plan.skipped { Button("Keep this one") { model.keep(copy, in: plan.set) }.buttonStyle(.link).font(.callout) }
            Button { model.reveal(copy) } label: { Image(systemName: "magnifyingglass.circle") }.buttonStyle(.plain).help("Show in Finder")
        }
        .padding(.leading, 58).padding(.trailing, 28).padding(.vertical, 5)
    }
}
