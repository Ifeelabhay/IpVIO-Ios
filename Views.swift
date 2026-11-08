import SwiftUI

// MARK: Poster cell

struct PosterCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Theme.card
                AsyncImage(url: item.poster) { phase in
                    switch phase {
                    case .success(let img):
                        if item.kind == .live {
                            img.resizable().scaledToFit().padding(10)
                        } else {
                            img.resizable().scaledToFill()
                        }
                    default:
                        Image(systemName: item.kind == .live ? "tv" : "film")
                            .font(.title).foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(item.kind == .live ? 16 / 9 : 2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title).font(.caption).lineLimit(2)
            if let r = item.rating {
                Label(String(format: "%.1f", r), systemImage: "star.fill")
                    .font(.caption2).foregroundStyle(.yellow)
            }
        }
    }
}

// MARK: Home

struct HomeView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var history: History

    private var continueItems: [MediaItem] {
        var seen = Set<String>()
        return history.continueWatching()
            .compactMap { library.item(kind: $0.kind, id: $0.itemRawID) }
            .filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let e = library.error {
                        Text(e).foregroundStyle(.red).padding(.horizontal)
                    }
                    row("Continue watching", continueItems)
                    row("Movies", Array(library.list(.movie).suffix(20).reversed()))
                    row("Series", Array(library.list(.series).suffix(20).reversed()))
                    row("Live TV", Array(library.list(.live).prefix(20)))
                }
                .padding(.vertical)
            }
            .background(Theme.navy.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ items: [MediaItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCell(item: item).frame(width: item.kind == .live ? 190 : 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: Browse (Movies / Series / Live)

struct BrowseView: View {
    let kind: MediaKind
    let title: String
    @EnvironmentObject private var library: Library
    @State private var query = ""
    @State private var category: String?
    @State private var sort: Sort = .standard

    enum Sort: String, CaseIterable { case standard = "Default", name = "A–Z", rating = "Rating" }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: kind == .live ? 150 : 105), spacing: 12)]
    }

    private var shown: [MediaItem] {
        var list = library.list(kind)
        if let category { list = list.filter { $0.categoryID == category } }
        if !query.isEmpty { list = list.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .standard: break
        case .name: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating: list.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
        return Array(list.prefix(1500))   // keeps huge playlists smooth; real paging comes later
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !library.cats(kind).isEmpty { chips }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(shown) { item in
                        NavigationLink(value: item) { PosterCell(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .background(Theme.navy.ignoresSafeArea())
            .navigationTitle(title)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                }
            }
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip("All", selected: category == nil) { category = nil }
                ForEach(library.cats(kind)) { c in
                    chip(c.name, selected: category == c.id) { category = c.id }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.footnote).padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        }
    }
}

// MARK: Details

struct DetailView: View {
    let item: MediaItem
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var history: History
    @State private var episodes: [Episode] = []
    @State private var details: VODDetails?
    @State private var playing: Playable?
    @State private var loadingEpisodes = false

