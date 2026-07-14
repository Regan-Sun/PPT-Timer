import AppKit
import AVFoundation
import Foundation

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?

    func play(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp3") else {
            NSSound.beep()
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            NSSound.beep()
        }
    }
}
