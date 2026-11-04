import Combine
import Foundation

/// A memory-only opt-in owned by one accepted login and canonical email.
/// Construction and observation never create consent or initialize a service.
@MainActor
final class ReaderNewsletterSignupModel: ObservableObject {
    struct Request: Codable, Equatable, Sendable {
        let requestID: String
        let expectedUserID: String
        let expectedEmail: String
        let consent: Bool
        let consentVersion: String
        let source: String
        let reconfirmationChallenge: String?

        init(requestID: String = UUID().uuidString.lowercased(), expectedUserID: String, expectedEmail: String,
             reconfirmationChallenge: String? = nil) {
            self.requestID = requestID
            self.expectedUserID = expectedUserID
            self.expectedEmail = expectedEmail
            consent = true
            consentVersion = "apropos-newsletter-v1"
            source = "ios-onboarding"
            self.reconfirmationChallenge = reconfirmationChallenge
        }

        private enum CodingKeys: String, CodingKey {
            case requestID, expectedUserID, expectedEmail, consent, consentVersion, source, reconfirmationChallenge
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(requestID, forKey: .requestID)
            try values.encode(expectedUserID, forKey: .expectedUserID)
            try values.encode(expectedEmail, forKey: .expectedEmail)
            try values.encode(consent, forKey: .consent)
            try values.encode(consentVersion, forKey: .consentVersion)
            try values.encode(source, forKey: .source)
            // Explicit null advertises the new protocol. Legacy six-field
            // clients must continue to receive legacy two-field responses.
            if let reconfirmationChallenge { try values.encode(reconfirmationChallenge, forKey: .reconfirmationChallenge) }
            else { try values.encodeNil(forKey: .reconfirmationChallenge) }
        }
    }

    enum ResponseStatus: String, Codable, Sendable, CaseIterable {
        case subscribed, alreadySubscribed, verificationRequired, reconfirmationRequired, pending, unavailable
    }

    struct Response: Codable, Equatable, Sendable {
        let status: ResponseStatus
        let requestID: String
        let reconfirmationChallenge: String?

