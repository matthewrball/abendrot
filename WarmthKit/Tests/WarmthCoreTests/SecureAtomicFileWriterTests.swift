import Darwin
import Foundation
import Testing
@testable import WarmthCore

@Suite("Secure atomic file writer")
struct SecureAtomicFileWriterTests {
    @Test("tightens an existing private directory and writes final file 0600")
    func tightensDirectoryAndFileMode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let url = directory.appendingPathComponent("state.json")
        try SecureAtomicFileWriter.write(Data("snapshot".utf8), to: url)

        #expect(mode(of: directory) == 0o700)
        #expect(mode(of: url) == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8) == "snapshot")
    }

    @Test("refuses a target symlink without modifying its referent")
    func refusesTargetSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let referent = directory.appendingPathComponent("referent.json")
        let target = directory.appendingPathComponent("state.json")
        try Data("keep".utf8).write(to: referent)
        try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: referent.path)

        #expect(throws: Error.self) {
            try SecureAtomicFileWriter.write(Data("replace".utf8), to: target)
        }

        #expect(try String(contentsOf: referent, encoding: .utf8) == "keep")
        #expect(isSymlink(target))
    }

    @Test("refuses a final directory symlink")
    func refusesDirectorySymlink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realDirectory = root.appendingPathComponent("real", isDirectory: true)
        let linkDirectory = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: linkDirectory.path, withDestinationPath: realDirectory.path)

        #expect(throws: Error.self) {
            try SecureAtomicFileWriter.write(Data("snapshot".utf8), to: linkDirectory.appendingPathComponent("state.json"))
        }

        #expect(!FileManager.default.fileExists(atPath: realDirectory.appendingPathComponent("state.json").path))
    }

    @Test("atomically replaces a regular file and round-trips content")
    func replacesAndRoundTrips() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Data("old".utf8).write(to: url)

        try SecureAtomicFileWriter.write(Data("new".utf8), to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "new")
        #expect(mode(of: url) == 0o600)
    }

    @Test("refuses oversized regular files on read")
    func refusesOversizedRead() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Data(repeating: 0, count: SecureAtomicFileWriter.maxSnapshotBytes + 1).write(to: url)

        #expect(throws: Error.self) {
            _ = try SecureAtomicFileWriter.readRegularFileIfExists(from: url)
        }
    }

    @Test("refuses oversized writes before creating a file")
    func refusesOversizedWrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")

        #expect(throws: Error.self) {
            try SecureAtomicFileWriter.write(
                Data(repeating: 0, count: SecureAtomicFileWriter.maxSnapshotBytes + 1),
                to: url
            )
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secure-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func mode(of url: URL) -> Int {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return -1 }
        return Int(info.st_mode & 0o777)
    }

    private func isSymlink(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }
}
