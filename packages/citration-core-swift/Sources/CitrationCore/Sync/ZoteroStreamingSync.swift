import Foundation

// MARK: - ZoteroStreamingError

public enum ZoteroStreamingError: Error, Equatable, Sendable {
    case invalidStreamingURL
    case protocolViolation
    case subscriptionRejected
}

// MARK: - ZoteroStreamingSubscription

public final class ZoteroStreamingSubscription: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        reports: AsyncThrowingStream<ZoteroPullReport, any Error>,
        task: Task<Void, Never>
    ) {
        self.reports = reports
        self.task = task
    }

    deinit {
        task.cancel()
    }

    // MARK: Public

    public let reports: AsyncThrowingStream<ZoteroPullReport, any Error>

    public func cancel() {
        task.cancel()
    }

    // MARK: Private

    private let task: Task<Void, Never>
}

// MARK: - ZoteroStreamingSync

public struct ZoteroStreamingSync: Sendable {
    // MARK: Lifecycle

    public init(
        database: CitrationDatabase,
        client: ZoteroAPIClient,
        connection: ZoteroConnection,
        session: URLSession = .shared
    ) {
        self.database = database
        self.client = client
        self.connection = connection
        self.session = session
    }

    // MARK: Public

    public func subscribe() -> ZoteroStreamingSubscription {
        let pair = AsyncThrowingStream<ZoteroPullReport, any Error>.makeStream()
        let task = Task {
            await run(continuation: pair.continuation)
        }
        pair.continuation.onTermination = { _ in task.cancel() }
        return ZoteroStreamingSubscription(reports: pair.stream, task: task)
    }

    // MARK: Private

    private let database: CitrationDatabase
    private let client: ZoteroAPIClient
    private let connection: ZoteroConnection
    private let session: URLSession

    private func run(
        continuation: AsyncThrowingStream<ZoteroPullReport, any Error>.Continuation
    ) async {
        guard let streamingURL = connection.streamingURL else {
            continuation.finish(throwing: ZoteroStreamingError.invalidStreamingURL)
            return
        }
        while !Task.isCancelled {
            do {
                try await runConnection(streamingURL: streamingURL, continuation: continuation)
            } catch is CancellationError {
                break
            } catch let retry as ZoteroStreamingRetry {
                do {
                    try await Task.sleep(for: .milliseconds(retry.milliseconds))
                } catch {
                    break
                }
            } catch {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    break
                }
            }
        }
        continuation.finish()
    }

    private func runConnection(
        streamingURL: URL,
        continuation: AsyncThrowingStream<ZoteroPullReport, any Error>.Continuation
    ) async throws {
        let keyInfo = try await client.keyInfo()
        let topic = "/users/\(keyInfo.userID)"
        let webSocket = session.webSocketTask(with: streamingURL)
        webSocket.resume()
        defer { webSocket.cancel(with: .goingAway, reason: nil) }

        let connected = try await receive(from: webSocket)
        guard connected.event == "connected" else {
            throw ZoteroStreamingError.protocolViolation
        }
        let retry = min(max(connected.retry ?? 10000, 1000), 300_000)
        do {
            try await runSubscribedConnection(
                webSocket: webSocket,
                keyInfo: keyInfo,
                topic: topic,
                continuation: continuation
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ZoteroStreamingRetry(milliseconds: retry)
        }
    }

    private func runSubscribedConnection(
        webSocket: URLSessionWebSocketTask,
        keyInfo: ZoteroKeyInfo,
        topic: String,
        continuation: AsyncThrowingStream<ZoteroPullReport, any Error>.Continuation
    ) async throws {
        try await sendSubscription(topic: topic, webSocket: webSocket)
        let subscribed = try await receive(from: webSocket)
        guard
            subscribed.event == "subscriptionsCreated",
            subscribed.subscriptions?.contains(where: { $0.topics.contains(topic) }) == true
        else {
            throw ZoteroStreamingError.subscriptionRejected
        }

        let initial = try await ZoteroSyncEngine(database: database, client: client).pullReadOnly()
        continuation.yield(initial)
        while !Task.isCancelled {
            let event = try await receive(from: webSocket)
            guard event.event == "topicUpdated", event.topic == topic, let version = event.version else {
                continue
            }
            let identity = ZoteroLibraryIdentity(type: "user", remoteID: keyInfo.userID)
            guard try version > (database.libraryVersion(identity: identity)) else {
                continue
            }
            let report = try await ZoteroSyncEngine(database: database, client: client).pullReadOnly()
            continuation.yield(report)
        }
    }

    private func sendSubscription(topic: String, webSocket: URLSessionWebSocketTask) async throws {
        let request = ZoteroStreamingRequest(
            action: "createSubscriptions",
            subscriptions: [ZoteroStreamingRequestSubscription(apiKey: connection.apiKey, topics: [topic])]
        )
        let data = try JSONEncoder().encode(request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ZoteroStreamingError.protocolViolation
        }
        try await webSocket.send(.string(text))
    }

    private func receive(from webSocket: URLSessionWebSocketTask) async throws -> ZoteroStreamingMessage {
        let message = try await webSocket.receive()
        let data: Data = switch message {
        case let .data(value):
            value
        case let .string(value):
            Data(value.utf8)
        @unknown default:
            throw ZoteroStreamingError.protocolViolation
        }
        return try JSONDecoder().decode(ZoteroStreamingMessage.self, from: data)
    }
}

// MARK: - ZoteroStreamingRequest

private struct ZoteroStreamingRequest: Encodable {
    let action: String
    let subscriptions: [ZoteroStreamingRequestSubscription]
}

// MARK: - ZoteroStreamingRequestSubscription

private struct ZoteroStreamingRequestSubscription: Encodable {
    let apiKey: String
    let topics: [String]
}

// MARK: - ZoteroStreamingMessage

private struct ZoteroStreamingMessage: Decodable {
    let event: String
    let retry: Int64?
    let topic: String?
    let version: Int64?
    let subscriptions: [ZoteroStreamingResponseSubscription]?
}

// MARK: - ZoteroStreamingResponseSubscription

private struct ZoteroStreamingResponseSubscription: Decodable {
    let topics: [String]
}

// MARK: - ZoteroStreamingRetry

private struct ZoteroStreamingRetry: Error {
    let milliseconds: Int64
}
