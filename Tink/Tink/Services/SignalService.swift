import Foundation

struct SignalService {
    static var endpoint: URL {
        let stored = UserDefaults.standard.string(forKey: "signalEndpoint")
            ?? "http://192.168.68.58:8080/send"
        return URL(string: stored)!
    }

    static func send(message: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["message": message])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
