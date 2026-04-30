import Foundation

struct ProjectEditSnapshot: Equatable {
    var sections: [Section]
    var sectionTags: [UUID: Set<String>]
    var taggedTextBySection: [UUID: [String: Set<String>]]
}
