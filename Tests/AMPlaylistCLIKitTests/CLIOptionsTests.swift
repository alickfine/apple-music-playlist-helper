import Foundation
import XCTest
@testable import AMPlaylistCLIKit
import PlaylistCore

final class CLIOptionsTests: XCTestCase {
    func testRequiresSubcommandAndInput() {
        XCTAssertThrowsError(try CLIOptions.parse([]))
        XCTAssertThrowsError(try CLIOptions.parse(["list"]))
        XCTAssertThrowsError(try CLIOptions.parse(["add"]))
        XCTAssertThrowsError(try CLIOptions.parse(["remove"]))
    }

    func testParsesAllAddOptions() throws {
        let options = try CLIOptions.parse([
            "add", "--playlist", "试音", "--input", "/tmp/tracks.json", "--create",
            "--dry-run", "--play-first", "--timeout", "12", "--json"
        ])
        XCTAssertEqual(options.command, .add)
        XCTAssertEqual(options.playlist, "试音")
        XCTAssertEqual(options.input.path, "/tmp/tracks.json")
        XCTAssertTrue(options.create)
        XCTAssertTrue(options.dryRun)
        XCTAssertTrue(options.playFirst)
        XCTAssertEqual(options.timeoutSeconds, 12)
        XCTAssertTrue(options.json)
    }

    func testParsesRemovalDryRunWithExplicitReceiptDirectoryAndJSON() throws {
        let options = try CLIOptions.parse([
            "remove", "--input", "/tmp/removals.json", "--receipt-dir", "/tmp/receipts",
            "--dry-run", "--json",
        ])

        XCTAssertEqual(options.command, .remove)
        XCTAssertEqual(options.input.path, "/tmp/removals.json")
        XCTAssertEqual(options.receiptDirectory?.path, "/tmp/receipts")
        XCTAssertTrue(options.dryRun)
        XCTAssertTrue(options.json)
        XCTAssertFalse(options.approved)
        XCTAssertNil(options.receiptToken)
    }

    func testParsesApprovedRemovalWithReceiptTokenAndSameDirectory() throws {
        let options = try CLIOptions.parse([
            "remove", "--input", "/tmp/removals.json", "--receipt-dir", "/tmp/receipts",
            "--approved", "--receipt-token", "0123456789abcdef",
        ])

        XCTAssertTrue(options.approved)
        XCTAssertEqual(options.receiptToken, "0123456789abcdef")
        XCTAssertEqual(options.receiptDirectory?.path, "/tmp/receipts")
    }

    func testRejectsCreateForRemove() {
        XCTAssertThrowsError(try CLIOptions.parse(["remove", "--input", "removals.json", "--create"]))
    }

    func testRejectsPlayFirstForRemove() {
        XCTAssertThrowsError(try CLIOptions.parse(["remove", "--input", "removals.json", "--play-first"]))
    }

    func testRemovalDryRunRequiresExplicitReceiptDirectoryAndJSON() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "remove", "--input", "removals.json", "--dry-run", "--json",
        ]))
        XCTAssertThrowsError(try CLIOptions.parse([
            "remove", "--input", "removals.json", "--receipt-dir", "/tmp/receipts", "--dry-run",
        ]))
    }

    func testActualRemovalRequiresApprovalTokenAndReceiptDirectory() {
        XCTAssertThrowsError(try CLIOptions.parse(["remove", "--input", "removals.json"]))
        XCTAssertThrowsError(try CLIOptions.parse([
            "remove", "--input", "removals.json", "--receipt-dir", "/tmp/receipts", "--approved",
        ]))
        XCTAssertThrowsError(try CLIOptions.parse([
            "remove", "--input", "removals.json", "--receipt-dir", "/tmp/receipts",
            "--receipt-token", "token",
        ]))
    }

    func testRejectsReceiptOptionsForAddAndApprovalOptionsForDryRun() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "add", "--input", "tracks.json", "--receipt-dir", "/tmp/receipts",
        ]))
        XCTAssertThrowsError(try CLIOptions.parse([
            "remove", "--input", "removals.json", "--receipt-dir", "/tmp/receipts",
            "--dry-run", "--json", "--approved", "--receipt-token", "token",
        ]))
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

    func testRemoveRequiresExplicitPlaylistFromCommandOrDocument() throws {
        let options = try CLIOptions.parse([
            "remove", "--input", "removals.json", "--receipt-dir", "/tmp/receipts",
            "--dry-run", "--json",
        ])

        XCTAssertThrowsError(try options.resolvedPlaylist(documentPlaylist: nil)) { error in
            XCTAssertEqual(error as? CLIOptionsError, .missingRemovalPlaylist)
            XCTAssertEqual(error.localizedDescription, "remove 命令必须通过 --playlist 或输入 JSON 明确指定播放列表。")
        }
        XCTAssertEqual(try options.resolvedPlaylist(documentPlaylist: "明确列表"), "明确列表")
    }

    func testAddKeepsHistoricalDefaultPlaylist() throws {
        let options = try CLIOptions.parse(["add", "--input", "tracks.json"])

        XCTAssertEqual(try options.resolvedPlaylist(documentPlaylist: nil), "试音")
    }
}
