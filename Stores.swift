import Foundation

// MARK: Playlists

final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: "activePlaylist") }
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: "playlists"),
           let p = try? JSONDecoder().decode([Playlist].self, from: d) {
            playlists = p
        }
        activeID = UserDefaults.standard.string(forKey: "activePlaylist").flatMap { UUID(uuidString: $0) }
        if activeID == nil || !playlists.contains(where: { $0.id == activeID }) {
            activeID = playlists.first?.id
        }
    }

    var active: Playlist? { playlists.first { $0.id == activeID } }

    func add(_ p: Playlist, password: String?) {
        playlists.append(p)
        if let password { Keychain.set(password, for: p.id.uuidString) }
        activeID = p.id
        save()
    }

    func remove(_ p: Playlist) {
        playlists.removeAll { $0.id == p.id }
        Keychain.delete(p.id.uuidString)
        if activeID == p.id { activeID = playlists.first?.id }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(d, forKey: "playlists")
        }
    }
}

// MARK: Watch history ("Continue watching")

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let kind: MediaKind
    let itemRawID: String
    var title: String
    var position: Double
    var duration: Double
    var date: Date
}

final class History: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let storeKey = "history.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: storeKey),
           let e = try? JSONDecoder().decode([HistoryEntry].self, from: d) {
            entries = e
        }
    }

    func position(for key: String) -> Double? {
        guard let e = entries.first(where: { $0.key == key }),
              e.duration == 0 || e.position / e.duration < 0.95 else { return nil }
        return e.position
    }

    func continueWatching() -> [HistoryEntry] {
        entries.filter { $0.kind != .live && $0.duration > 0 && $0.position / $0.duration < 0.95 }
    }

    func update(key: String, kind: MediaKind, itemRawID: String, title: String,
                position: Double, duration: Double) {
        guard position > 5 else { return }
        entries.removeAll { $0.key == key }
        entries.insert(HistoryEntry(key: key, kind: kind, itemRawID: itemRawID, title: title,
                                    position: position, duration: duration, date: Date()), at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        if let d = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(d, forKey: storeKey)
        }
    }
}

// MARK: Library (loaded catalogue of the active playlist)

@MainActor
final class Library: ObservableObject {
    @Published private(set) var items: [MediaKind: [MediaItem]] = [:]
    @Published private(set) var categories: [MediaKind: [Category]] = [:]
    @Published private(set) var isLoading = false
    @Published var error: String?
    private var client: XtreamClient?

    func list(_ k: MediaKind) -> [MediaItem] { items[k] ?? [] }
    func cats(_ k: MediaKind) -> [Category] { categories[k] ?? [] }
    func item(kind: MediaKind, id: String) -> MediaItem? { list(kind).first { $0.rawID == id } }

    nonisolated private static func safe<T>(_ op: @Sendable () async throws -> [T]) async -> [T] {
        (try? await op()) ?? []
    }

    func load(_ p: Playlist) async {
        isLoading = true
        error = nil
        items = [:]
        categories = [:]
        client = nil
        defer { isLoading = false }

        do {
            switch p.source {
            case .xtream:
                let c = try XtreamClient(server: p.server, username: p.username,
                                         password: Keychain.get(p.id.uuidString) ?? "")
                client = c
                async let l = Self.safe { try await c.items(.live) }
                async let m = Self.safe { try await c.items(.movie) }
                async let s = Self.safe { try await c.items(.series) }
                async let lc = Self.safe { try await c.categories(.live) }
                async let mc = Self.safe { try await c.categories(.movie) }
                async let sc = Self.safe { try await c.categories(.series) }
                items = [.live: await l, .movie: await m, .series: await s]
                categories = [.live: await lc, .movie: await mc, .series: await sc]
            case .m3u:
                guard let url = URL(string: p.m3uURL.trimmingCharacters(in: .whitespaces)) else {
                    throw XtreamError.invalidServer
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(decoding: data, as: UTF8.self)
                let all = await Task.detached { M3UParser.parse(text) }.value
                items = Dictionary(grouping: all, by: \.kind)
                categories = items.mapValues { list in
                    Array(Set(list.compactMap(\.categoryID))).sorted().map { Category(id: $0, name: $0) }
                }
            }
            if items.values.allSatisfy({ $0.isEmpty }) {
                error = "The playlist loaded but contains no titles."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func episodes(for item: MediaItem) async -> [Episode] {
        (try? await client?.episodes(seriesID: item.rawID)) ?? []
    }

    func movieDetails(_ item: MediaItem) async -> VODDetails? {
        (try? await client?.vodDetails(item.rawID)) ?? nil
    }
}
