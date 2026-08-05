import Foundation
import XCTest
@testable import MusicAccessibilityDriver
import PlaylistCore

final class MusicScriptReaderTests: XCTestCase {
    func testDecodesOnlyRequestedPlaylistSnapshot() async throws {
        let json = #"{"name":"试音","tracks":[{"name":"被遗忘的时光","artist":"蔡琴"}]}"#.data(using: .utf8)!
        let runner = FakeProcessRunner(results: [.init(exitCode: 0, stdout: json, stderr: Data())])
        let snapshot = try await MusicScriptReader(runner: runner).playlist(named: "试音")
        XCTAssertEqual(snapshot, .init(name: "试音", tracks: [.init(name: "被遗忘的时光", artist: "蔡琴")]))
    }

    func testNullMeansPlaylistDoesNotExist() async throws {
        let runner = FakeProcessRunner(results: [
            .init(exitCode: 0, stdout: Data("null\n".utf8), stderr: Data())
        ])
        let snapshot = try await MusicScriptReader(runner: runner).playlist(named: "不存在")
        XCTAssertNil(snapshot)
    }

    func testMissingTrackFieldFailsClosed() async {
        let malformed = Data(#"{"name":"试音","tracks":[{"name":"曲目"}]}"#.utf8)
        let runner = FakeProcessRunner(results: [.init(exitCode: 0, stdout: malformed, stderr: Data())])
        do {
            _ = try await MusicScriptReader(runner: runner).playlist(named: "试音")
            XCTFail("缺少艺人字段时不应接受快照")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("解析"))
        }
    }

    func testNonzeroExitIncludesChineseDiagnosticAndStderr() async {
        let runner = FakeProcessRunner(results: [
            .init(exitCode: 1, stdout: Data(), stderr: Data("没有自动化权限".utf8))
        ])
        do {
            _ = try await MusicScriptReader(runner: runner).playlist(named: "试音")
            XCTFail("非零退出码不应成功")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("音乐脚本执行失败"))
            XCTAssertTrue(error.localizedDescription.contains("没有自动化权限"))
        }
    }

    func testJXAReturnsJSONOnStandardOutputInsteadOfConsoleDiagnostic() async throws {
        let runner = OutputChannelCheckingRunner()
        let snapshot = try await MusicScriptReader(runner: runner).playlist(named: "试音")
        XCTAssertEqual(snapshot?.tracks.count, 1)
    }
}

private actor FakeProcessRunner: ProcessRunning {
    var results: [ProcessResult]
    init(results: [ProcessResult]) { self.results = results }

    func run(executable: URL, arguments: [String], stdin: Data?) throws -> ProcessResult {
        results.removeFirst()
    }
}

private actor OutputChannelCheckingRunner: ProcessRunning {
    func run(executable: URL, arguments: [String], stdin: Data?) throws -> ProcessResult {
        let script = String(decoding: stdin ?? Data(), as: UTF8.self)
        let json = Data(#"{"name":"试音","tracks":[{"name":"被遗忘的时光","artist":"蔡琴"}]}"#.utf8)
        if script.contains("console.log") {
            return .init(exitCode: 0, stdout: Data(), stderr: json)
        }
        return .init(exitCode: 0, stdout: json, stderr: Data())
    }
}
