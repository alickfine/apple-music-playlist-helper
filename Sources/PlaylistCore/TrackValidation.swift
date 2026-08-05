import Foundation

public extension CatalogTrack {
    func validated() throws -> CatalogTrack {
        let isASCIINumeric = !id.isEmpty && id.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(Int(scalar.value))
        }
        guard isASCIINumeric else {
            throw TrackValidationError.invalidCatalogID
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrackValidationError.emptyName
        }
        guard !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrackValidationError.emptyArtist
        }

        guard url.scheme?.lowercased() == "https" else {
            throw TrackValidationError.invalidScheme
        }
        guard url.host?.lowercased() == "music.apple.com" else {
            throw TrackValidationError.invalidHost
        }

        let catalogIDs = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .filter { $0.name == "i" }
            .compactMap(\.value) ?? []

        guard !catalogIDs.isEmpty else {
            throw TrackValidationError.missingCatalogID
        }
        guard catalogIDs.count == 1 else {
            throw TrackValidationError.ambiguousCatalogID
        }
        guard catalogIDs[0] == id else {
            throw TrackValidationError.catalogIDMismatch
        }

        return self
    }
}