        init(status: ResponseStatus, requestID: String, reconfirmationChallenge: String? = nil) {
            self.status = status; self.requestID = requestID
            self.reconfirmationChallenge = reconfirmationChallenge
        }
        private enum CodingKeys: String, CodingKey { case status, requestID, reconfirmationChallenge }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            status = try values.decode(ResponseStatus.self, forKey: .status)
            requestID = try values.decode(String.self, forKey: .requestID)
            reconfirmationChallenge = try values.decodeIfPresent(String.self, forKey: .reconfirmationChallenge)
            guard hasValidChallenge else {
                throw DecodingError.dataCorruptedError(forKey: .reconfirmationChallenge, in: values,
                    debugDescription: "Invalid newsletter reconfirmation response")
            }
        }
        var hasValidChallenge: Bool {
            reconfirmationChallenge == nil || (status == .reconfirmationRequired && ReaderNewsletterSignupModel.validChallenge(reconfirmationChallenge))
        }
    }

    enum Status: Equatable {
        case idle, submitting, subscribed, alreadySubscribed, verificationRequired, reconfirmationRequired, pending, unavailable
    }

    typealias Sender = @MainActor (Request, CanonicalSessionState.ContextTicket) async throws -> Response

    nonisolated let objectWillChange = ObservableObjectPublisher()
    var status: Status { presentation }
    var requestID: String? { intent?.request.requestID }
    /// UI work for the current opt-in. A revoked transport may still be draining.
    var isWorking: Bool { status == .submitting }
    var canRetry: Bool {
        guard let intent, flight == nil, owns(intent), canonical?.snapshot.session?.isEmailVerified == true else { return false }
        return status == .unavailable || status == .pending || status == .verificationRequired
    }
    var canReconfirm: Bool {
        guard status == .reconfirmationRequired, let intent, flight == nil,
              owns(intent), canonical?.snapshot.session?.isEmailVerified == true else { return false }
        return Self.validChallenge(intent.reconfirmationChallenge)
    }
    var message: String? {
        switch status {
        case .idle: return nil
        case .submitting: return "Tilmelder dig nyhedsbrevet…"
        case .subscribed: return "Du er tilmeldt Apropos’ nyhedsbrev."
        case .alreadySubscribed: return "Du er allerede tilmeldt Apropos’ nyhedsbrev."
        case .verificationRequired: return "Bekræft din e-mail for at afslutte tilmeldingen til nyhedsbrevet."
        case .reconfirmationRequired:
            return canReconfirm
                ? "Adressen er tidligere afmeldt. Tryk på Tilmeld igen, hvis du vil modtage nyhedsbrevet."
                : "Adressen er tidligere afmeldt. Vælg nyhedsbrevet igen for at lave en ny tilmelding."
        case .pending: return "Tilmeldingen er endnu ikke bekræftet. Prøv igen for at kontrollere den."
        case .unavailable: return "Nyhedsbrevstilmeldingen kunne ikke bekræftes. Prøv igen."
        }
    }

    private struct Intent {
        let request: Request
        let context: CanonicalSessionState.ContextTicket
        var verified: Bool
        var verificationRevision: UInt64 = 0
        var needsSend: Bool
        var reconfirmationChallenge: String? = nil
    }
    private struct Flight {
        let id: UUID
        let requestID: String
        let verificationRevision: UInt64
        var task: Task<Void, Never>?
    }

    private weak var canonical: CanonicalSessionState?
    private let send: Sender
    private var observation: AnyCancellable?
    private var intent: Intent?
    // Cancellation revokes UI ownership, not an HTTP request already accepted.
    // Keep this one physical slot until the transport actually returns.
    private var flight: Flight?
    private var presentation: Status = .idle
    private var publication = UUID()
    private var notifying = false

    init(canonical: CanonicalSessionState, send: @escaping Sender) {
        self.canonical = canonical
        self.send = send
        observation = canonical.changes.sink { [weak self] snapshot in self?.observe(snapshot) }
    }

    /// The caller must use the exact accepted auth operation or an explicit,
    /// owner-bound signed-in opt-in. A generic auth listener must never call begin.
    @discardableResult
    func begin(session: ReaderAccountSession, context: CanonicalSessionState.ContextTicket) -> Bool {
        begin(session: session, context: context, freshExplicitChoice: false)
    }

    /// A new checked choice is distinct from repeated delivery of one accepted
    /// login and from a network retry of an already admitted request.
    @discardableResult
    func beginExplicitOptIn(session: ReaderAccountSession, context: CanonicalSessionState.ContextTicket) -> Bool {
        begin(session: session, context: context, freshExplicitChoice: true)
    }

    private func begin(session: ReaderAccountSession, context: CanonicalSessionState.ContextTicket,
                       freshExplicitChoice: Bool) -> Bool {
        guard let canonical, canonical.isCurrent(context), context.userID == session.uid,
              let current = canonical.snapshot.session, current.uid == session.uid,
              current.email == session.email, Self.validEmail(current.email) else { return false }
        if let intent, intent.context == context, intent.request.expectedUserID == current.uid,
           intent.request.expectedEmail == current.email {
            // Repeated delivery of the accepted login is not a new subscription.
            let terminal = status == .subscribed || status == .alreadySubscribed || status == .reconfirmationRequired
            if !freshExplicitChoice || !terminal { return true }
        }
        // Replace the old intent before the single publication below. Publishing
        // an intermediate idle state could let a nested begin/cancel be undone.
        intent = nil
        flight?.task?.cancel()
        let request = Request(expectedUserID: current.uid, expectedEmail: current.email)
        let verified = canonical.snapshot.session?.isEmailVerified == true
        intent = Intent(request: request, context: context, verified: verified, needsSend: verified)
        guard publish(verified ? .submitting : .verificationRequired, for: request.requestID) else { return false }
        startIfPossible()
        return intent?.request.requestID == request.requestID && canonical.isCurrent(context)
    }

    @discardableResult
    func retry() -> Bool {
        guard canRetry, let requestID = intent?.request.requestID else { return false }
        intent?.needsSend = true
        guard publish(.submitting, for: requestID) else { return false }
        startIfPossible()
        return intent?.request.requestID == requestID
    }

    /// Only the existing primary button may redeem a server challenge. An
    /// ordinary response, retry, auth observation or form appearance cannot.
    @discardableResult
    func reconfirm() -> Bool {
        guard canReconfirm, var current = intent, let challenge = current.reconfirmationChallenge else { return false }
        let original = current.request
        current = Intent(request: Request(requestID: original.requestID,
            expectedUserID: original.expectedUserID, expectedEmail: original.expectedEmail,
            reconfirmationChallenge: challenge), context: current.context,
            verified: current.verified, verificationRevision: current.verificationRevision, needsSend: true)
        intent = current
        guard publish(.submitting, for: original.requestID) else { return false }
        startIfPossible()
        return intent?.request.requestID == original.requestID
    }

    func cancel() {
        intent = nil
        flight?.task?.cancel()
        _ = publish(.idle, for: nil)
    }

    private func owns(_ candidate: Intent) -> Bool {
        guard let canonical else { return false }
        return canonical.isCurrent(candidate.context)
            && canonical.snapshot.session?.uid == candidate.request.expectedUserID
            && canonical.snapshot.session?.email == candidate.request.expectedEmail
    }

    private func observe(_ snapshot: CanonicalSessionState.Snapshot) {
        guard var current = intent else { return }
        guard owns(current), snapshot.generation == current.context.generation,
              snapshot.session?.email == current.request.expectedEmail else { cancel(); return }
        let verified = snapshot.session?.isEmailVerified == true
        let becameVerified = !current.verified && verified
        current.verified = verified
        if becameVerified {
            current.verificationRevision &+= 1
            if status == .verificationRequired { current.needsSend = true }
        }
        intent = current
        if current.needsSend && verified { startIfPossible() }
    }

    private func startIfPossible() {
        guard flight == nil, let current = intent, current.needsSend, owns(current),
              canonical?.snapshot.session?.isEmailVerified == true else { return }
        let id = UUID()
        flight = Flight(id: id, requestID: current.request.requestID,
                        verificationRevision: current.verificationRevision, task: nil)
        guard publish(.submitting, for: current.request.requestID),
              maySend(id: id, requestID: current.request.requestID) else {
            finish(id: id, result: .failure(CancellationError()))
            return
        }
        intent?.needsSend = false
        let sender = send, request = current.request, context = current.context
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.maySend(id: id, requestID: request.requestID) == true else {
                self?.finish(id: id, result: .failure(CancellationError()))
                return
            }
            let result: Result<Response, Error>
            do { result = .success(try await sender(request, context)) }
            catch { result = .failure(error) }
            self?.finish(id: id, result: result)
        }
        if flight?.id == id { flight?.task = task }
        else { task.cancel() }
    }

    private func maySend(id: UUID, requestID: String) -> Bool {
        guard flight?.id == id, let current = intent, current.request.requestID == requestID else { return false }
        return owns(current) && canonical?.snapshot.session?.isEmailVerified == true
    }

    private func finish(id: UUID, result: Result<Response, Error>) {
        guard let completed = flight, completed.id == id else { return }
        flight = nil
        guard var current = intent else { return }
        guard owns(current) else { cancel(); return }
        guard current.request.requestID == completed.requestID else {
            // A separately accepted new opt-in can proceed after the old sender
            // returns. No payload or result is ever reassigned to that new owner.
            _ = publish(status, for: current.request.requestID)
            startIfPossible()
            return
        }
        let next: Status
        switch result {
        case .success(let response) where response.requestID == current.request.requestID && response.hasValidChallenge:
            current.reconfirmationChallenge = nil
            switch response.status {
            case .subscribed: next = .subscribed
            case .alreadySubscribed: next = .alreadySubscribed
            case .verificationRequired:
                next = .verificationRequired
                // Only a real false→true canonical verification change during
                // this send justifies an automatic follow-up, never a retry loop.
                current.needsSend = current.verified && current.verificationRevision > completed.verificationRevision
            case .reconfirmationRequired:
                next = .reconfirmationRequired
                current.reconfirmationChallenge = response.reconfirmationChallenge
            case .pending: next = .pending
            case .unavailable: next = .unavailable
            }
        case .success: next = .unavailable
        case .failure(let error):
            if error is CancellationError {
                next = canonical?.snapshot.session?.isEmailVerified == false ? .verificationRequired : .pending
            } else { next = .unavailable }
        }
        if next != .verificationRequired { current.needsSend = false }
        intent = current
        guard publish(next, for: current.request.requestID) else { return }
        startIfPossible()
    }

    /// Serialize publication around synchronous ObservableObject subscribers.
    /// A nested cancellation/account change invalidates the outer assignment.
    @discardableResult
    private func publish(_ value: Status, for requestID: String?) -> Bool {
        let token = UUID()
        publication = token
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard publication == token else { return false }
        if let requestID {
            guard let current = intent, current.request.requestID == requestID, owns(current) else { return false }
        } else if intent != nil { return false }
        presentation = value
        return true
    }

    private static func validEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return email.count <= 254 && parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && parts[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
            && !email.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }
    nonisolated static func validChallenge(_ value: String?) -> Bool {
        guard let value, value.utf8.count == 36 else { return false }
        return value.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }
}
