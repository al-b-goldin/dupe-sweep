import SwiftUI
import DupeEngine

struct StartView: View {
    @Bindable var model: AppModel
    @State private var targeted = false
    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
                    .foregroundStyle(targeted ? Color.brand : Color.secondary.opacity(0.5))
                    .background(RoundedRectangle(cornerRadius: 20).fill(targeted ? Color.brand.opacity(0.10) : Color.clear))
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 46)).foregroundStyle(Color.brand)
                    Text("Drop folders here").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Drag in the folders you want checked for duplicate files, or").foregroundStyle(.secondary)
                    Button("Choose Folders…") { model.choose() }.controlSize(.large)
                }
                .padding(24)
            }
            .frame(height: 230)
            .dropDestination(for: URL.self, action: { urls, _ in model.add(urls); return true }, isTargeted: { targeted = $0 })
            .animation(.easeOut(duration: 0.15), value: targeted)

            if !model.folders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To check").font(.headline)
                    FlowLayout(spacing: 8) { ForEach(model.folders, id: \.self) { u in FolderChip(path: u.path) { model.remove(u) } } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup("Options", isExpanded: $showOptions) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Ignore files smaller than", selection: $model.floor) {
                        ForEach(SizeFloor.allCases) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 320)
                    Toggle("Include hidden files and folders", isOn: $model.includeHidden)
                }
                .padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }

            if let m = model.message { Text(m).font(.callout).foregroundStyle(Color.removeRed) }

            Button { model.startScan() } label: {
                Text("Find Duplicates").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(model.folders.isEmpty)

            VStack(alignment: .leading, spacing: 6) {
                Label("Files go to the Trash, never straight to deletion, and you can put them back.", systemImage: "arrow.uturn.backward.circle")
                Label("Every copy is compared byte for byte, not just by name. At least one copy of each file always stays.", systemImage: "checkmark.shield")
            }
            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            CoffeeFooter()
        }
        .padding(28)
    }
}

/// A simple wrapping row of views.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
