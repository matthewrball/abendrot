import AVFoundation

// MARK: - OneShotPlayer

/// The shared lazy-engine core behind every one-shot UI sound (the confirmation chime, the advanced-panel
/// swoosh, the slider dial-tick). Each of those used to copy-paste the SAME `AVAudioEngine` + `AVAudioPlayerNode`
/// + `idleTask` plumbing with a byte-identical play body and idle-shutdown `Task`. This owns that plumbing once;
/// callers keep only their own node graph (which they wire onto `engine`/`player`) and their own buffer/file
/// recipe + idle constant.
///
/// `fire(…)` starts the engine on demand, retriggers cleanly on rapid re-fire (`player.stop()`), and idles the
/// engine `idleAfter` seconds after the (short) sound so its render thread doesn't run indefinitely.
@MainActor
final class OneShotPlayer {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    private var idleTask: Task<Void, Never>?

    /// Schedule + play a pre-rendered PCM buffer. `volume` is the per-fire loudness; `idleAfter` is the
    /// seconds-after-sound the engine waits before idling its render thread.
    func fire(buffer: AVAudioPCMBuffer, volume: Float, idleAfter: TimeInterval) {
        player.volume = volume
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.stop()                       // reset if a prior shot is still scheduled (rapid re-fire)
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        scheduleIdle(after: idleAfter)
    }

    /// Schedule + play an on-disk audio file (e.g. the system "Glass" chime). Same lifecycle as the buffer
    /// variant — only the source differs.
    func fire(file: AVAudioFile, volume: Float, idleAfter: TimeInterval) {
        player.volume = volume
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.stop()                       // reset if a prior shot is still scheduled (rapid re-fire)
        player.scheduleFile(file, at: nil)
        player.play()
        scheduleIdle(after: idleAfter)
    }

    /// Spin the engine up ahead of the first `fire(…)` so that first sound isn't delayed by render-thread
    /// startup (e.g. on a slider press, before the first detent is crossed). Idles itself after `idleAfter`
    /// if no shot follows (a press with no movement).
    func prewarm(idleAfter: TimeInterval) {
        if !engine.isRunning { try? engine.start() }
        scheduleIdle(after: idleAfter)
    }

    /// Stop the engine `seconds` after the (short) sound so the render thread doesn't run on forever.
    private func scheduleIdle(after seconds: TimeInterval) {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.player.isPlaying else { return }
            self.engine.stop()
        }
    }
}
