import CoreFoundation
import Foundation

/// Assembles known mirror reads before the caller publishes any availability
/// effects. No SDK, reference, disk or network is constructed here.
enum ArticleMirrorCatalog {
    struct Source {
        let language: ArticleContentLanguage
        let documents: [(id: String, data: [String: Any])]
        let isFromCache: Bool
        let hasPendingWrites: Bool
    }

    enum Failure: Error { case invalidSource }

    struct ReadBatch {
        let sources: [Source]
        let failures: [ArticleContentLanguage: Error]
    }
    struct Namespace {
        let source: Source
        let articles: [Article]
        var isFresh: Bool { !source.isFromCache && !source.hasPendingWrites }
    }
    struct Update {
        let namespaces: [Namespace]
        let failures: [ArticleContentLanguage: Error]
        // Identity-validated withdrawals remain denials even when all public
        // rows in the same source fail body/metadata decoding.
        let validatedSources: [Source]
        let hadDecodeFailures: Bool
        var articles: [Article] { namespaces.flatMap(\.articles) }
        var freshLanguages: Set<ArticleContentLanguage> {
            Set(namespaces.filter(\.isFresh).map { $0.source.language })
        }
    }

    struct LanguageFailure: LocalizedError {
        let language: ArticleContentLanguage
        var errorDescription: String? {
            AppLocalization.string("Artiklerne kunne ikke opdateres. Prøv igen.", language: language)
        }
    }

    /// Decode each validated namespace independently, on the existing worker
    /// queue in production. A malformed public source cannot look like empty.
    static func decode(_ batch: ReadBatch) -> Update {
        var values: [Namespace] = [], failures = batch.failures, validated: [Source] = []
        var hadDecodeFailures = false
        let counts = Dictionary(grouping: batch.sources, by: \.language).mapValues(\.count)
        for source in batch.sources {
            do {
                guard counts[source.language] == 1, batch.failures[source.language] == nil else { throw Failure.invalidSource }
                try validate(source)
                validated.append(source)
                let decoded = try CMSArticleDocumentCodec.decodeFeed(source.documents)
                hadDecodeFailures = hadDecodeFailures || !decoded.failures.isEmpty
                values.append(Namespace(source: source, articles: decoded.articles))
                if decoded.articles.isEmpty && (source.isFromCache || source.hasPendingWrites) {
                    failures[source.language] = URLError(.cannotLoadFromNetwork)
                }
            } catch { failures[source.language] = error; hadDecodeFailures = true }
        }
        return Update(namespaces: values, failures: failures, validatedSources: validated, hadDecodeFailures: hadDecodeFailures)
    }

    typealias Deadline = @MainActor (@escaping @MainActor () -> Void) -> (() -> Void)

