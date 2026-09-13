import Foundation

/// Drive v3 REST calls scoped to `appDataFolder` — a private, per-app storage space that needs
/// only the `drive.appdata` scope and never shows up in the user's normal Drive UI. Built
/// directly on `URLSession`, no Drive SDK, per this codebase's hand-roll ethos.
@MainActor
struct DriveClient {
    private let auth: GoogleAuthService
    /// Caches `name -> fileId` so a repeated sync of the same file skips the lookup call.
    private static var fileIDCache: [String: String] = [:]

    init(auth: GoogleAuthService = .shared) {
        self.auth = auth
    }

    // MARK: - Named singleton files (settings.json, dictionary.json)

    func upload<T: Encodable>(_ payload: T, name: String) async throws {
        let data = try JSONEncoder.sync.encode(payload)
        if let fileID = try await findFileID(name: name) {
            try await update(fileID: fileID, data: data)
        } else {
            try await create(name: name, data: data, appProperties: nil)
        }
    }

    func download<T: Decodable>(_ type: T.Type, name: String) async throws -> T? {
        guard let fileID = try await findFileID(name: name) else { return nil }
        let data = try await downloadContent(fileID: fileID)
        guard let decoded = try? JSONDecoder.sync.decode(T.self, from: data) else {
            throw SyncError.decodeFailed
        }
        return decoded
    }

    // MARK: - Per-device stats files

    /// Uploads always as a full overwrite — each device is the sole writer of its own file, so
    /// there's never anything to merge before writing.
    func uploadStats(_ payload: DeviceStatsPayload) async throws {
        let name = "stats-\(payload.deviceID).json"
        let data = try JSONEncoder.sync.encode(payload)
        if let fileID = try await findFileID(name: name) {
            try await update(fileID: fileID, data: data)
        } else {
            try await create(name: name, data: data, appProperties: ["kind": "stats"])
        }
    }

    /// Lists every device's stats file via the `kind=stats` custom property, so new devices
    /// are discovered without needing to know their UUIDs up front.
    func downloadAllStats() async throws -> [DeviceStatsPayload] {
        let token = try await auth.validAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "appProperties has {key='kind' and value='stats'}"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)

        struct FileList: Decodable {
            struct File: Decodable { let id: String; let name: String }
            let files: [File]
        }
        let list = try JSONDecoder().decode(FileList.self, from: data)

        var results: [DeviceStatsPayload] = []
        for file in list.files {
            let content = try await downloadContent(fileID: file.id)
            if let payload = try? JSONDecoder.sync.decode(DeviceStatsPayload.self, from: content) {
                results.append(payload)
            }
        }
        return results
    }

    // MARK: - Primitives

    private func findFileID(name: String) async throws -> String? {
        if let cached = Self.fileIDCache[name] { return cached }

        let token = try await auth.validAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name='\(name)'"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)

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
        let token = try await auth.validAccessToken()
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

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)

        struct CreatedFile: Decodable { let id: String }
        if let created = try? JSONDecoder().decode(CreatedFile.self, from: responseData) {
            Self.fileIDCache[name] = created.id
        }
    }

    private func update(fileID: String, data: Data) async throws {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)
    }

    private func downloadContent(fileID: String) async throws -> Data {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)
        return data
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.driveAPI(status: status, message: "request failed")
        }
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
