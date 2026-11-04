import Foundation

/// Legacy directory enumeration runs only when explicitly requested. No scan is
/// scheduled by CacheManager construction, and the synchronous I/O stays here.
actor CacheDirectorySizeWorker {
    func size(at directory: URL) -> Int64 {
        let manager = FileManager()
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return contents.reduce(into: Int64(0)) { size, url in
            if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { size += Int64(bytes) }
        }
    }
}
