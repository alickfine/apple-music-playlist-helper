import Foundation
import XCTest
@testable import AMPlaylistCLIKit
import PlaylistCore

final class CLIOptionsTests: XCTestCase {
    func testRequiresAddSubcommandAndInput() {
        XCTAssertThrowsError(try CLIOptions.parse([]))
        XCTAssertThrowsError(try CLIOptions.parse(["list"]))
        XCTAssertThrowsError(try CLIOptions.parse(["add"]))
    }

    func testParsesAllSupportedOptions() throws {
        let options = try CLIOptions.parse([
            "add", "--playlist", "试音", "--input", "/tmp/tracks.json", "--create",
            "--dry-run", "--play-first", "--timeout", "12", "--json"
        ])
        XCTAssertEqual(options.playlist, "试音")
        XCTAssertEqual(options.input.path, "/tmp/tracks.json")
        XCTAssertTrue(options.create)
        XCTAssertTrue(options.dryRun)
        XCTAssertTrue(options.playFirst)
        XCTAssertEqual(options.timeoutSeconds, 12)
        XCTAssertTrue(options.json)
    }

    func testDefaultTimeoutIsEightSeconds() throws {
        XCTAssertEqual(try CLIOptions.parse(["add", "--input", "a.json"]).timeoutSeconds, 8)
    }

    func testRejectsUnknownOptionAndNonpositiveTimeout() {
        XCTAssertThrowsError(try CLIOptions.parse(["add", "--input", "a.json", "--what"]))
        XCTAssertThrowsError(try CLIOptions.parse(["add", "--input", "a.json", "--timeout", "0"]))
    }

    func testRejectsConflictingPlaylistSources() throws {
        let options = try CLIOptions.parse(["add", "--playlist", "命令行", "--input", "a.json"])
        XCTAssertThrowsError(try options.resolvedPlaylist(documentPlaylist: "JSON"))
        XCTAssertEqual(try options.resolvedPlaylist(documentPlaylist: nil), "命令行")
    }
}
