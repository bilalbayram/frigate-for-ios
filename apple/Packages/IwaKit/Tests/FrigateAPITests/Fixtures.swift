import Foundation
import FrigateAPI

/// Sanitized captures from real Frigate servers, in `fixtures/frigate/<version>/` at the repository root.
enum Fixtures {
    /// `fixtures/` at the repository root.
    static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: "fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "frigate").path) { return candidate }
            directory.deleteLastPathComponent()
        }
        fatalError("fixtures/frigate not found above \(#filePath)")
    }()

    static let frigateRoot = root.appending(path: "frigate")

    /// Every captured Frigate version, so a new capture is tested without touching the tests.
    static let frigateVersions: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frigateRoot.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }()

    static func data(_ version: String, _ file: String) throws -> Data {
        try Data(contentsOf: frigateRoot.appending(path: "\(version)/\(file)"))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ version: String, _ file: String) throws -> T {
        try Frigate.decoder().decode(type, from: data(version, file))
    }
}
