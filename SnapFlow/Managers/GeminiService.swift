import Foundation
import EventKit
import GoogleGenerativeAI
import Combine

struct AIEventBlock: Codable {
    let title: String
    let startTime: String
    let durationMinutes: Int
    let notes: String
}

class GeminiService: ObservableObject {
    static let shared = GeminiService()
    
    func scheduleFromTranscript(_ transcript: String) async throws {
        let apiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API Key. Please add it in preferences."])
        }
        
        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
        
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let nowString = df.string(from: Date())
        
        let prompt = """
        You are an intelligent scheduling assistant. The user will provide a natural language transcript of tasks.
        Generate a strictly formatted JSON array of events starting from the current time. Do not overlap events.
        Format MUST strictly be exactly this JSON array with nothing else before or after: 
        [
          { "title": "Example", "startTime": "14:00", "durationMinutes": 60, "notes": "example note" }
        ]
        
        Ensure you append a 🤖 emoji to the start of each title.
        The current time is \(nowString). If no specific start time is mentioned, start the schedule from the current time or the next logical slot (round to nearest 5 minutes). 
        Ensure there are NO overlapping events.
        Unless specified otherwise (e.g. with fixed start/end times or durations).
        Also unless specified otherwise, make sure the schedule is gap-free such that the end time of one event is the start time of the next event.
        
        Here is the user request: 
        "\(transcript)"
        """
        
        let response = try await model.generateContent(prompt)
        guard let text = response.text else {
            throw NSError(domain: "Gemini", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response from Gemini"])
        }
        
        try await parseAndInjectEvents(jsonText: text)
    }
    
    private func parseAndInjectEvents(jsonText: String) async throws {
        let pattern = "(?s)\\[.*\\]"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(jsonText.startIndex..., in: jsonText)
        
        guard let match = regex.firstMatch(in: jsonText, range: range),
              let jsonRange = Range(match.range, in: jsonText) else {
            throw NSError(domain: "Gemini", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not extract JSON"])
        }
        
        let cleanJSON = String(jsonText[jsonRange])
        guard let data = cleanJSON.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        let blocks = try decoder.decode([AIEventBlock].self, from: data)
        
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        for block in blocks {
            guard let time = Formatter.timeOnly.date(from: block.startTime) ?? dateFormatter.date(from: block.startTime) else { continue }
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            
            if let targetDate = Calendar.current.date(byAdding: components, to: today) {
                await MainActor.run {
                    CalendarManager.shared.insertEvent(
                        title: block.title,
                        startDate: targetDate,
                        durationMinutes: block.durationMinutes,
                        notes: block.notes
                    )
                }
            }
        }
    }
}

extension Formatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
