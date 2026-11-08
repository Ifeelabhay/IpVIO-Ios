import Foundation

enum M3UParser {
    private static let attrRegex = try! NSRegularExpression(pattern: #"([A-Za-z0-9_-]+)="([^"]*)""#)

    static func parse(_ text: String) -> [MediaItem] {
        var result: [MediaItem] = []
        var pending: (title: String, logo: URL?, group: String?)?
        var counter = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                let ns = line as NSString
                var attrs: [String: String] = [:]
                for m in attrRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    attrs[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
                }
                var title = attrs["tvg-name"] ?? ""
                if let comma = line.range(of: ",", options: .backwards) {
                    let t = line[comma.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { title = t }
                }
                let logo = attrs["tvg-logo"].flatMap { URL(string: $0) }
                let group = attrs["group-title"].flatMap { $0.isEmpty ? nil : $0 }
                pending = (title.isEmpty ? "Untitled" : title, logo, group)
            } else if !line.isEmpty, !line.hasPrefix("#"), let p = pending, let url = URL(string: line) {
                counter += 1
                let kind: MediaKind = line.contains("/movie/") ? .movie : (line.contains("/series/") ? .series : .live)
                result.append(MediaItem(rawID: String(counter), kind: kind, title: p.title, poster: p.logo,
                                        rating: nil, categoryID: p.group, year: nil, plot: nil, streamURL: url))
                pending = nil
            }
        }
        return result
    }
}
