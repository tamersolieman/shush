import Foundation

/// Drive v3 REST calls scoped to `appDataFolder` — a private, per-app storage space that needs
/// only the `drive.appdata` scope and never shows up in the user's normal Drive UI. Built
/// directly on `URLSession`, no Drive SDK, per this codebase's hand-roll ethos.
@MainActor
struct DriveClient {
    private let auth: GoogleAuthService
    /// Caches `name -> fileId` so a repeated sync of the same file skips the lookup call.
    private static var fileIDCache: [String: String] = [:]
    /// `fileId -> (modifiedTime, content)` for the per-device files, see `downloadAll`.
    private static var contentCache: [String: (modified: String, data: Data)] = [:]

    /// A Drive file listing with modification times. Declared here because Swift won't nest a
    /// type inside the generic `downloadAll`.
    private struct TimedFileList: Decodable {
        struct File: Decodable { let id: String; let name: String; let modifiedTime: String? }
        let files: [File]
    }

    init(auth: GoogleAuthService = .shared) {
        self.auth = auth
    }

    // MARK: - Named singleton files (settings.json, dictionary.json, snippets.json)

    func upload<T: Encodable>(_ payload: T, name: String) async throws {
        try await upsert(name: name, data: JSONEncoder.sync.encode(payload), appProperties: nil)
    }

    func download<T: Decodable>(_ type: T.Type, name: String) async throws -> T? {
        guard let fileID = try await findFileID(name: name) else { return nil }
        let data: Data
        do {
            data = try await downloadContent(fileID: fileID)
        } catch SyncError.driveAPI(let status, _) where status == 404 {
            // The cached id outlived the file (deleted from Drive): forget it, report no copy.
            Self.fileIDCache[name] = nil
            return nil
        }
        guard let decoded = try? JSONDecoder.sync.decode(T.self, from: data) else {
            throw SyncError.decodeFailed
        }
        return decoded
    }

    // MARK: - Per-device stats files

    /// Uploads always as a full overwrite — each device is the sole writer of its own file, so
    /// there's never anything to merge before writing.
    func uploadStats(_ payload: DeviceStatsPayload) async throws {
        try await upsert(
            name: "stats-\(payload.deviceID).json",
            data: JSONEncoder.sync.encode(payload),
            appProperties: ["kind": "stats"]
        )
    }

    func downloadAllStats() async throws -> [DeviceStatsPayload] {
        try await downloadAll(kind: "stats", as: DeviceStatsPayload.self)
    }

    // MARK: - Per-device transcript files

    func uploadRuns(_ payload: DeviceRunsPayload) async throws {
        try await upsert(
            name: "runs-\(payload.deviceID).json",
            data: JSONEncoder.sync.encode(payload),
            appProperties: ["kind": "runs"]
        )
    }

    func downloadAllRuns() async throws -> [DeviceRunsPayload] {
        try await downloadAll(kind: "runs", as: DeviceRunsPayload.self)
    }

