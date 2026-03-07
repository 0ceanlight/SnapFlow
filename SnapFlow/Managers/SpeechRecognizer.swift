import Foundation
import Combine
import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    
    func toggleRecording() {
        if isRecording {
            stopTranscribing()
        } else {
            startTranscribing()
        }
    }
    
    func startTranscribing() {
        // Request permissions safely first
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    self.beginRecording()
                } else {
                    self.transcript = "Speech recognition permission denied."
                }
            }
        }
    }
    
    private func beginRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            request?.endAudio()
            isRecording = false
        }
        
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
        }
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        request.shouldReportPartialResults = true
        
        task = recognizer?.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.stopTranscribing()
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            transcript = "Listening..."
        } catch {
            print("Audio Engine failed to start")
        }
    }
    
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        
        isRecording = false
        request = nil
        task = nil
    }
}
