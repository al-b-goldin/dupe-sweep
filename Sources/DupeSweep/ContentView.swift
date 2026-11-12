import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            switch model.stage {
            case .start: StartView(model: model)
            case .scanning: ScanningView(model: model)
            case .results: ResultsView(model: model)
            case .done: DoneView(model: model)
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
