import XCTest
@testable import Apropos_Magazine

final class PodcastAudioCacheEvictionTests: XCTestCase {
    func testNoEvictionWhenUnderLimit() {
        let files = [("a", Int64(10)), ("b", Int64(20))]
        let evicted = PodcastAudioCache.keysToEvict(
            files: files, accessTimes: [:], pinnedKeys: [], maxBytes: 100
        )
        XCTAssertTrue(evicted.isEmpty)
    }

    func testEvictsLeastRecentlyUsedFirst() {
        let files = [("old", Int64(50)), ("new", Int64(50)), ("mid", Int64(50))]
        let access: [String: TimeInterval] = ["old": 1, "mid": 2, "new": 3]
        // total 150, max 100 -> free 50 -> evict only the oldest
        let evicted = PodcastAudioCache.keysToEvict(
            files: files, accessTimes: access, pinnedKeys: [], maxBytes: 100
        )
        XCTAssertEqual(evicted, ["old"])
    }

    func testEvictsMultipleUntilUnderLimit() {
        let files = [("a", Int64(40)), ("b", Int64(40)), ("c", Int64(40))]
        let access: [String: TimeInterval] = ["a": 1, "b": 2, "c": 3]
        // total 120, max 50 -> free 70 -> evict a (40) then b (40)
        let evicted = PodcastAudioCache.keysToEvict(
            files: files, accessTimes: access, pinnedKeys: [], maxBytes: 50
        )
        XCTAssertEqual(evicted, ["a", "b"])
    }

    func testPinnedFilesAreNeverEvicted() {
        let files = [("pinned", Int64(80)), ("free", Int64(80))]
        let access: [String: TimeInterval] = ["pinned": 1, "free": 2]
        // pinned is oldest but protected; only "free" can be evicted
        let evicted = PodcastAudioCache.keysToEvict(
            files: files, accessTimes: access, pinnedKeys: ["pinned"], maxBytes: 50
        )
        XCTAssertEqual(evicted, ["free"])
        XCTAssertFalse(evicted.contains("pinned"))
    }

    func testMissingAccessTimeTreatedAsOldest() {
        let files = [("known", Int64(60)), ("unknown", Int64(60))]
        let access: [String: TimeInterval] = ["known": 100]
        // total 120, max 60 -> free 60 -> the one without a timestamp is oldest
        let evicted = PodcastAudioCache.keysToEvict(
            files: files, accessTimes: access, pinnedKeys: [], maxBytes: 60
        )
        XCTAssertEqual(evicted, ["unknown"])
    }
}
