import Foundation

enum XtreamError: LocalizedError {
    case invalidServer, authFailed, badResponse

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "The server address is not valid."
        case .authFailed: return "Login failed. Check server, user name and password."
        case .badResponse: return "The server sent an unexpected response."
        }
    }
}

// Xtream servers mix numbers and strings freely, so values are read tolerantly.
private func str(_ v: Any?) -> String? {
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
private func dbl(_ v: Any?) -> Double? {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}
private func imageURL(_ v: Any?) -> URL? {
    guard let s = str(v), s.hasPrefix("http") else { return nil }
    return URL(string: s)
}

struct XtreamClient {
    let base: String
    let username: String
    let password: String

    init(server: String, username: String, password: String) throws {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw XtreamError.invalidServer }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard URL(string: s) != nil else { throw XtreamError.invalidServer }
        self.base = s
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    // MARK: Requests

    private func call(_ action: String? = nil, _ extra: [String: String] = [:]) async throws -> Any {
        guard var comps = URLComponents(string: base + "/player_api.php") else { throw XtreamError.invalidServer }
        var q = [URLQueryItem(name: "username", value: username),
                 URLQueryItem(name: "password", value: password)]
        if let action { q.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in extra { q.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = q
        guard let url = comps.url else { throw XtreamError.invalidServer }
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 90))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw XtreamError.badResponse }
        return try JSONSerialization.jsonObject(with: data)
    }

    func authenticate() async throws {
        guard let d = try await call() as? [String: Any],
              let info = d["user_info"] as? [String: Any],
              str(info["auth"]) == "1" else { throw XtreamError.authFailed }
    }

    // MARK: Stream URLs

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func streamURL(_ path: String, _ id: String, ext: String) -> URL? {
        URL(string: "\(base)/\(path)/\(enc(username))/\(enc(password))/\(id).\(ext)")
    }

    // MARK: Catalogue

    func categories(_ kind: MediaKind) async throws -> [Category] {
        let action: String
        switch kind {
        case .live: action = "get_live_categories"
        case .movie: action = "get_vod_categories"
        case .series: action = "get_series_categories"
        }
        guard let rows = try await call(action) as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let id = str(r["category_id"]) else { return nil }
            return Category(id: id, name: str(r["category_name"]) ?? id)
        }
    }

    func items(_ kind: MediaKind) async throws -> [MediaItem] {
        let action: String
        switch kind {
        case .live: action = "get_live_streams"
        case .movie: action = "get_vod_streams"
        case .series: action = "get_series"
        }
        guard let rows = try await call(action) as? [[String: Any]] else { return [] }
        return rows.compactMap { r -> MediaItem? in
            let rt = dbl(r["rating"])
            let rating = (rt ?? 0) > 0 ? rt : nil
            switch kind {
            case .live:
                guard let id = str(r["stream_id"]) else { return nil }
                return MediaItem(rawID: id, kind: .live, title: str(r["name"]) ?? "Channel",
                                 poster: imageURL(r["stream_icon"]), rating: nil,
                                 categoryID: str(r["category_id"]), year: nil, plot: nil,
                                 streamURL: streamURL("live", id, ext: "m3u8"))
            case .movie:
                guard let id = str(r["stream_id"]) else { return nil }
                let ext = str(r["container_extension"]) ?? "mp4"
                return MediaItem(rawID: id, kind: .movie, title: str(r["name"]) ?? "Movie",
                                 poster: imageURL(r["stream_icon"]), rating: rating,
                                 categoryID: str(r["category_id"]), year: str(r["year"]), plot: nil,
                                 streamURL: streamURL("movie", id, ext: ext))
            case .series:
                guard let id = str(r["series_id"]) else { return nil }
                return MediaItem(rawID: id, kind: .series, title: str(r["name"]) ?? "Series",
                                 poster: imageURL(r["cover"]), rating: rating,
                                 categoryID: str(r["category_id"]),
                                 year: str(r["year"]) ?? str(r["releaseDate"]).map { String($0.prefix(4)) },
                                 plot: str(r["plot"]), streamURL: nil)
            }
        }
    }

    func vodDetails(_ id: String) async throws -> VODDetails? {
        guard let d = try await call("get_vod_info", ["vod_id": id]) as? [String: Any],
              let info = d["info"] as? [String: Any] else { return nil }
        return VODDetails(plot: str(info["plot"]) ?? str(info["description"]),
                          genre: str(info["genre"]),
                          year: str(info["releasedate"]).map { String($0.prefix(4)) })
    }

    func episodes(seriesID: String) async throws -> [Episode] {
        guard let d = try await call("get_series_info", ["series_id": seriesID]) as? [String: Any] else { return [] }
        var rows: [[String: Any]] = []
        if let bySeason = d["episodes"] as? [String: Any] {
            for (_, v) in bySeason {
                if let arr = v as? [[String: Any]] { rows += arr }
            }
        } else if let arr = d["episodes"] as? [[String: Any]] {
            rows = arr
        }
        return rows.compactMap { r -> Episode? in
            guard let id = str(r["id"]) else { return nil }
            let ext = str(r["container_extension"]) ?? "mp4"
            guard let url = streamURL("series", id, ext: ext) else { return nil }
            let info = r["info"] as? [String: Any] ?? [:]
            return Episode(id: id,
                           season: Int(str(r["season"]) ?? "") ?? 1,
                           number: Int(str(r["episode_num"]) ?? "") ?? 0,
                           title: str(r["title"]) ?? "Episode",
                           plot: str(info["plot"]),
                           image: imageURL(info["movie_image"]),
                           streamURL: url)
        }
        .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }
}
