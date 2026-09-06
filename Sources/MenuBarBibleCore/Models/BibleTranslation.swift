import Foundation

/// One of the three bundled translations.
///
/// Named `BibleTranslation` rather than `Translation`: the latter collides with the
/// system `Translation` framework, which SwiftUI pulls in, and the ambiguity is a type
/// lookup error at every use site in the app target.
public struct BibleTranslation: Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let year: Int?
    public let license: String

    public init(code: String, name: String, year: Int?, license: String) {
        self.code = code
        self.name = name
        self.year = year
        self.license = license
    }

    /// The default translation. WEB is the only one of the three in modern English,
    /// which matters for a verse someone glances at for a few seconds.
    public static let defaultCode = "WEB"
}
