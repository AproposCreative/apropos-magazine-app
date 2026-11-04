import Combine
import CryptoKit
import Foundation
import Security

struct AppleSignInChallenge {
    let id: UUID
    let rawNonce: String
    let state: String
    var hashedNonce: String { SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func generate() throws -> Self {
        func randomHex() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AppleAccountFlowError.randomUnavailable
            }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return try Self(id: UUID(), rawNonce: randomHex(), state: randomHex())
    }
}

struct AppleIdentityResponse {
    let identityToken: Data?
    let state: String?
    let fullName: PersonNameComponents?
    let userID: String?
    init(identityToken: Data?, state: String?, fullName: PersonNameComponents?, userID: String? = nil) {
        self.identityToken = identityToken; self.state = state; self.fullName = fullName; self.userID = userID
    }
}

enum AppleAccountFlowError: Error { case randomUnavailable, invalidIdentity }

/// Owns one Apple → Firebase exchange; the injected operation keeps tests offline.
@MainActor
final class AppleAccountFlowModel: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    enum Purpose: Equatable { case login, reauthentication }
    let purpose: Purpose
    var isReauthentication: Bool { purpose == .reauthentication }
    var activeTicketID: UUID? { active?.challenge.id }
    typealias Perform = (String, String, PersonNameComponents?) async throws -> ReaderAccountSession?
    struct Operation {
        let perform: Perform
        var providerReturned: () throws -> Void = {}
        var providerFailed: () -> Bool = { true }
        var cancel: () -> Void = {}
        var feedbackIsCurrent: () -> Bool = { true }
        var expectedAppleUserID: String? = nil
    }
    private final class Request {
        let challenge: AppleSignInChallenge
        let operation: Operation
        var exchanging = false
        var cancelled = false
        init(challenge: AppleSignInChallenge, operation: Operation) {
            self.challenge = challenge; self.operation = operation
        }
    }
    var isWorking: Bool { active != nil }
    private(set) var errorMessage: String? { didSet { objectWillChange.send() } }
    private(set) var authenticatedSession: ReaderAccountSession? { didSet { objectWillChange.send() } }
    private var active: Request?
    private var admission = UUID()
    private let makeChallenge: () throws -> AppleSignInChallenge
    private let capture: () throws -> Operation
    private let preparationFailed: () -> Void

    init(purpose: Purpose = .login,
         makeChallenge: @escaping () throws -> AppleSignInChallenge = AppleSignInChallenge.generate,
         preparationFailed: @escaping () -> Void = {},
         capture: @escaping () throws -> Operation) {
        self.purpose = purpose; self.makeChallenge = makeChallenge; self.capture = capture
        self.preparationFailed = preparationFailed
    }
    convenience init(purpose: Purpose = .login,
                     makeChallenge: @escaping () throws -> AppleSignInChallenge = AppleSignInChallenge.generate,
                     perform: @escaping Perform) {
        self.init(purpose: purpose, makeChallenge: makeChallenge, capture: { Operation(perform: perform) })
    }

    /// Capture and provider admission happen in the native button event.
    func begin() -> AppleSignInChallenge? {
        guard active == nil else { return nil }
        let event = UUID(); admission = event
        do {
            let challenge = try makeChallenge()
            guard admission == event, active == nil else { return nil }
            guard !isReauthentication || (!challenge.rawNonce.isEmpty && !challenge.state.isEmpty) else { throw AppleAccountFlowError.invalidIdentity }
            let operation = try capture()
            guard admission == event, active == nil else {
                operation.cancel(); _ = operation.providerFailed(); return nil
            }
            let request = Request(challenge: challenge, operation: operation)
            active = request
            errorMessage = nil
            guard active === request, !request.cancelled else { drainUnpresented(request); return nil }
            authenticatedSession = nil
            guard active === request, !request.cancelled else { drainUnpresented(request); return nil }
            return challenge
        } catch is CancellationError { return nil }
        catch {
            guard admission == event, active == nil else { return nil }
            errorMessage = isReauthentication ? reauthenticationError : (error as? AuthOperationCoordinator.Failure)?.message ?? "Apple-login kunne ikke klargøres sikkert. Prøv igen."
            if isReauthentication, admission == event, active == nil { preparationFailed() }
            return nil
        }
    }

    func complete(ticketID: UUID, response: AppleIdentityResponse) async {
        guard let request = active, request.challenge.id == ticketID, !request.exchanging else { return }
        // This callback proves the provider returned. Cancelling its UI alone
        // never frees the slot; even a cancelled credential reply must drain it.
        do { try request.operation.providerReturned() }
        catch { finish(request); return }
        guard active === request, !request.cancelled else { request.operation.cancel(); finish(request); return }
        let challenge = request.challenge
        guard response.state == challenge.state,
              !isReauthentication || (request.operation.expectedAppleUserID.map { !$0.isEmpty && $0 == response.userID } == true),
              let tokenData = response.identityToken,
              let token = String(data: tokenData, encoding: .utf8), !token.isEmpty else {
            if owns(request) { errorMessage = isReauthentication ? reauthenticationError : "Apple-login kunne ikke gennemføres. Prøv igen." }
            request.operation.cancel(); finish(request); return
        }
        request.exchanging = true
        defer { finish(request) }
        do {
            let session = try await request.operation.perform(token, challenge.rawNonce, response.fullName)
            guard owns(request) else { return }
            if isReauthentication { return } // Reauthentication never publishes a replacement login session.
            authenticatedSession = session
            if session == nil, owns(request) { errorMessage = "Apple-login blev ikke bekræftet. Prøv igen." }
        } catch is CancellationError { }
        catch {
            guard owns(request) else { return }
            errorMessage = isReauthentication ? reauthenticationError : AccountErrorMessage.forError(error)
        }
    }

    /// Actual provider failure/cancellation callbacks release the original slot.
    func fail(ticketID: UUID, error: Error) {
        guard let request = active, request.challenge.id == ticketID, !request.exchanging else { return }
        let mayPublish = request.operation.providerFailed()
        if mayPublish, owns(request) { errorMessage = isReauthentication ? reauthenticationError : "Apple-login kunne ikke gennemføres. Prøv igen." }
        finish(request)
    }
    func providerCancelled(ticketID: UUID) {
        guard let request = active, request.challenge.id == ticketID, !request.exchanging else { return }
        cancel(ticketID: ticketID)
        _ = request.operation.providerFailed()
        finish(request)
    }
    func cancel(ticketID: UUID) {
        admission = UUID()
        guard let request = active, request.challenge.id == ticketID else { return }
        request.cancelled = true
        request.operation.cancel()
        // Provider/exchange has not returned, so the request remains busy.
    }
    func clearError() {
        // The alert action and its dismissal binding can both acknowledge the
        // same error. A second nil publication would occur during view updates.
        guard errorMessage != nil else { return }
        errorMessage = nil
    }
    /// Native presentation still belongs to this exact captured operation after
    /// controller factories and lifetime registration have had a chance to reenter.
    func canPresent(ticketID: UUID) -> Bool {
        guard let request = active, request.challenge.id == ticketID, !request.exchanging, !request.cancelled else { return false }
        let allowed = owns(request)
        guard allowed, active === request, request.challenge.id == ticketID, !request.exchanging, !request.cancelled else {
            if isReauthentication, active === request, !request.cancelled { cancel(ticketID: ticketID) }
            return false
        }
        return true
    }
    private var reauthenticationError: String { "Kunne ikke bekræfte din identitet med Apple. Prøv igen." }
    private func owns(_ request: Request) -> Bool {
        guard active === request, !request.cancelled else { return false }
        let allowed = request.operation.feedbackIsCurrent()
        return allowed && active === request && !request.cancelled
    }
    private func drainUnpresented(_ request: Request) {
        request.operation.cancel(); _ = request.operation.providerFailed(); finish(request)
    }
    private func finish(_ request: Request) {
        guard active === request else { return }
        active = nil
        objectWillChange.send()
    }
}
