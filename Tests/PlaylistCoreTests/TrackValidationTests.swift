import Foundation
import XCTest
@testable import PlaylistCore

final class TrackValidationTests: XCTestCase {
    func testAcceptsValidChinaStorefrontTrack() throws {
        let track = makeTrack()

        XCTAssertEqual(try track.validated(), track)
    }

    func testCatalogTrackExtractsNumericAlbumIDFromValidatedURL() throws {
        let track = makeTrack(
            url: "https://music.apple.com/cn/album/example/905228605?i=905228611"
        )

        XCTAssertEqual(try track.validated().albumID, "905228605")
    }

    func testCatalogTrackReturnsNilWhenAlbumPathHasNoNumericID() throws {
        let track = makeTrack(
            url: "https://music.apple.com/cn/album/example/not-numeric?i=905228611"
        )

        XCTAssertNil(try track.validated().albumID)
    }

    func testRejectsNonNumericCatalogID() {
        let track = makeTrack(id: "not-a-number")

        assertValidationError(.invalidCatalogID, for: track)
    }

    func testRejectsNonHTTPSURL() {
        let track = makeTrack(url: "http://music.apple.com/cn/album/example/1?i=905228611")

        assertValidationError(.invalidScheme, for: track)
    }

    func testRejectsNonAppleMusicHost() {
        let track = makeTrack(url: "https://example.com/cn/album/example/1?i=905228611")

        assertValidationError(.invalidHost, for: track)
    }

    func testRejectsMissingCatalogIDQuery() {
        let track = makeTrack(url: "https://music.apple.com/cn/album/example/1")

        assertValidationError(.missingCatalogID, for: track)
    }

    func testRejectsMismatchedCatalogID() {
        let track = makeTrack(url: "https://music.apple.com/cn/album/example/1?i=123")

        assertValidationError(.catalogIDMismatch, for: track)
    }

    func testRejectsEmptyTrackName() {
        let track = makeTrack(name: "  \n")

        assertValidationError(.emptyName, for: track)
    }

    func testRejectsEmptyArtistName() {
        let track = makeTrack(artist: "\t ")

        assertValidationError(.emptyArtist, for: track)
    }

    func testLargeInputRetainsEveryTrackInOrder() throws {
        let tracks = (1...135).map { index in
            let id = String(900_000_000 + index)
            return makeTrack(
                id: id,
                name: "曲目 \(index)",
                artist: "艺人 \(index)",
                url: "https://music.apple.com/ca/album/example/1?i=\(id)"
            )
        }
        let document = TrackInputDocument(playlist: "大量曲目", tracks: tracks)

        let decoded = try JSONDecoder().decode(
            TrackInputDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded.tracks.count, 135)
        XCTAssertEqual(decoded.tracks.first?.name, "曲目 1")
        XCTAssertEqual(decoded.tracks.last?.name, "曲目 135")
    }

    private func makeTrack(
        id: String = "905228611",
        name: String = "被遗忘的时光",
        artist: String = "蔡琴",
        url: String = "https://music.apple.com/cn/album/example/1?i=905228611"
    ) -> CatalogTrack {
        CatalogTrack(
            id: id,
            name: name,
            artist: artist,
            url: URL(string: url)!
        )
    }

    private func assertValidationError(
        _ expected: TrackValidationError,
        for track: CatalogTrack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try track.validated(), file: file, line: line) { error in
            XCTAssertEqual(error as? TrackValidationError, expected, file: file, line: line)
        }
    }
}
