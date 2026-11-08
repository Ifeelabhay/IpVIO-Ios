import SwiftUI
import AVKit

final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    private var token: Any?

    func start(_ url: URL, resumeAt: Double?) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if let resumeAt, resumeAt > 5 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        player.play()
    }

    func observe(every seconds: Double, _ handler: @escaping (Double, Double) -> Void) {
        token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: seconds, preferredTimescale: 1), queue: .main
        ) { [weak self] t in
            let d = self?.player.currentItem?.duration.seconds ?? 0
            handler(t.seconds, d.isFinite ? d : 0)
        }
    }

    func stop() {
        if let token { player.removeTimeObserver(token) }
        token = nil
        player.pause()
    }
}

struct PlayerView: View {
    let item: Playable
    @EnvironmentObject private var history: History
    @StateObject private var model = PlayerModel()

    var body: some View {
        VideoPlayer(player: model.player)
            .ignoresSafeArea()
            .background(Color.black)
            .onAppear {
                model.start(item.url, resumeAt: item.kind == .live ? nil : history.position(for: item.key))
                if item.kind != .live {
                    model.observe(every: 10) { pos, dur in
                        history.update(key: item.key, kind: item.kind, itemRawID: item.itemRawID,
                                       title: item.title, position: pos, duration: dur)
                    }
                }
            }
            .onDisappear { model.stop() }
    }
}
