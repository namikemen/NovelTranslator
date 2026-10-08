import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    public static let shared = AudioPlayerManager()

    // MARK: - Published State
    @Published public var isPlaying: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var isPreparing: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            audioPlayer?.rate = playbackRate
        }
    }
    @Published public var volume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = volume
        }
    }
    @Published public var currentTitle: String = ""
    @Published public var currentAudioURL: URL? = nil
    @Published public var errorMessage: String? = nil

    // Private Player & Synthesizer
    private var audioPlayer: AVAudioPlayer?
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var timer: Timer?

    public override init() {
        super.init()
        setupCacheDirectory()
    }

    // MARK: - Playback Control

    public func loadAndPlay(url: URL, title: String = "") {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Audio file not found at \(url.lastPathComponent)"
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            player.volume = volume
            player.prepareToPlay()

            self.audioPlayer = player
            self.currentAudioURL = url
            self.currentTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
            self.duration = player.duration
            self.currentTime = 0

            if player.play() {
                self.isPlaying = true
                self.isPaused = false
                startTimer()
            } else {
                self.errorMessage = "Failed to start audio playback."
            }
        } catch {
            self.errorMessage = "Could not initialize audio player: \(error.localizedDescription)"
        }
    }

    public func play() {
        guard let player = audioPlayer else { return }
        if player.play() {
            isPlaying = true
            isPaused = false
            startTimer()
        }
    }

    public func pause() {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isPlaying = false
            isPaused = true
            stopTimer()
        } else if let synth = speechSynthesizer, synth.isSpeaking {
            synth.pauseSpeaking(at: .immediate)
            isPlaying = false
            isPaused = true
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            if audioPlayer != nil {
                play()
            } else if let synth = speechSynthesizer, synth.isPaused {
                synth.continueSpeaking()
                isPlaying = true
                isPaused = false
            }
        }
    }

    public func stop() {
        stopTimer()
        if let player = audioPlayer {
            player.stop()
            self.audioPlayer = nil
        }
        if let synth = speechSynthesizer {
            synth.stopSpeaking(at: .immediate)
            self.speechSynthesizer = nil
        }
        isPlaying = false
        isPaused = false
        currentTime = 0
    }

    public func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration))
        if let player = audioPlayer {
            player.currentTime = target
            currentTime = target
        }
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func setRate(_ rate: Float) {
        playbackRate = rate
    }

    // MARK: - Native Apple Speech Direct Playback

    public func speakLiveWithApple(text: String, voiceIdentifier: String, title: String) {
        stop()

        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        self.speechSynthesizer = synth
        self.currentTitle = title

        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * playbackRate

        synth.speak(utterance)
        isPlaying = true
        isPaused = false
        duration = Double(text.count) * 0.06 // rough estimation for progress bar
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.isPaused = false
            self.currentTime = self.duration
            self.stopTimer()
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.errorMessage = error?.localizedDescription ?? "Audio decode error"
            self.stop()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.isPaused = false
            self.stop()
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.isPaused = false
            self.stop()
        }
    }

    // MARK: - Cache Directory

    public var cacheDirectory: URL {
        let fm = FileManager.default
        let cacheBase = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return cacheBase.appendingPathComponent("NovelTranslator/TTS", isDirectory: true)
    }

    private func setupCacheDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedAudioURL(for bookTitle: String, chapterIndex: Int, voiceId: String, suffix: String = "") -> URL {
        let safeBook = bookTitle
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .prefix(30)
        let safeVoice = voiceId
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let extra = suffix.isEmpty ? "" : "_\(suffix)"
        let filename = "\(safeBook)_ch\(chapterIndex)_\(safeVoice)\(extra).wav"
        return cacheDirectory.appendingPathComponent(filename)
    }

    public func hasCachedAudio(for bookTitle: String, chapterIndex: Int, voiceId: String, suffix: String = "") -> Bool {
        let url = cachedAudioURL(for: bookTitle, chapterIndex: chapterIndex, voiceId: voiceId, suffix: suffix)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // Formatted time helper (e.g. "02:45")
    public nonisolated static func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, !seconds.isInfinite, seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
