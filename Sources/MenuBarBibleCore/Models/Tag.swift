import Foundation

public struct Tag: Identifiable, Hashable, Sendable {
    public let id: Int
    public let slug: String
    public let displayName: String
    public let sortOrder: Int

    public init(id: Int, slug: String, displayName: String, sortOrder: Int) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.sortOrder = sortOrder
    }
}
