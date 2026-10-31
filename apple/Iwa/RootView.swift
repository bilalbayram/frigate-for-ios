import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Frigate Servers", systemImage: "video.badge.plus")
            } description: {
                Text("Add a Frigate server to see your cameras.")
            } actions: {
                Button("Add Server") {}
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Iwa")
        }
    }
}

#Preview {
    RootView()
}
