import SwiftUI

struct SettingsView: View {
    @State private var geminiAPIKeyInput: String = ""
    @State private var showSaveMessage: Bool = false

    @AppStorage("gemini_api_key") private var storedGeminiAPIKey: String = ""
    @AppStorage("default_input_mode") private var defaultInputMode: String = "voice"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Gemini API Key ────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.headline)

                HStack(spacing: 8) {
                    SecureField("Paste your key here…", text: $geminiAPIKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save") { saveAPIKey() }
                        .disabled(geminiAPIKeyInput.isEmpty)
                }

                if showSaveMessage {
                    Text("Key saved!")
                        .foregroundColor(.green)
                        .font(.caption)
                        .transition(.opacity)
                }

                Text("Your Gemini API key is stored in your app's preferences. Obtain it from Google AI Studio.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // ── Default Scheduler Input ───────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Scheduler Input")
                    .font(.headline)

                Picker("", selection: $defaultInputMode) {
                    Text("Voice").tag("voice")
                    Text("Keyboard").tag("keyboard")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Choose whether the scheduler opens in voice or keyboard mode by default. You can always switch inside the scheduler window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 380, height: 250)
    }

    private func saveAPIKey() {
        storedGeminiAPIKey = geminiAPIKeyInput
        geminiAPIKeyInput = ""
        withAnimation { showSaveMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaveMessage = false }
        }
    }
}

#Preview {
    SettingsView()
}
