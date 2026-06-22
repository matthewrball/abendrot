import Foundation
import AVFoundation

// MARK: - ConfirmationChime

/// A tiny reusable AVAudioEngine graph that plays the system "Glass" chime, optionally pitch-shifted.
/// Built once; `play(pitchCents:)` re-triggers it. 0 cents = the bright Glass (warming ON); a negative
/// value plays it deeper + dampened (warming OFF). Real pitch shifting (not `AVAudioPlayer.rate`, which
/// only time-stretches and preserves pitch). Main-actor; the engine idles itself a few seconds after the
/// (short) chime so its render thread doesn't run forever.
@MainActor
final class ConfirmationChime {
    private let core = OneShotPlayer()
    private let pitch = AVAudioUnitTimePitch()
    private let file: AVAudioFile

    init?() {
        guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")) else {
            return nil
        }
        file = f
        core.engine.attach(core.player)
        core.engine.attach(pitch)
        core.engine.connect(core.player, to: pitch, format: file.processingFormat)
        core.engine.connect(pitch, to: core.engine.mainMixerNode, format: file.processingFormat)
        core.engine.mainMixerNode.outputVolume = 0.5
    }

    func play(pitchCents: Float, volume: Float = 1.0) {
        pitch.pitch = pitchCents
        // per-play loudness; warming = 1.0, mode tick = quieter. Engine idles 3s after the (sub-2s) chime.
        core.fire(file: file, volume: volume, idleAfter: 3)
    }
}

/// An airy, light "swoosh" for the advanced popover panel — no audio asset; two buffers rendered once.
/// Recipe: white noise HIGH-PASSED (cutoff sweeps so only the "air" is kept — no mid body, which read
/// as hard), then gently low-passed (~7.5 kHz ceiling) so it shimmers like frosted glass instead of
/// hissing, on a soft clickless raised-cosine envelope over ~0.3 s. OPEN sweeps the cutoff UP (rising,
/// "opening"); CLOSE sweeps it DOWN (falling, "settling") — the only difference, so they read as a
/// pair. Same lazy main-actor engine pattern as `ConfirmationChime`; the engine idles after the shot.
@MainActor
final class SwooshSound {
    private let core = OneShotPlayer()
    private let openBuffer: AVAudioPCMBuffer
    private let closeBuffer: AVAudioPCMBuffer

    init?() {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate * 0.32)   // ~0.3 s one-shot
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let open = Self.render(rising: true, format: format, frames: frames, sampleRate: sampleRate),
              let close = Self.render(rising: false, format: format, frames: frames, sampleRate: sampleRate)
        else { return nil }
        openBuffer = open
        closeBuffer = close
        core.engine.attach(core.player)
        core.engine.connect(core.player, to: core.engine.mainMixerNode, format: format)
    }

    /// Render one swoosh buffer. `rising` sweeps the high-pass cutoff UP (open); `false` sweeps it DOWN
    /// (close). Reversing that sweep is the ONLY difference between the paired open/close sounds.
    private static func render(rising: Bool, format: AVAudioFormat, frames: AVAudioFrameCount,
                               sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames

        // ponytail: taste-tune by ear — "airy & light like frosted glass" = high-passed AIR (no mid
        // body/resonance — that read as "hard"), softly smoothed so it shimmers not hisses, and quiet.
        // Widen [lo, hi] for a bigger sweep; lower fcLP for a softer/darker top.
        let lo = 1500.0, hi = 4200.0            // high-pass cutoff sweep ends (Hz)
        let hpStart = rising ? lo : hi          // open rises lo→hi; close falls hi→lo
        let hpEnd = rising ? hi : lo
        let fcLP = 7500.0                        // soft ceiling → frosted-glass smooth, not gritty
        let aLP = 1.0 - exp(-2.0 * Double.pi * fcLP / sampleRate)
        var lpHP = 0.0, lpOut = 0.0
        let n = Int(frames)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let fcHP = hpStart + (hpEnd - hpStart) * t
            let aHP = 1.0 - exp(-2.0 * Double.pi * fcHP / sampleRate)
            let white = Double.random(in: -1...1)
            lpHP += aHP * (white - lpHP)            // low-pass at the HP cutoff…
            let hp = white - lpHP                   // …subtracted → one-pole high-pass: keep only the air
            lpOut += aLP * (hp - lpOut)             // gentle top smoothing → frosted, not fizzy
            let env = pow(sin(Double.pi * t), 1.4)  // soft raised cosine (tapered = lighter); 0 at ends
            out[i] = Float(max(-1.0, min(1.0, lpOut * env * 0.5)))   // low internal gain → headroom, no clip
        }
        return buf
    }

    func play(opening: Bool, volume: Float) {
        core.fire(buffer: opening ? openBuffer : closeBuffer, volume: volume, idleAfter: 2)
    }
}