    /// Lists every device's file of one kind via its `kind` custom property, so new devices
    /// are discovered without needing to know their UUIDs up front. A file whose Drive
    /// `modifiedTime` hasn't moved is served from memory instead of downloaded again, which
    /// keeps a sync cycle cheap when nothing changed.
    private func downloadAll<T: Decodable>(kind: String, as type: T.Type) async throws -> [T] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "appProperties has {key='kind' and value='\(kind)'}"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime)"),
        ]
        let url = components.url!
        let data = try await send { Self.authorized(URLRequest(url: url), token: $0) }
        let list = try JSONDecoder().decode(TimedFileList.self, from: data)

        var results: [T] = []
        for file in list.files {
            let content: Data
            if let modified = file.modifiedTime, let cached = Self.contentCache[file.id], cached.modified == modified {
                content = cached.data
            } else {
                content = try await downloadContent(fileID: file.id)
                if let modified = file.modifiedTime { Self.contentCache[file.id] = (modified, content) }
            }
            if let payload = try? JSONDecoder.sync.decode(T.self, from: content) {
                results.append(payload)
            }
        }
        return results
    }

    // MARK: - Primitives

    /// Updates the named file, or creates it. A cached id that Drive no longer knows (the file
    /// was deleted) is dropped and looked up fresh, rather than failing every cycle after.
    private func upsert(name: String, data: Data, appProperties: [String: String]?) async throws {
        for _ in 0..<2 {
            guard let fileID = try await findFileID(name: name) else { break }
            do {
                try await update(fileID: fileID, data: data)
                return
            } catch SyncError.driveAPI(let status, _) where status == 404 {
                Self.fileIDCache[name] = nil
            }
        }
        try await create(name: name, data: data, appProperties: appProperties)
    }

    private func findFileID(name: String) async throws -> String? {
        if let cached = Self.fileIDCache[name] { return cached }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name='\(name)'"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime)"),
        ]
        let url = components.url!
        let data = try await send { Self.authorized(URLRequest(url: url), token: $0) }

        struct FileList: Decodable {
            struct File: Decodable { let id: String; let name: String; let modifiedTime: String? }
            let files: [File]
        }
        let list = try JSONDecoder().decode(FileList.self, from: data)
        // appDataFolder is exclusively Shush's own writes, so a name collision would be a bug
        // rather than a real Drive-wide naming conflict — fall back to the newest if it ever
        // happens rather than crashing.
        let match = list.files.max { ($0.modifiedTime ?? "") < ($1.modifiedTime ?? "") }
        guard let fileID = match?.id else { return nil }
        Self.fileIDCache[name] = fileID
        return fileID
    }

    private func create(name: String, data: Data, appProperties: [String: String]?) async throws {
        var metadata: [String: Any] = ["name": name, "parents": ["appDataFolder"]]
        if let appProperties { metadata["appProperties"] = appProperties }
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        let boundary = "shush-sync-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8Data)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".utf8Data)
        body.append("Content-Type: application/json\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n--\(boundary)--".utf8Data)

        let responseData = try await send { token in
            var request = Self.authorized(
                URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!),
                token: token
            )
            request.httpMethod = "POST"
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }

        struct CreatedFile: Decodable { let id: String }
        if let created = try? JSONDecoder().decode(CreatedFile.self, from: responseData) {
            Self.fileIDCache[name] = created.id
        }
    }

    private func update(fileID: String, data: Data) async throws {
        _ = try await send { token in
            var request = Self.authorized(
                URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!),
                token: token
            )
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            return request
        }
    }

    private func downloadContent(fileID: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!
        return try await send { Self.authorized(URLRequest(url: url), token: $0) }
    }

    // MARK: - Transport

    private static func authorized(_ request: URLRequest, token: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Sends a request with a valid token, and absorbs the failures that say nothing about the
    /// data: a 401 gets one forced token refresh, and a 429 or 5xx a couple of short retries.
    /// Anything else — including a 404, which callers interpret — is thrown as it came.
    private func send(_ build: (String) -> URLRequest) async throws -> Data {
        var token = try await auth.validAccessToken()
        var refreshed = false
        var attempts = 0

        while true {
            let (data, response) = try await URLSession.shared.data(for: build(token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 401, !refreshed {
                refreshed = true
                token = try await auth.refreshAccessToken()
                continue
            }
            if (status == 429 || status >= 500), attempts < 2 {
                attempts += 1
                try await Task.sleep(for: .seconds(attempts))
                continue
            }
            guard (200...299).contains(status) else {
                throw SyncError.driveAPI(status: status, message: Self.errorMessage(in: data))
            }
            return data
        }
    }

    /// Drive's own explanation ("Drive API has not been used in project…") beats a bare status.
    private static func errorMessage(in body: Data) -> String {
        struct Failure: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail?
        }
        return (try? JSONDecoder().decode(Failure.self, from: body))?.error?.message ?? "request failed"
    }
}

extension JSONEncoder {
    static let sync: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let sync: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension String {
    var utf8Data: Data { data(using: .utf8) ?? Data() }
}
