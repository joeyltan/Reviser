import Foundation

struct Section: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var notes: [String] = []
    var resolvedNotes: [String] = []
    var colors: [TextStyleRange] = []
    var highlights: [TextStyleRange] = []
    var fontTypes: [TextStyleRange] = []
    var fontSizes: [TextStyleRange] = []
    var boldStyles: [TextStyleRange] = []
    var italicStyles: [TextStyleRange] = []
    var underlineStyles: [TextStyleRange] = []
    var strikethroughStyles: [TextStyleRange] = []

    init(id: UUID, text: String, notes: [String] = [], resolvedNotes: [String] = [], colors: [TextStyleRange] = [], highlights: [TextStyleRange] = [], fontTypes: [TextStyleRange] = [], fontSizes: [TextStyleRange] = [], boldStyles: [TextStyleRange] = [], italicStyles: [TextStyleRange] = [], underlineStyles: [TextStyleRange] = [], strikethroughStyles: [TextStyleRange] = []) {
        self.id = id
        self.text = text
        self.notes = notes
        self.resolvedNotes = resolvedNotes
        self.colors = colors
        self.highlights = highlights
        self.fontTypes = fontTypes
        self.fontSizes = fontSizes
        self.boldStyles = boldStyles
        self.italicStyles = italicStyles
        self.underlineStyles = underlineStyles
        self.strikethroughStyles = strikethroughStyles
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case notes
        case resolvedNotes
        case colors
        case highlights
        case fontTypes
        case fontSizes
        case boldStyles
        case italicStyles
        case underlineStyles
        case strikethroughStyles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        resolvedNotes = try container.decodeIfPresent([String].self, forKey: .resolvedNotes) ?? []
        colors = try container.decodeIfPresent([TextStyleRange].self, forKey: .colors) ?? []
        highlights = try container.decodeIfPresent([TextStyleRange].self, forKey: .highlights) ?? []
        fontTypes = try container.decodeIfPresent([TextStyleRange].self, forKey: .fontTypes) ?? []
        fontSizes = try container.decodeIfPresent([TextStyleRange].self, forKey: .fontSizes) ?? []
        boldStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .boldStyles) ?? []
        italicStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .italicStyles) ?? []
        underlineStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .underlineStyles) ?? []
        strikethroughStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .strikethroughStyles) ?? []
    }
}
