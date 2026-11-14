import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ContextAssistantCore

final class MockLLMURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

final class LLMClientTests: XCTestCase {
    override func tearDown() {
        MockLLMURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testChatCompletionsURL() {
        let root = LLMConfiguration(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-4o-mini",
            apiKey: "secret"
        )
        XCTAssertEqual(root.chatCompletionsURL.absoluteString, "https://api.openai.com/v1/chat/completions")

        let already = LLMConfiguration(
            baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            model: "local",
            apiKey: ""
        )
        XCTAssertEqual(already.chatCompletionsURL.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
    }

    func testStreamsDeltasThroughURLProtocol() async throws {
        let session = makeSession()
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try Self.bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["model"] as? String, "demo-model")
            XCTAssertEqual(json?["stream"] as? Bool, true)
            let payload = """
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: [DONE]

            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(payload.utf8))
        }
        let client = LLMClient(session: session)
        let config = LLMConfiguration(
            baseURL: URL(string: "https://example.test/v1")!,
            model: "demo-model",
            apiKey: "test-key"
        )
        var collected = ""
        for try await chunk in client.stream(configuration: config, messages: [ChatMessage(role: "user", content: "Hi")]) {
            collected += chunk
        }
        XCTAssertEqual(collected, "Hello world")
    }

    func testHTTPErrorSurfacesStatus() async throws {
        let session = makeSession()
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        let client = LLMClient(session: session)
        let config = LLMConfiguration(baseURL: URL(string: "https://example.test/v1")!, model: "m", apiKey: "nope")
        do {
            for try await _ in client.stream(configuration: config, messages: []) {
                XCTFail("did not expect tokens")
            }
            XCTFail("expected an HTTP error")
        } catch let error as LLMClientError {
            guard case .http(let status, let body) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("bad key"))
        }
    }

    func testEmptyAPIKeyOmitsAuthorization() async throws {
        let session = makeSession()
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("data: [DONE]\n\n".utf8))
        }
        let client = LLMClient(session: session)
        let config = LLMConfiguration(baseURL: URL(string: "http://127.0.0.1:11434/v1")!, model: "local", apiKey: "")
        var count = 0
        for try await _ in client.stream(configuration: config, messages: [ChatMessage(role: "user", content: "Hi")]) {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func testStreamCapsCharacters() async throws {
        let session = makeSession()
        MockLLMURLProtocol.requestHandler = { request in
            let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello world\"}}]}\n\ndata: [DONE]\n\n"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }
        let client = LLMClient(session: session, maxStreamCharacters: 5)
        let config = LLMConfiguration(baseURL: URL(string: "https://example.test/v1")!, model: "m", apiKey: "k")
        var collected = ""
        for try await chunk in client.stream(configuration: config, messages: []) {
            collected += chunk
        }
        XCTAssertEqual(collected, "Hello…")
    }

    func testCancellationFinishesQuietly() async throws {
        let session = makeSession()
        MockLLMURLProtocol.requestHandler = { request in
            throw URLError(.cancelled)
        }
        let client = LLMClient(session: session)
        let config = LLMConfiguration(baseURL: URL(string: "https://example.test/v1")!, model: "m", apiKey: "k")
        let task = Task {
            var count = 0
            for try await _ in client.stream(configuration: config, messages: []) {
                count += 1
            }
            return count
        }
        task.cancel()
        let count = try await task.value
        XCTAssertEqual(count, 0)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockLLMURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw LLMClientError.stream("missing body")
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class ProbeReportTests: XCTestCase {
    func testReportCannotClaimAFallback() throws {
        let probe = CaptureProbeReport(
            api: "SCScreenshotManager.captureImage",
            windowID: 42,
            windowTitle: "Lab",
            ownerName: "Capture Lab",
            osVersion: "Version 15.0 (Build 24A335)",
            success: true,
            hasVisibleContent: false,
            error: "near-black frame",
            tccFailure: false
        )
        XCTAssertFalse(probe.usedAsFallback)
        XCTAssertTrue(probe.independentProbe)
        let report = CaptureDiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            osVersion: probe.osVersion,
            windowID: 42,
            windowTitle: "Lab",
            ownerName: "Capture Lab",
            probes: [probe]
        )
        XCTAssertEqual(report.policy, "independent-probes-no-fallback")
        let object = try JSONSerialization.jsonObject(with: report.json()) as? [String: Any]
        XCTAssertEqual(object?["policy"] as? String, CaptureDiagnosticsReport.policy)
        let probes = object?["probes"] as? [[String: Any]]
        XCTAssertEqual(probes?.first?["usedAsFallback"] as? Bool, false)
        XCTAssertEqual(probes?.first?["api"] as? String, "SCScreenshotManager.captureImage")
        XCTAssertEqual(probes?.first?["hasVisibleContent"] as? Bool, false)
        XCTAssertEqual(probes?.first?["tccFailure"] as? Bool, false)
    }
}
