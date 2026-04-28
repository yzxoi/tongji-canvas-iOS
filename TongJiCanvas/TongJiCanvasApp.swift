import SwiftUI

@main
struct TongJiCanvasApp: App {
    @StateObject private var repo = SessionRepository()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(repo)
        }
    }
}
