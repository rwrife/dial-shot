import Foundation
import DialShotKit

/// Issue #7 — local-first data ownership at the app boundary.
///
/// `ShotExportService` turns the validated backup/CSV logic into files the
/// user can own: it writes into the app's Documents directory with a dated
/// name and hands the URL to the iOS share sheet (or Files). No network
/// framework is ever touched — the share sheet and document picker are the
/// only transport, fully user-initiated.
enum ExportDestination: Equatable {
    case documents
}

struct ExportedFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let kind: Kind

    enum Kind: Equatable {
        case backupJSON
        case shotCSV
    }
}

enum ExportError: LocalizedError {
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .notPrepared: "Local storage is not ready yet."
        }
    }
}

@MainActor
final class ShotExportService {
    private let persistence: ShotPersistence

    init(persistence: ShotPersistence) {
        self.persistence = persistence
    }

    /// Writes the complete database as a versioned JSON backup into the
    /// Documents directory. Returns the URL for the share sheet / Files.
    func writeBackupJSON() throws -> ExportedFile {
        let document = try persistence.backupDocument()
        let data = try BackupJSONCodec.encode(document)
        let url = documentsURL(prefix: "dial-shot-backup", extension: "json")
        try data.write(to: url, options: .atomic)
        return ExportedFile(url: url, kind: .backupJSON)
    }

    /// Writes the flat shot-log CSV export into the Documents directory.
    func writeShotCSV() throws -> ExportedFile {
        let history = try persistence.history()
        let csv = ShotCSVExport.csv(history)
        let url = documentsURL(prefix: "dial-shot-shots", extension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return ExportedFile(url: url, kind: .shotCSV)
    }

    /// Validates a picked backup file and reports what it contains, without
    /// touching the database.
    func previewRestore(from url: URL) throws -> BackupPreview {
        let scoped = PickedFile.read(url) { try Data(contentsOf: $0) }
        return try BackupJSONCodec.preview(scoped)
    }

    func readRestore(from url: URL) throws -> BackupDocument {
        let scoped = PickedFile.read(url) { try Data(contentsOf: $0) }
        return try BackupJSONCodec.decodedForRestore(scoped)
    }

    /// Applies a picked backup after the user confirmed the preview: full
    /// replacement in one transaction, then re-opens local storage so the
    /// live workspace reflects the restored beans, recipe, and selection.
    func restore(from url: URL) throws {
        let scoped = PickedFile.read(url) { try Data(contentsOf: $0) }
        let document = try BackupJSONCodec.decodedForRestore(scoped)
        try persistence.restoreBackup(document)
    }

    private func documentsURL(prefix: String, extension ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // Never overwrite an earlier export when the user taps twice within
        // the same second (or the wall clock moves backwards).
        let name = "\(prefix)-\(formatter.string(from: Date()))-\(UUID().uuidString).\(ext)"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(name)
    }
}

/// Files picked through the system document picker are security-scoped:
/// reads must happen between `startAccessingSecurityScopedResource()` and
/// its matching release. This helper keeps that bracket exact.
enum PickedFile {
    static func read<T>(_ url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
