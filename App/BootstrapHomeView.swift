import DialShotKit
import SwiftUI

struct BootstrapHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Dial Shot")
                        .font(.largeTitle.bold())
                    Text("A local-first espresso dial-in log for one-thumb shot capture.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Native iPhone foundation is ready", systemImage: "checkmark.circle")
                        Text("Timer capture, immutable shot memory, and deterministic next-step guidance land in the next milestones.")
                            .foregroundStyle(.secondary)
                        Text("Domain core milestone: \(DialShotKit.milestone).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .navigationTitle("Home")
        }
        .accessibilityIdentifier("bootstrap.home")
    }
}
