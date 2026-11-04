import CryptoKit
import Darwin
import Foundation

/// Small device-local badge state shared by the app and its existing extension.
/// Every mutation reloads under the same cross-process lock; callers send deltas.
final class NotificationUnreadStore: @unchecked Sendable {
    struct Event: Codable, Equatable, Sendable {
        let key: String
        let languageCode: String?
        let date: Date
    }
    struct Projection: Equatable, Sendable {
        let count: Int
        let revision: UInt64
        let unread: [Event]
    }
    enum Failure: Error { case invalid, unavailable, busy, corrupt }
    private struct State: Codable, Equatable {
        var version = 1
        var revision: UInt64 = 0
        var unread: [Event] = []
        var read: [String] = []
        var deleted: [String] = []
    }
    static let appGroupID = "group.com.aproposmagazine.app"
    static let languagePreferenceKey = "widget_interface_language"
    private static let maximumBytes = 128 * 1024
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    static func key(forInboxIdentity identity: String) -> String {
        if publicationLanguage(identity) != nil { return identity }
        return "notification:" + digest(identity)
    }

    static func event(userInfo: [AnyHashable: Any], requestIdentifier: String, date: Date) -> Event? {
        guard !requestIdentifier.isEmpty, requestIdentifier.utf8.count <= 512,
              date.timeIntervalSince1970.isFinite else { return nil }
        let info = NotificationNavigation.normalize(userInfo)
        guard !["uid", "user_id", "userId", "owner_uid"].contains(where: { info[$0] != nil }),
              let payload = NotificationNavigation.payload(from: userInfo),
              payload.isArticleNotification || payload.isPodcastNotification,
              !payload.articleIdentifier.isEmpty, payload.articleIdentifier.utf8.count <= 256,
              !payload.articleIdentifier.contains("/"),
              payload.articleIdentifier.rangeOfCharacter(from: .controlCharacters) == nil,
              payload.articleSlug.map({ $0.utf8.count <= 256 }) ?? true else { return nil }
        let title = qualifiedPodcastTitle(payload.podcastTitle)
        let article = payload.isArticleNotification || (payload.type == "new_narration" && title == nil)
        if article {
            let key = "article-publication:" + payload.articleIdentifier
            if let language = publicationLanguage(key) { return Event(key: key, languageCode: language, date: date) }
            if payload.articleIdentifier.hasPrefix("en_") { return nil }
        }
        let identity = requestIdentifier.hasPrefix("article-publication:")
            ? "notification-delivery:" + digest(requestIdentifier) : requestIdentifier
        return Event(key: key(forInboxIdentity: identity), languageCode: nil, date: date)
    }

    static func qualifiedPodcastTitle(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 1_000 else { return nil }
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= 240 ? title : nil
    }
    static func isValidEvent(_ event: Event) -> Bool { validEvent(event) }
    static func isValidKey(_ key: String) -> Bool { validKey(key) }

    func snapshot(languageCode: String) throws -> Projection {
        try locked { state in Self.projection(state, languageCode: languageCode) }
    }

    func apply(received: [Event], read: [String] = [], deleted: [String] = [],
               languageCode: String) throws -> Projection {
        guard received.count <= 100, read.count <= 200, deleted.count <= 200,
              received.allSatisfy(Self.validEvent), (read + deleted).allSatisfy(Self.validKey) else { throw Failure.invalid }
        return try locked { state in
            let original = state
            for key in read { Self.remember(key, in: &state.read) }
            for key in deleted { Self.remember(key, in: &state.deleted) }
            let acknowledged = Set(state.read + state.deleted)
            state.unread.removeAll { acknowledged.contains($0.key) }
            for event in received where !acknowledged.contains(event.key) {
                if let index = state.unread.firstIndex(where: { $0.key == event.key }) {
                    if event.date < state.unread[index].date { state.unread[index] = event }
                } else { state.unread.append(event) }
            }
            state.unread.sort { $0.date == $1.date ? $0.key < $1.key : $0.date > $1.date }
            state.unread = Array(state.unread.prefix(100))
            if state != original {
                guard state.revision < UInt64.max else { throw Failure.corrupt }
                state.revision += 1
                try self.write(state)
            }
            return Self.projection(state, languageCode: languageCode)
        }
    }

    private func locked<T>(_ body: (inout State) throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw Failure.unavailable }
        let lockURL = directory.appendingPathComponent("unread-v1.lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, (attributes.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              attributes.st_nlink == 1 else { throw Failure.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw Failure.unavailable }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.busy }
            Thread.sleep(forTimeInterval: 0.002)
        }
        defer { flock(fd, LOCK_UN) }
        var state = try load()
        return try body(&state)
    }

    private func load() throws -> State {
        let url = directory.appendingPathComponent("unread-v1.json")
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return State() }
            throw Failure.unavailable
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, (attributes.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              attributes.st_nlink == 1, attributes.st_size >= 0,
              attributes.st_size <= Self.maximumBytes else { throw Failure.corrupt }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw Failure.corrupt }
        let state: State
        do { state = try JSONDecoder().decode(State.self, from: data) } catch { throw Failure.corrupt }
        guard state.version == 1, state.unread.count <= 100, state.read.count <= 200, state.deleted.count <= 200,
              state.unread.allSatisfy(Self.validEvent), (state.read + state.deleted).allSatisfy(Self.validKey),
              Set(state.unread.map(\.key)).count == state.unread.count,
              Set(state.read).count == state.read.count, Set(state.deleted).count == state.deleted.count,
              Set(state.unread.map(\.key)).isDisjoint(with: Set(state.read + state.deleted)) else { throw Failure.corrupt }
        return state
    }

    private func write(_ state: State) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maximumBytes else { throw Failure.invalid }
        let url = directory.appendingPathComponent("unread-v1.json")
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw Failure.unavailable }
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var destination = url; try destination.setResourceValues(values)
    }

    private static func projection(_ state: State, languageCode: String) -> Projection {
        let language = languageCode == "en" ? "en" : "da"
        return Projection(count: state.unread.filter { $0.languageCode == nil || $0.languageCode == language }.count,
                          revision: state.revision, unread: state.unread)
    }
    private static func remember(_ key: String, in list: inout [String]) {
        list.removeAll { $0 == key }; list.append(key)
        if list.count > 200 { list.removeFirst(list.count - 200) }
    }
    private static func validEvent(_ event: Event) -> Bool {
        guard validKey(event.key), event.date.timeIntervalSince1970.isFinite else { return false }
        if let language = publicationLanguage(event.key) { return event.languageCode == language }
        return event.languageCode == nil
    }
    private static func validKey(_ key: String) -> Bool {
        if publicationLanguage(key) != nil { return true }
        guard key.hasPrefix("notification:") else { return false }
        return hex(String(key.dropFirst("notification:".count)), count: 64)
    }
    private static func publicationLanguage(_ key: String) -> String? {
        guard key.hasPrefix("article-publication:") else { return nil }
        let id = String(key.dropFirst("article-publication:".count))
        if hex(id, count: 24) { return "da" }
        if id.hasPrefix("en_"), hex(String(id.dropFirst(3)), count: 24) { return "en" }
        return nil
    }
    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