    private var hasEpisodes: Bool { item.kind == .series && item.streamURL == nil }
    private var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: item.poster) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                        } else {
                            Theme.card
                        }
                    }
                    .frame(width: 110, height: item.kind == .live ? 62 : 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.title3.bold())
                        let meta = [details?.year ?? item.year, details?.genre].compactMap { $0 }.joined(separator: " · ")
                        if !meta.isEmpty { Text(meta).font(.footnote).foregroundStyle(.secondary) }
                        if let r = item.rating {
                            Label(String(format: "%.1f", r), systemImage: "star.fill")
                                .font(.footnote).foregroundStyle(.yellow)
                        }
                    }
                }

                if let plot = details?.plot ?? item.plot {
                    Text(plot).font(.callout).foregroundStyle(.secondary)
                }

                if let url = item.streamURL {
                    let resumable = item.kind != .live && history.position(for: item.id) != nil
                    Button {
                        playing = Playable(url: url, title: item.title, key: item.id,
                                           kind: item.kind, itemRawID: item.rawID)
                    } label: {
                        Label(item.kind == .live ? "Watch live" : (resumable ? "Resume" : "Play"),
                              systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if hasEpisodes {
                    if loadingEpisodes { ProgressView() }
                    ForEach(seasons, id: \.self) { s in
                        Text("Season \(s)").font(.headline).padding(.top, 8)
                        ForEach(episodes.filter { $0.season == s }) { ep in
                            Button { play(ep) } label: { EpisodeRow(episode: ep) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.navy.ignoresSafeArea())
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playing) { p in
            PlayerView(item: p).environmentObject(history)
        }
    }

    private func load() async {
        if hasEpisodes {
            loadingEpisodes = true
            episodes = await library.episodes(for: item)
            loadingEpisodes = false
        } else if item.kind == .movie {
            details = await library.movieDetails(item)
        }
    }

    private func play(_ ep: Episode) {
        playing = Playable(url: ep.streamURL,
                           title: "\(item.title) · S\(ep.season)E\(ep.number)",
                           key: "series-\(item.rawID)-\(ep.id)",
                           kind: .series, itemRawID: item.rawID)
    }
}

struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: episode.image) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() } else { Theme.card }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.number). \(episode.title)").font(.subheadline.weight(.semibold)).lineLimit(2)
                if let plot = episode.plot {
                    Text(plot).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Add playlist

struct AddPlaylistView: View {
    var canCancel = false
    @EnvironmentObject private var store: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    @State private var source: Playlist.Source = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var m3u = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $source) {
                        Text("Xtream Codes").tag(Playlist.Source.xtream)
                        Text("M3U address").tag(Playlist.Source.m3u)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Details") {
                    TextField("Name (optional)", text: $name)
                    if source == .xtream {
                        TextField("Server, e.g. http://host:port", text: $server).keyboardType(.URL)
                        TextField("User name", text: $user)
                        SecureField("Password", text: $pass)
                    } else {
                        TextField("M3U address", text: $m3u).keyboardType(.URL)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Button { Task { await connect() } } label: {
                        if busy { ProgressView() } else { Text("Connect").frame(maxWidth: .infinity) }
                    }
                    .disabled(busy)
                }
                Section {
                    Text("This app does not provide any content. Add only playlists you are legally allowed to use.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Add playlist")
            .toolbar {
                if canCancel {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    @MainActor
    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if source == .xtream {
                let c = try XtreamClient(server: server, username: user, password: pass)
                try await c.authenticate()
                let p = Playlist(name: name.isEmpty ? server : name, source: .xtream,
                                 server: server, username: user)
                store.add(p, password: pass)
            } else {
                let trimmed = m3u.trimmingCharacters(in: .whitespacesAndNewlines)
                guard URL(string: trimmed) != nil, !trimmed.isEmpty else { throw XtreamError.invalidServer }
                let p = Playlist(name: name.isEmpty ? "M3U playlist" : name, source: .m3u, m3uURL: trimmed)
                store.add(p, password: nil)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var library: Library
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Playlists") {
                    ForEach(store.playlists) { p in
                        Button { store.activeID = p.id } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if p.id == store.activeID {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    .onDelete { idx in idx.map { store.playlists[$0] }.forEach(store.remove) }
                    Button("Add playlist") { adding = true }
                }
                Section {
                    Button("Refresh library") {
                        Task { if let p = store.active { await library.load(p) } }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $adding) { AddPlaylistView(canCancel: true) }
        }
    }
}

// MARK: Root

struct RootView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var library: Library

    var body: some View {
        Group {
            if store.active == nil {
                AddPlaylistView()
            } else {
                TabView {
                    HomeView().tabItem { Label("Home", systemImage: "house") }
                    BrowseView(kind: .movie, title: "Movies").tabItem { Label("Movies", systemImage: "film") }
                    BrowseView(kind: .series, title: "Series").tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
                    BrowseView(kind: .live, title: "Live TV").tabItem { Label("Live", systemImage: "tv") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .overlay {
                    if library.isLoading {
                        ProgressView("Loading library…")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .task(id: store.activeID) {
            if let p = store.active { await library.load(p) }
        }
    }
}
