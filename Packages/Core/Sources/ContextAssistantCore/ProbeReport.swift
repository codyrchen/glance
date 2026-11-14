import Foundation

/// One independent capture measurement. The initializer always records that the
/// result was not used as a fallback.
public struct CaptureProbeReport: Codable, Equatable, Sendable {
    public var api: String
    public var windowID: UInt32?
    public var windowTitle: String?
    public var ownerName: String?
    public var osVersion: String
    public var success: Bool
    public var hasVisibleContent: Bool?
    public var error: String?
    public var tccFailure: Bool
    public var independentProbe: Bool
    public var usedAsFallback: Bool

    public init(
        api: String,
        windowID: UInt32?,
        windowTitle: String?,
        ownerName: String?,
        osVersion: String,
        success: Bool,
        hasVisibleContent: Bool?,
        error: String?,
        tccFailure: Bool
    ) {
        self.api = api
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.ownerName = ownerName
        self.osVersion = osVersion
        self.success = success
        self.hasVisibleContent = hasVisibleContent
        self.error = error
        self.tccFailure = tccFailure
        self.independentProbe = true
        self.usedAsFallback = false
    }
}

public struct CaptureDiagnosticsReport: Codable, Equatable, Sendable {
    public static let policy = "independent-probes-no-fallback"

    public var generatedAt: Date
    public var osVersion: String
    public var policy: String
    public var windowID: UInt32?
    public var windowTitle: String?
    public var ownerName: String?
    public var probes: [CaptureProbeReport]

    public init(
        generatedAt: Date,
        osVersion: String,
        windowID: UInt32?,
        windowTitle: String?,
        ownerName: String?,
        probes: [CaptureProbeReport]
    ) {
        self.generatedAt = generatedAt
        self.osVersion = osVersion
        self.policy = Self.policy
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.ownerName = ownerName
        self.probes = probes
    }

    public func json(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}
