#if os(iOS)
import TodayCore
import TodayShared
import Foundation
import AVFoundation
#if canImport(AlarmKit)
import ActivityKit
#endif

/// The alarm tones bundled with the app (made by `Tools/make_alarm_sounds.py`). AlarmKit can ring the system alarm sound or a
/// sound file from the app, but not Apple's ringtones, so these are the choices in the editor's Sound row.
package struct AlarmSound: Identifiable, Hashable {
    package let name: String
    package var id: String { name }
    package var file: String { name.replacingOccurrences(of: " ", with: "") }

    package static let all: [AlarmSound] = ["Daybreak", "Chimes", "Marimba", "Glass", "Ripple", "Morning Piano", "Beacon", "Crystal"].map(AlarmSound.init)

    /// The tone saved on an alarm; nil for the system default (or a name that no longer exists).
    package static func named(_ name: String) -> AlarmSound? { all.first { $0.name == name } }

    package var url: URL? { Bundle.main.url(forResource: file, withExtension: "caf") }

    #if canImport(AlarmKit)
    package var alertSound: ActivityKit.AlertConfiguration.AlertSound { .named(file + ".caf") }
    #endif
}

@MainActor
package protocol SoundPreviewing: AnyObject {
    func play(_ sound: AlarmSound)
    func stop()
}

/// Plays a tone for a few seconds while the user is choosing one, and stops when it is told to or the screen goes.
@MainActor
package final class SoundPreview {
    package static let shared = SoundPreview()
    private var player: AVAudioPlayer?

    package func play(_ sound: AlarmSound) {
        stop()
        guard let url = sound.url else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }

    package func stop() {
        player?.stop()
        player = nil
    }
}

#endif
