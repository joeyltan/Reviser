import Foundation

struct TextStyleRange: Codable, Equatable {
    var location: Int
    var length: Int
    var style: String

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}
