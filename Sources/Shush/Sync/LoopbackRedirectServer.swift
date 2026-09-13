import Darwin
import Foundation

/// A one-shot local HTTP listener on 127.0.0.1, for the OAuth redirect. Google's "Desktop app"
/// client type validates `redirect_uri` against RFC 8252's loopback flow, not an arbitrary
/// custom URL scheme — `shush://oauth-callback` gets rejected with "Error 400: invalid_request"
/// even though it's registered in Info.plist, because that registration only matters to macOS,
/// not to Google's own allow-list for this client type. A loopback address needs no
/// registration at all: Google accepts any `http://127.0.0.1:<port>/...` for this client type.
enum LoopbackRedirectServer {
    /// Binds an ephemeral port on loopback only (never LAN-reachable) and starts listening.
    /// Returns the socket so `awaitRedirect` can accept the single incoming request on it.
    static func start() throws -> (port: UInt16, socketFD: Int32) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SyncError.oauthCallbackInvalid }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // let the kernel pick an ephemeral port

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw SyncError.oauthCallbackInvalid
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) }
        }
        return (UInt16(bigEndian: bound.sin_port), fd)
    }

    /// Blocks on a background thread for the one incoming connection Google's redirect makes,
    /// parses its request-line query string, and answers with a small "you can close this" page
    /// so the browser tab doesn't just hang.
    static func awaitRedirect(socketFD: Int32) async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { close(socketFD) }
                let clientFD = accept(socketFD, nil, nil)
                guard clientFD >= 0 else {
                    continuation.resume(returning: [:])
                    return
                }
                defer { close(clientFD) }

                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = read(clientFD, &buffer, buffer.count)
                let requestText = bytesRead > 0 ? String(decoding: buffer[0..<bytesRead], as: UTF8.self) : ""

                let body = "<html><body>Signed in — you can close this window.</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n" + body
                _ = response.withCString { write(clientFD, $0, strlen($0)) }

                continuation.resume(returning: Self.parseQuery(from: requestText))
            }
        }
    }

    private static func parseQuery(from request: String) -> [String: String] {
        guard let requestLine = request.split(separator: "\r\n").first,
              let path = requestLine.split(separator: " ").dropFirst().first,
              let queryStart = path.firstIndex(of: "?")
        else { return [:] }

        var result: [String: String] = [:]
        for pair in path[path.index(after: queryStart)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return result
    }
}
