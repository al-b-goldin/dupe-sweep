import SwiftUI
import AppKit

@MainActor let appModel = AppModel()

@main
struct DupeSweepApp: App {
    @State private var model = appModel

    init() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { Task { @MainActor in await SelfTest.run(model: appModel) } }
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            let dir = args[i + 1]
            Task { @MainActor in await Screenshots.run(into: dir, model: appModel) }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 860, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link("Buy Me a Coffee", destination: Config.coffeeURL)
                Link("Website", destination: Config.websiteURL)
            }
        }
    }
}
