import Darwin
import XCTest
@testable import Apropos

final class NotificationUnreadStoreTests: XCTestCase {
    private final class Errors: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Error] = []
        func add(_ error: Error) { lock.lock(); values.append(error); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UnreadStore-" + UUID().uuidString, isDirectory: true)
    }
    private func event(_ n: Int, english: Bool = false) -> NotificationUnreadStore.Event {
        let id = String(format: "%024x", n)
        return .init(key: "article-publication:" + (english ? "en_" : "") + id,
                     languageCode: english ? "en" : "da", date: Date(timeIntervalSince1970: Double(n)))
    }

    func testActualSharedFileCountsNewEventsOnceAndProjectsEachVisibleLanguage() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = NotificationUnreadStore(directory: dir), extensionStore = NotificationUnreadStore(directory: dir)
        let first = try app.apply(received: [event(1), event(2), event(1, english: true)], languageCode: "da")
        XCTAssertEqual(first.count, 2)
        let duplicate = try extensionStore.apply(received: [event(1)], languageCode: "da")
        XCTAssertEqual(duplicate.count, 2); XCTAssertEqual(duplicate.revision, first.revision)
        XCTAssertEqual(try extensionStore.snapshot(languageCode: "en").count, 1)
        XCTAssertEqual(try NotificationUnreadStore(directory: dir).snapshot(languageCode: "da"), duplicate)
    }

    func testReadDeleteDeltasWinOverStaleAppSnapshotAndDuplicateExtensionReceipt() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = NotificationUnreadStore(directory: dir), ext = NotificationUnreadStore(directory: dir)
        let old = event(1), new = event(2)
        _ = try ext.apply(received: [old], languageCode: "da")
        _ = try app.apply(received: [], read: [old.key], languageCode: "da")
        XCTAssertEqual(try ext.apply(received: [old], languageCode: "da").count, 0)
        _ = try ext.apply(received: [new], languageCode: "da")
        let latest = try app.apply(received: [old], deleted: [old.key], languageCode: "da")
        XCTAssertEqual(latest.unread.map(\.key), [new.key])
        XCTAssertEqual(try ext.apply(received: [old, new], languageCode: "da").count, 1)
    }

    func testIndependentInstancesSerializeConcurrentAppAndExtensionDeltas() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let initial = NotificationUnreadStore(directory: dir)
        _ = try initial.apply(received: [event(99)], languageCode: "da")
        let errors = Errors(), group = DispatchGroup()
        for worker in 0..<4 {
            let events = (1...5).map { event(worker * 5 + $0) }
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try NotificationUnreadStore(directory: dir).apply(received: events,
                        deleted: ["article-publication:" + String(format: "%024x", 99)], languageCode: "da")
                } catch { errors.add(error) }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(errors.count, 0)
        let final = try NotificationUnreadStore(directory: dir).snapshot(languageCode: "da")
        XCTAssertEqual(final.count, 20); XCTAssertEqual(Set(final.unread.map(\.key)).count, 20)
        XCTAssertFalse(final.unread.contains { $0.key == event(99).key })
    }

    func testSeparateOpenLockDescriptionsEnforceBoundedContention() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = NotificationUnreadStore(directory: dir)
        _ = try store.snapshot(languageCode: "da")
        let fd = Darwin.open(dir.appendingPathComponent("unread-v1.lock").path, O_RDWR | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd, 0); guard fd >= 0 else { return }
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try NotificationUnreadStore(directory: dir).snapshot(languageCode: "da")) {
            guard let failure = $0 as? NotificationUnreadStore.Failure,
                  case .busy = failure else { return XCTFail("Expected bounded lock contention") }
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
    }

    func testCorruptAndSymlinkStateNeverResetOrOverwriteUnrecognizedBytes() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = NotificationUnreadStore(directory: dir)
        _ = try store.snapshot(languageCode: "da")
        let state = dir.appendingPathComponent("unread-v1.json"), bad = Data("foreign bytes".utf8)
        try bad.write(to: state)
        XCTAssertThrowsError(try store.apply(received: [event(1)], languageCode: "da"))
        XCTAssertEqual(try Data(contentsOf: state), bad)
        try FileManager.default.removeItem(at: state)
        let retained = dir.appendingPathComponent("retained.json"); try bad.write(to: retained)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: retained)
        XCTAssertThrowsError(try store.apply(received: [event(1)], languageCode: "da"))
        XCTAssertEqual(try Data(contentsOf: retained), bad)
    }

    func testActualPayloadIdentityMatchesCoreAndRejectsPrivateOrMalformedData() throws {
        let article = String(format: "%024x", 1)
        let info: [AnyHashable: Any] = ["type": "new_narration", "article_id": article]
        let date = Date(timeIntervalSince1970: 100)
        let event = try XCTUnwrap(NotificationUnreadStore.event(userInfo: info, requestIdentifier: "push", date: date))
        let item = try XCTUnwrap(NotificationInboxItem.make(id: "push", title: "Title", body: "Body", date: date, userInfo: info))
        XCTAssertEqual(event.key, NotificationUnreadStore.key(forInboxIdentity: item.inboxIdentity))
        XCTAssertEqual(event.languageCode, item.articlePublicationLanguage?.rawValue)
        var privateInfo = info; privateInfo["uid"] = "private"
        XCTAssertNil(NotificationUnreadStore.event(userInfo: privateInfo, requestIdentifier: "push", date: date))
        XCTAssertNil(NotificationUnreadStore.event(userInfo: ["type": "test"], requestIdentifier: "test", date: date))
        XCTAssertNil(NotificationUnreadStore.event(userInfo: ["type": "new_article", "article_id": "en_invalid"], requestIdentifier: "x", date: date))
        let audio: [AnyHashable: Any] = ["type": "new_narration", "article_id": article, "podcast_title": "Audio"]
        XCTAssertNil(try XCTUnwrap(NotificationUnreadStore.event(userInfo: audio, requestIdentifier: "audio", date: date)).languageCode)
    }
}
