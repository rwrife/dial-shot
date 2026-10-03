import DialShotKit
import SwiftUI

@main
struct DialShotApp: App {
    /// Issue #6: timer, draft, and comparison selection live here — above
    /// the view hierarchy — so view rebuilds and layout switches cannot
    /// reset an active shot or discard input.
    @State private var workspace = ShotWorkspaceCoordinator()

    var body: some Scene {
        WindowGroup {
            ShotWorkspaceView()
                .environment(workspace)
        }
    }
}
