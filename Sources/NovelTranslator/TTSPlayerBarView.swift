import SwiftUI
import AppKit

public struct TTSPlayerBarView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @ObservedObject var player: AudioPlayerManager

    public init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
        self.player = viewModel.audioPlayer
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Top Row: Title, Voice Picker, Speed, Close
            HStack(spacing: 8) {
                // Speaker Icon & Title
                Image(systemName: player.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .foregroundColor(.accentColor)
                    .font(.body)

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.currentTitle.isEmpty ? "Chapter Audio" : player.currentTitle)
                        .font(.caption.bold())
                        .lineLimit(1)

                    if viewModel.isSynthesizingAudio {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(viewModel.ttsStatusMessage ?? "Synthesizing speech...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = viewModel.ttsErrorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    } else {
                        Text("\(viewModel.ttsEngine.rawValue) • \(viewModel.selectedTTSVoiceId)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Voice Picker
                if !viewModel.availableTTSVoices.isEmpty {
                    Picker("", selection: $viewModel.selectedTTSVoiceId) {
                        ForEach(viewModel.availableTTSVoices) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 160)

                    Button(action: {
                        viewModel.testListeningCurrentVoice()
                    }) {
                        HStack(spacing: 2) {
                            if viewModel.isTestingTTSVoice {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "speaker.wave.1")
                            }
                            Text("Test")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isTestingTTSVoice)
                    .help("Test voice with sample phrase")
                }

                // Speed Picker
                Picker("", selection: $player.playbackRate) {
                    Text("0.75x").tag(Float(0.75))
                    Text("1.0x").tag(Float(1.0))
                    Text("1.25x").tag(Float(1.25))
                    Text("1.5x").tag(Float(1.5))
                    Text("2.0x").tag(Float(2.0))
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 70)

                // Stop / Close Button
                Button(action: {
                    player.stop()
                    viewModel.ttsErrorMessage = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close audio player")
            }

            // Bottom Row: Controls & Timeline Slider
            HStack(spacing: 8) {
                // Skip Backward 10s
                Button(action: { player.skip(by: -10) }) {
                    Image(systemName: "gobackward.10")
                }
                .buttonStyle(.plain)
                .disabled(player.duration == 0)
                .help("Skip backward 10s")

                // Play / Pause / Re-synthesize Button
                Button(action: {
                    if viewModel.isSynthesizingAudio { return }
                    viewModel.playCurrentChapterAudio()
                }) {
                    if viewModel.isSynthesizingAudio {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause" : "Play chapter")

                // Skip Forward 10s
                Button(action: { player.skip(by: 10) }) {
                    Image(systemName: "goforward.10")
                }
                .buttonStyle(.plain)
                .disabled(player.duration == 0)
                .help("Skip forward 10s")

                // Current Time
                Text(AudioPlayerManager.formatTime(player.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                // Scrubber Slider
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { newTime in
                            player.seek(to: newTime)
                        }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .controlSize(.small)
                .disabled(player.duration == 0)

                // Total Duration
                Text(AudioPlayerManager.formatTime(player.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}
