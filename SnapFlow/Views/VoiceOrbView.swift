import SwiftUI

enum InputMode {
    case voice, keyboard
}

struct VoiceOrbView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @ObservedObject private var hotkeyManager = HotKeyManager.shared

    // Load the user's preferred default; falls back to voice
    @AppStorage("default_input_mode") private var defaultModeRaw: String = "voice"
    @State private var inputMode: InputMode = .voice

    @State private var keyboardText: String = ""
    @State private var isPulsing = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    @FocusState private var textFieldFocused: Bool

    private var isVoiceMode: Bool { inputMode == .voice }

    var body: some View {
        VStack(spacing: 16) {

            // ── Orb ──────────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(orbColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: orbColor, radius: isPulsing ? 30 : 10)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)

                Image(systemName: isVoiceMode ? "mic.fill" : "keyboard")
                    .foregroundColor(.white)
                    .font(.largeTitle)
            }
            .onTapGesture {
                if isVoiceMode {
                    if speechRecognizer.isRecording {
                        stopAndProcess(text: speechRecognizer.transcript)
                    } else {
                        errorMessage = nil
                        speechRecognizer.startTranscribing()
                    }
                } else {
                    // In keyboard mode tapping the orb submits
                    guard !keyboardText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    stopAndProcess(text: keyboardText)
                }
            }

            // ── Transcript / Text input ───────────────────────────
            if isVoiceMode {
                if !speechRecognizer.transcript.isEmpty {
                    Text(speechRecognizer.transcript)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Material.ultraThin)
                        .cornerRadius(10)
                }
            } else {
                // Keyboard text field — grabs focus automatically
                TextField("e.g. Deep work for 2h, then lunch 30m…", text: $keyboardText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Material.ultraThin)
                    .cornerRadius(10)
                    .focused($textFieldFocused)
                    .onSubmit { stopAndProcess(text: keyboardText) }
                    // Smart switch: pressing Enter while voice has content will have been
                    // handled by onSubmit above — the text field only appears in keyboard mode.
            }

            // ── Status messages ───────────────────────────────────
            if isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
                Text("Synthesizing schedule…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // ── Mode toggle button ────────────────────────────────
            Button {
                switchMode(to: isVoiceMode ? .keyboard : .voice)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isVoiceMode ? "keyboard" : "mic.fill")
                    Text(isVoiceMode ? "Switch to Typing" : "Switch to Voice")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Material.thin)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help(isVoiceMode ? "Switch to keyboard input" : "Switch to voice input")
        }
        .padding(28)
        .frame(width: 320, height: isVoiceMode ? 280 : 300)
        .onAppear {
            inputMode = defaultModeRaw == "keyboard" ? .keyboard : .voice
        }
        // Smart switch: if the user starts typing while orb has no voice content yet, jump to keyboard
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // handled via keyDown below
        }
        .onChange(of: hotkeyManager.isVoiceOrbVisible) { _, newValue in
            if newValue {
                // Reset to default mode on open
                inputMode = defaultModeRaw == "keyboard" ? .keyboard : .voice
                errorMessage = nil
                if inputMode == .voice {
                    isPulsing = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        textFieldFocused = true
                    }
                }
            } else {
                isPulsing = false
                if speechRecognizer.isRecording { speechRecognizer.stopTranscribing() }
            }
        }
        .onChange(of: speechRecognizer.isRecording) { _, newValue in
            isPulsing = newValue
        }
        // Smart switch: keystrokes in voice mode with empty transcript → jump to keyboard
        .background(KeyEventInterceptor { char in
            guard isVoiceMode, !isProcessing else { return }
            guard speechRecognizer.transcript.isEmpty else {
                // There's spoken content already; Enter sends it, other keys are ignored
                if char == "\r" || char == "\n" {
                    stopAndProcess(text: speechRecognizer.transcript)
                }
                return
            }
            // No voice content yet and user is typing → switch to keyboard and seed the field
            if !char.isNewline {
                switchMode(to: .keyboard)
                keyboardText = String(char)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    textFieldFocused = true
                }
            }
        })
    }

    // MARK: - Helpers

    private var orbColor: Color {
        if isProcessing { return .orange }
        if isVoiceMode && speechRecognizer.isRecording { return .red }
        if !isVoiceMode { return .indigo }
        return .blue
    }

    private func switchMode(to mode: InputMode) {
        if mode == .voice && speechRecognizer.isRecording { speechRecognizer.stopTranscribing() }
        if mode == .keyboard { keyboardText = "" }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { inputMode = mode }
        if mode == .keyboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { textFieldFocused = true }
        } else {
            isPulsing = true
        }
    }

    private func stopAndProcess(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if isVoiceMode { speechRecognizer.stopTranscribing() }
        keyboardText = ""
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                try await GeminiService.shared.scheduleFromTranscript(clean)
                await MainActor.run {
                    speechRecognizer.transcript = ""
                    isProcessing = false
                    hotkeyManager.isVoiceOrbVisible = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Key Event Interceptor

/// Transparent overlay that forwards the first character to a callback,
/// allowing the orb to detect when the user starts typing in voice mode.
struct KeyEventInterceptor: NSViewRepresentable {
    let onChar: (Character) -> Void

    func makeNSView(context: Context) -> KeyCatchView {
        let v = KeyCatchView()
        v.onChar = onChar
        return v
    }
    func updateNSView(_ nsView: KeyCatchView, context: Context) {
        nsView.onChar = onChar
    }
}

class KeyCatchView: NSView {
    var onChar: ((Character) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters, let ch = chars.first {
            onChar?(ch)
        } else {
            super.keyDown(with: event)
        }
    }
}
