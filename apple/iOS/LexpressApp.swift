import SwiftUI

@main
struct LexpressApp: App {
    @StateObject private var model = TranslatorModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
