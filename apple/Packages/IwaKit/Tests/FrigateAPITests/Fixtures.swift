import Foundation
import FrigateAPI

/// Sanitized captures from real Frigate servers, in `fixtures/frigate/<version>/` at the repository root.
enum Fixtures {
    static let frigateRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: "fixtures/frigate")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        fatalError("fixtures/frigate not found above \(#filePath)")
    }()

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
