import Cocoa

struct RectangleManager {
    static let shared = RectangleManager()
    
    func executeAction(_ action: String) {
        if let url = URL(string: "rectangle://execute-action?name=\(action)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func leftHalf() { executeAction("left-half") }
    func rightHalf() { executeAction("right-half") }
    func maximize() { executeAction("maximize") }
    func center() { executeAction("center") }
}
