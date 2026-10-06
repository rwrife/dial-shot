import DialShotKit
import DialShotStore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Issue #7 — the user-owned data surface: JSON backup, CSV shot log, and
/// previewed restore, all file-based and fully user-initiated.
///
/// Transport is exclusively the iOS share sheet and the system Files picker;
/// the app never contacts a network. Restore is strictly two-phase: pick a
/// file, review a preview of exactly what it contains, and only then confirm
/// a transactional replacement — a cancelled preview never touches data.
struct DataOwnershipView: View {
    @Environment(ShotWorkspaceCoordinator.self) private var workspace
    let persistence: ShotPersistence
    @State private var message: String?
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var backupFile: BackupFileDocument?
    @State private var backupExporterPresented = false
    @State private var importPresented = false
    @State private var pendingRestore: BackupDocument?
    @State private var restorePreview: BackupPreview?
    @State private var restoreConfirmed = false
    @State private var didConsumeRestoreArgument = false

    #if DEBUG
    /// UI automation hook: suppresses presenting system sheets so journeys
    /// can assert the app-side write/validation ran, without driving the
    /// system share sheet through the AX layer.
    private var suppressSystemSheets: Bool {
        ProcessInfo.processInfo.arguments.contains("-DialShotUITestSuppressSystemSheets")
    }

    /// UI automation hook: the system document picker is out-of-process UI
    /// that XCUITest cannot drive. A launch argument naming a JSON file in
    /// the app's Documents directory injects the picked URL directly, so
    /// journeys exercise the real preview → confirm → restore pipeline.
    private var pendingRestoreArgument: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-DialShotUITestRestoreFrom"),
              index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #else
    private var suppressSystemSheets: Bool { false }
    private var pendingRestoreArgument: String? { nil }
    #endif

    private var service: ShotExportService { ShotExportService(persistence: persistence) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your coffee data stays on this iPhone").font(.title2.bold())
            Text("Export a backup file, export the shot log as CSV, or restore a backup from Files. Restoring replaces everything on this device after you review a preview.")
                .foregroundStyle(.secondary)

            Button {
                runExport(.backup)
            } label: {
                Label("Export backup (JSON)", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Export backup JSON file")
            .accessibilityIdentifier("data.backup")

            Button {
                runExport(.csv)
            } label: {
                Label("Export shot log (CSV)", systemImage: "tablecells")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Export shot log CSV file")
            .accessibilityIdentifier("data.csv")

            Button {
                importPresented = true
            } label: {
                Label("Restore from backup", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel("Restore from backup JSON file")
            .accessibilityIdentifier("data.restore")

            if let message {
                Text(message)
                    .accessibilityIdentifier("data.message")
            }
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("data.error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { consumePendingRestoreArgument() }
        .fileImporter(
            isPresented: $importPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(isPresented: $backupExporterPresented, document: backupFile,
                      contentType: .json, defaultFilename: "dial-shot-backup") { result in
            if case .failure(let failure) = result {
                error = "Export failed: \(failure.localizedDescription)"
            }
            backupFile = nil
        }
        .confirmationDialog(
            restorePreview != nil ? "Replace all local data with this backup?" : "",
            isPresented: $restoreConfirmed,
            titleVisibility: .visible
        ) {
            Button("Replace all data", role: .destructive) { confirmRestore() }
            Button("Cancel", role: .cancel) { clearPendingRestore() }
        } message: {
            if let restorePreview {
                Text("Schema v\(restorePreview.schemaVersion.rawValue) · \(restorePreview.entityCounts.previewSummary)")
            }
        }
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURL(url: $0) } },
            set: { shareURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
                .ignoresSafeArea()
        }
    }

    private enum ExportKind { case backup, csv }

    /// Once per view lifetime: route an injected automation URL through the
    /// exact same preview pipeline a picked file would use.
    private func consumePendingRestoreArgument() {
        #if DEBUG
        guard !didConsumeRestoreArgument, let name = pendingRestoreArgument else { return }
        didConsumeRestoreArgument = true
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        handleImport(.success([url]))
        #endif
    }

    private func runExport(_ kind: ExportKind) {
        error = nil
        message = nil
        do {
            let file: ExportedFile
            switch kind {
            case .backup: file = try service.writeBackupJSON()
            case .csv: file = try service.writeShotCSV()
            }
            switch kind {
            case .backup:
                message = "Backup written: \(file.url.lastPathComponent)"
                if !suppressSystemSheets {
                    backupFile = BackupFileDocument(data: try Data(contentsOf: file.url))
                    backupExporterPresented = true
                }
            case .csv:
                let shotCount = (try? persistence.history().count) ?? 0
                message = "CSV written: \(file.url.lastPathComponent) — \(shotCount) shot\(shotCount == 1 ? "" : "s")"
                if !suppressSystemSheets { shareURL = file.url }
            }
        } catch {
            self.error = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        error = nil
        restorePreview = nil
        pendingRestore = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let document = try service.readRestore(from: url)
                restorePreview = BackupPreview(schemaVersion: document.schemaVersion,
                    producerBundleID: document.exportInfo.producerBundleID,
                    entityCounts: document.entityCounts)
                pendingRestore = document
                restoreConfirmed = true
            } catch {
                self.error = "Cannot restore this file: \(error.localizedDescription)"
            }
        case .failure(let failure):
            self.error = "Pick cancelled or failed: \(failure.localizedDescription)"
        }
    }

    private func confirmRestore() {
        guard let document = pendingRestore else { return }
        do {
            try persistence.restoreBackup(document)
            workspace.clearComparisonSelection()
            workspace.selectedBeanID = persistence.workspaceBeanID
            if let recipe = persistence.recipe {
                workspace.installDraft(recipe: recipe)
            } else {
                workspace.draft = nil
                workspace.yieldInputText = ""
            }
            message = "Backup restored on this iPhone."
            error = nil
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
        clearPendingRestore()
    }

    private func clearPendingRestore() {
        restorePreview = nil
        pendingRestore = nil
        restoreConfirmed = false
    }
}

/// Concrete document for the system Files export picker.
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Minimal share-sheet wrapper for CSV. JSON backup uses the Files export
/// picker; the app itself never talks to any service.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