    /// Two independent reads, with one bounded observation and no retry. The
    /// outer feed deadline is12s;8s leaves budget for decoding/cache admission.
    /// Logical expiry does not claim cancellation of the underlying SDK query.
    @MainActor
    static func loadIndependently(englishEnabled: Bool,
        stillCurrent: @escaping @MainActor () -> Bool,
        scheduleDeadline: Deadline? = nil,
        read: @escaping @MainActor (ArticleContentLanguage) async throws -> Source) async throws -> ReadBatch {
        let languages: [ArticleContentLanguage] = englishEnabled ? [.danish, .english] : [.danish]
        let flight = ReadFlight(languages: languages, stillCurrent: stillCurrent)
        let result = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                flight.start(continuation, schedule: scheduleDeadline ?? defaultReadDeadline, read: read)
            }
        }, onCancel: { Task { @MainActor in flight.cancel() } })
        try Task.checkCancellation()
        guard stillCurrent() else { throw CancellationError() }
        return result
    }

    @MainActor private static func defaultReadDeadline(_ action: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            action()
        }
        return { timer.cancel() }
    }

    /// Per-call continuation ownership only; no persistent catalog state or
    /// service. Closed callbacks cannot publish into a later read flight.
    @MainActor private final class ReadFlight {
        let languages: [ArticleContentLanguage]
        let stillCurrent: @MainActor () -> Bool
        var remaining: Set<ArticleContentLanguage>
        var sources: [ArticleContentLanguage: Source] = [:]
        var failures: [ArticleContentLanguage: Error] = [:]
        var continuation: CheckedContinuation<ReadBatch, Error>?
        var cancelDeadline: (() -> Void)?
        var tasks: [Task<Void, Never>] = []
        var closed = false
        init(languages: [ArticleContentLanguage], stillCurrent: @escaping @MainActor () -> Bool) {
            self.languages = languages; self.remaining = Set(languages); self.stillCurrent = stillCurrent
        }
        func permitted() -> Bool {
            guard !closed else { return false }
            let allowed = stillCurrent()
            return allowed && !closed
        }
        func start(_ continuation: CheckedContinuation<ReadBatch, Error>, schedule: Deadline,
                   read: @escaping @MainActor (ArticleContentLanguage) async throws -> Source) {
            guard !closed else { continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            guard permitted() else { cancel(); return }
            let stopTimer = schedule { [self] in
                guard permitted() else { self.cancel(); return }
                for language in remaining { failures[language] = URLError(.timedOut) }
                finish(.success(ReadBatch(sources: languages.compactMap { sources[$0] }, failures: failures)))
            }
            guard !closed else { stopTimer(); return }
            cancelDeadline = stopTimer
            for language in languages {
                guard permitted() else { self.cancel(); return }
                let task = Task { @MainActor [self] in
                    guard permitted() else { cancel(); return }
                    do {
                        let source = try await read(language)
                        guard permitted() else { cancel(); return }
                        guard source.language == language else { throw Failure.invalidSource }
                        try validate(source)
                        guard permitted() else { cancel(); return }
                        sources[language] = source
                    } catch {
                        guard permitted() else { cancel(); return }
                        failures[language] = error
                    }
                    remaining.remove(language)
                    if remaining.isEmpty {
                        finish(.success(ReadBatch(sources: languages.compactMap { sources[$0] }, failures: failures)))
                    }
                }
                tasks.append(task)
            }
        }
        func cancel() { finish(.failure(CancellationError())) }
        func finish(_ result: Result<ReadBatch, Error>) {
            guard !closed else { return }
            closed = true
            let held = continuation; continuation = nil
            let stop = cancelDeadline; cancelDeadline = nil
            let active = tasks; tasks = []
            stop?(); active.forEach { $0.cancel() }
            held?.resume(with: result)
        }
    }

    /// A cached namespace cannot borrow another namespace's fresh server reply.
    /// The caller passes the decoded rows from these same completed sources.
    static func confirmedPublications(from articles: [Article], sources: [Source]) -> [Article] {
        guard Set(sources.map(\.language)).count == sources.count,
              sources.allSatisfy({ (try? validate($0)) != nil }) else { return [] }
        let currentIDs = Dictionary(uniqueKeysWithValues: sources.filter {
            !$0.isFromCache && !$0.hasPendingWrites
        }.map { source in
            (source.language, Set(source.documents.filter {
                !CMSMirrorDocumentPolicy.isWithdrawn($0.data)
            }.map(\.id)))
        })
        return articles.filter { article in
            guard article.hasValidContentIdentity, let language = article.contentLanguage,
                  currentIDs[language]?.contains(article.id) == true,
                  article.isDraft == false, article.isArchived != true,
                  Article.parseWebflowTimestamp(article.lastPublished) != nil else { return false }
            return true
        }
    }

    static func englishEnabled(in info: [String: Any]) -> Bool {
        guard let value = info["ReaderEnglishArticlesEnabled"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }

    /// Tombstones retain source identity even though their content is stripped.
    /// Validate those primitives before any row may withdraw a reader identity.
    static func validate(_ source: Source) throws {
        var seen = Set<String>()
        for document in source.documents {
            guard CMSMirrorDocumentPolicy.isSafeDocumentID(document.id),
                  seen.insert(document.id).inserted else { throw Failure.invalidSource }
            if let declaredID = document.data["id"] {
                guard declaredID as? String == document.id else { throw Failure.invalidSource }
            } else {
                // Existing Danish tombstones may contain only withdrawal
                // primitives. Their authoritative document slot owns the ID.
                guard source.language == .danish,
                      CMSMirrorDocumentPolicy.isWithdrawn(document.data) else { throw Failure.invalidSource }
            }
            for key in ["contentLanguage", "sourceArticleID", "cmsLocaleId"] {
                if let value = document.data[key], !(value is String),
                   !(key != "contentLanguage" && value is NSNull) { throw Failure.invalidSource }
            }
            guard let language = ArticleContentLanguage.validated(articleID: document.id,
                languageCode: document.data["contentLanguage"] as? String,
                sourceArticleID: document.data["sourceArticleID"] as? String,
                cmsLocaleId: document.data["cmsLocaleId"] as? String),
                  language == source.language else { throw Failure.invalidSource }
        }
    }

    @MainActor
    static func load(englishEnabled: Bool,
                     stillCurrent: @escaping @MainActor () -> Bool,
                     read: @escaping @MainActor (ArticleContentLanguage) async throws -> Source) async throws -> [Source] {
        func check() throws {
            guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        }
        var result: [Source] = []
        let languages: [ArticleContentLanguage] = englishEnabled ? [.danish, .english] : [.danish]
        for language in languages {
            try check()
            let source = try await read(language)
            try check()
            guard source.language == language else { throw Failure.invalidSource }
            try validate(source)
            try check()
            result.append(source)
        }
        try check()
        return result
    }
}
