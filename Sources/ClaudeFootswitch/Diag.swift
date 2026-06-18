import Foundation

/// Minimal append-only diagnostic log at ~/Library/Logs/ClaudeFootswitch.log.
/// Complements os_log (which can be awkward to read back) with a file anyone can `cat`.
enum Diag {
    static let url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeFootswitch.log")

    static func log(_ message: String) {
        let line = "\(stamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
