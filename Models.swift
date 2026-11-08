import Foundation

enum MediaKind: String, Codable, CaseIterable {
    case live, movie, series
}

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
}

struct MediaItem: Identifiable, Hashable {
    let rawID: String          // provider id (stream_id / series_id) or running number for M3U
    let kind: MediaKind
    let title: String
    let poster: URL?
    let rating: Double?
    let categoryID: String?
    let year: String?
    let plot: String?
    let streamURL: URL?        // live, movie, M3U entries; nil for Xtream series (episodes are loaded later)

    var id: String { "\(kind.rawValue):\(rawID)" }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let plot: String?
    let image: URL?
    let streamURL: URL
}

struct VODDetails {
    var plot: String?
    var genre: String?
    var year: String?
}

struct Playlist: Identifiable, Codable, Hashable {
    enum Source: String, Codable { case xtream, m3u }
    var id = UUID()
    var name: String
    var source: Source
    var server: String = ""
    var username: String = ""
    var m3uURL: String = ""
    // The password lives in the Keychain, keyed by `id`.
}

struct Playable: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let key: String            // history key
    let kind: MediaKind
    let itemRawID: String
}
