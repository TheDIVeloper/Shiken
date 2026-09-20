import SwiftUI

@main
struct ShikenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 660)
        #endif
    }
}

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        NavigationStack {
            HomeView()
        }
        #else
        NavigationSplitView {
            List { Text("Subjects") }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            HomeView()
        }
        #endif
    }
}

struct HomeView: View {
    var body: some View {
        VStack(spacing: DesignSystem.spaceL()) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: DesignSystem.typeHero()))

            Text("Shiken")
                .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))

            Text("Your revision plan, held to account.")
                .font(.system(size: DesignSystem.typeBody(), weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .padding()
        #endif
    }
}