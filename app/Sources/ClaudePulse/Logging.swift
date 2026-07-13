import Foundation
import os

/// Centralizovano logovanje: `os.Logger` (Console.app / `log stream`) + append u fajl
/// `~/Library/Logs/ClaudePulse/claudepulse.log` (za „Open log file" iz Settings-a, §3.4 Advanced).
///
/// Thread-safe: upis u fajl je serijalizovan preko privatnog queue-a, pa se sme zvati iz
/// bilo kog threada (npr. iz `NWListener` connection callbacka).
enum AppLog {
    private static let subsystem = "com.marko.claudepulse"

    private static let logger = Logger(subsystem: subsystem, category: "app")

    /// Serijalni queue štiti file handle od konkurentnih upisa.
    private static let fileQueue = DispatchQueue(label: "\(subsystem).filelog")

    /// `~/Library/Logs/ClaudePulse/claudepulse.log`
    private static let logFileURL: URL = {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClaudePulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claudepulse.log")
    }()

    /// ISO8601 vremenski žig za linije u fajlu (os.Logger ima svoj timestamp).
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        appendToFile(level: "INFO", message: message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        appendToFile(level: "ERROR", message: message)
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        appendToFile(level: "DEBUG", message: message)
    }

    private static func appendToFile(level: String, message: String) {
        let line = "\(timestampFormatter.string(from: Date())) [\(level)] \(message)\n"
        fileQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                // Fajl još ne postoji → kreiraj ga.
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }
}
