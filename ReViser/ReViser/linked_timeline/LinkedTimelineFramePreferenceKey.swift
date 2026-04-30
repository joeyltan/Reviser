import SwiftUI

struct LinkedTimelineFramePreferenceKey: PreferenceKey {
    static var defaultValue: [LinkedTimelineFrame] = []

    static func reduce(value: inout [LinkedTimelineFrame], nextValue: () -> [LinkedTimelineFrame]) {
        value.append(contentsOf: nextValue())
    }
}
