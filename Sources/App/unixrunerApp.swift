import SwiftUI

@main
struct unixrunerApp: App {
    init() {
        try? AlpinePayload.shared.preparePayload()
    }

    var body: some Scene {
        WindowGroup {
            VMListView()
                .preferredColorScheme(.dark)
        }
    }
}
