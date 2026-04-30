import SwiftUI

struct LinkedTimelineTextViewFramePreferenceKey: PreferenceKey {
    static var defaultValue: [LinkedTimelineTextViewFrame] = []

    static func reduce(value: inout [LinkedTimelineTextViewFrame], nextValue: () -> [LinkedTimelineTextViewFrame]) {
        value.append(contentsOf: nextValue())
    }
}
