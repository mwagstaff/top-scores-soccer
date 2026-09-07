import AVFAudio
import OSLog

/// A short, original cue. Ambient audio mixes with music and obeys Silent Mode.
@MainActor
final class WhistlePlayer {
    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "uk.co.mwagstaff.TopScoresSoccer", category: "Whistle")

    func prepare() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "referee-whistle", withExtension: "wav") else {
            logger.error("Whistle resource is missing; visual foul feedback remains available.")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let sound = try AVAudioPlayer(contentsOf: url)
            sound.volume = 0.45
            sound.prepareToPlay()
            player = sound
        } catch {
            logger.error("Whistle playback could not be prepared: \(error.localizedDescription)")
        }
    }

    func play() {
        if player == nil { prepare() }
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
