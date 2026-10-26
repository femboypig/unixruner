import SwiftUI

public struct RootView: View {
    public init() {}

    public var body: some View {
        TabView {
            VMListView()
                .tabItem {
                    Label("Machines", systemImage: "terminal.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
