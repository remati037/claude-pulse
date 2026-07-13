import Foundation
import Network

/// Lokalni HTTP server (§2.2, ADR-003). `NWListener` iz Network.framework, ručni minimalni
/// HTTP/1.1 parsing (samo `POST /status` i `GET /health`). Bind **isključivo** `127.0.0.1`.
final class HTTPServer {
    /// Maksimalna veličina tela (§2.2). Veći payload → 400 bez daljeg parsiranja.
    private static let maxBodyBytes = 4096
    /// Ceo request (headeri + telo) tvrdo ograničen da spori/zli klijent ne pojede memoriju.
    private static let maxRequestBytes = 16 * 1024

    private let port: UInt16
    private let statusStore: StatusStore
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.marko.claudepulse.http")

    init(port: UInt16, statusStore: StatusStore) {
        self.port = port
        self.statusStore = statusStore
    }

    func start() {
        do {
            let params = NWParameters.tcp
            // Nepregovarljivo: vezuj se samo za loopback (CLAUDE.md / ADR-003).
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLog.info("HTTP server ready on 127.0.0.1:\(self.port)")
                case .failed(let error):
                    AppLog.error("HTTP server failed: \(error)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            AppLog.error("HTTP server could not start on port \(port): \(error)")
        }
    }

    // MARK: - Konekcije

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > Self.maxRequestBytes {
                self.respond(connection, status: 400, json: #"{"ok":false,"error":"request too large"}"#)
                return
            }

            if let request = HTTPRequest(buffer: buffer) {
                // Ceo request stigao → obradi.
                self.route(connection, request: request)
                return
            }

            if error != nil || isComplete {
                // Konekcija se zatvorila pre kompletnog requesta.
                self.respond(connection, status: 400, json: #"{"ok":false,"error":"incomplete request"}"#)
                return
            }

            // Još nema ceo request → nastavi da čitaš.
            self.receive(connection, buffer: buffer)
        }
    }

    // MARK: - Rutiranje

    private func route(_ connection: NWConnection, request: HTTPRequest) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            respond(connection, status: 200, json: #"{"ok":true,"version":"\#(version)"}"#)

        case ("POST", "/status"):
            handleStatus(connection, request: request)

        default:
            respond(connection, status: 404, json: #"{"ok":false,"error":"not found"}"#)
        }
    }

    private func handleStatus(_ connection: NWConnection, request: HTTPRequest) {
        if request.body.count > Self.maxBodyBytes {
            respond(connection, status: 400, json: #"{"ok":false,"error":"body too large"}"#)
            return
        }

        struct StatusPayload: Decodable {
            let source: String
            let state: String
            struct Meta: Decodable { let title: String? }
            let meta: Meta?
        }

        guard let payload = try? JSONDecoder().decode(StatusPayload.self, from: request.body) else {
            respond(connection, status: 400, json: #"{"ok":false,"error":"invalid json"}"#)
            return
        }

        // `desktop` stiže in-process (Phase 4), ne preko HTTP-a → prihvataj samo code/web.
        guard payload.source == "code" || payload.source == "web",
              let source = Source(rawValue: payload.source) else {
            respond(connection, status: 400, json: #"{"ok":false,"error":"invalid source"}"#)
            return
        }
        // `inactive` je interno stanje; API prima samo busy/waiting/done.
        guard payload.state == "busy" || payload.state == "waiting" || payload.state == "done",
              let state = SourceState(rawValue: payload.state) else {
            respond(connection, status: 400, json: #"{"ok":false,"error":"invalid state"}"#)
            return
        }

        Task { @MainActor in
            self.statusStore.apply(source: source, state: state)
        }
        respond(connection, status: 200, json: #"{"ok":true}"#)
    }

    // MARK: - Odgovor

    private func respond(_ connection: NWConnection, status: Int, json: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }

        let body = Data(json.utf8)
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"

        var out = Data(response.utf8)
        out.append(body)

        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Minimalni parser HTTP/1.1 requesta. Vraća `nil` dok ceo request (headeri + telo po
/// `Content-Length`) nije stigao — pozivalac tada čita dalje.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(buffer: Data) {
        // Traži kraj headera: `\r\n\r\n`.
        let separator = Data("\r\n\r\n".utf8)
        guard let range = buffer.range(of: separator) else { return nil }

        let headerData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        self.method = String(parts[0])
        // Odbaci query string ako postoji.
        self.path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])

        // Content-Length (case-insensitive).
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = range.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength {
            // Telo još nije celo stiglo.
            return nil
        }
        self.body = buffer.subdata(in: bodyStart..<buffer.index(bodyStart, offsetBy: contentLength))
    }
}
