import Testing
import Foundation
@testable import Twain

struct CLIInstallTests {
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("twain-cli-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func installsExecutableCopyIntoMissingBinDirectory() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let source = work.appendingPathComponent("twain-source")
        try "#!/bin/bash\necho hi\n".write(to: source, atomically: true, encoding: .utf8)
        let bin = work.appendingPathComponent("nested/.bin")

        let installed = try CLIInstaller.install(from: source, toDirectory: bin)

        #expect(installed.path == bin.appendingPathComponent("twain").path)
        #expect(try String(contentsOf: installed, encoding: .utf8).contains("echo hi"))
        let permissions = try FileManager.default
            .attributesOfItem(atPath: installed.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test func overwritesExistingInstall() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let source = work.appendingPathComponent("twain-source")
        try "new version".write(to: source, atomically: true, encoding: .utf8)
        let bin = work.appendingPathComponent(".bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "old version".write(
            to: bin.appendingPathComponent("twain"), atomically: true, encoding: .utf8)

        let installed = try CLIInstaller.install(from: source, toDirectory: bin)

        #expect(try String(contentsOf: installed, encoding: .utf8) == "new version")
    }

    @Test func missingBundleResourceThrows() {
        #expect(throws: CLIInstaller.ResourceMissingError.self) {
            try CLIInstaller.install(from: nil, toDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }
}
