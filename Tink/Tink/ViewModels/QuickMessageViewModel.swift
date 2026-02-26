import Foundation

@Observable
final class QuickMessageViewModel {
    var message: String = ""
    var status: Status = .idle
    var history: [String] = []

    enum Status: Equatable {
        case idle, sending, sent, error(String)
    }

    func send() async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = message
        status = .sending
        do {
            try await SignalService.send(message: text)
            history.insert(text, at: 0)
            message = ""
            status = .sent
            try? await Task.sleep(for: .seconds(2))
            if status == .sent { status = .idle }
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
