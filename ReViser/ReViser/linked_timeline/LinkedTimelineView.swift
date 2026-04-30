import SwiftUI

extension ProjectDetailView {
    @ViewBuilder
    func linkedTimelineView() -> some View {
        let displayedSections = displayedSectionsForCurrentFilters()
        let textPointsByTag = linkedTimelineTextPointsByTag(displayedSections: displayedSections)
        let timelineAvailableTags = filterableTags()

        if displayedSections.isEmpty {
            Text("(Empty project)")
                .font(.system(size: 24))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
        } else {
            GeometryReader { proxy in
                let panelWidth: CGFloat = 260
                let contentSpacing: CGFloat = 20
                let canvasWidth = max(proxy.size.width - panelWidth - contentSpacing, 620)
                let columns = timelineColumnCount(for: canvasWidth)
                let gridItems = Array(
                    repeating: GridItem(.flexible(minimum: 360, maximum: 520), spacing: 28),
                    count: columns
                )

                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: contentSpacing) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Linked timeline")
                                        .font(.headline)
                                    Text("Shows section links plus tag-based text links. Use the panel to filter by tags.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(displayedSections.count) sections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.secondary.opacity(0.10))
                                    )
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                            ZStack(alignment: .topLeading) {
                                Canvas { context, _ in
                                    func addSeparatedCurve(
                                        _ path: inout Path,
                                        from startPoint: CGPoint,
                                        to endPoint: CGPoint,
                                        offset: CGFloat
                                    ) {
                                        let sharedControlX = max(startPoint.x, endPoint.x) + offset

                                        path.move(to: startPoint)
                                        path.addCurve(
                                            to: endPoint,
                                            control1: CGPoint(x: sharedControlX, y: startPoint.y),
                                            control2: CGPoint(x: sharedControlX, y: endPoint.y)
                                        )
                                    }

                                    if displayedSections.count > 1 {
                                        for (pairIndex, pair) in zip(displayedSections, displayedSections.dropFirst()).enumerated() {
                                            guard let startFrame = linkedTimelineFrames[pair.0.id],
                                                  let endFrame = linkedTimelineFrames[pair.1.id] else { continue }

                                            let startPoint = CGPoint(x: startFrame.minX, y: startFrame.minY)
                                            let endPoint = CGPoint(x: endFrame.minX, y: endFrame.minY)
                                            let sectionOffset = 26 + CGFloat(pairIndex % 4) * 10

                                            let startSectionTags = sectionLevelTags(for: pair.0.id)
                                            let endSectionTags = sectionLevelTags(for: pair.1.id)
                                            let sharedSectionTags = startSectionTags.intersection(endSectionTags)

                                            let preferredTag =
                                                activeFilterTags.sorted().first(where: { sharedSectionTags.contains($0) }) ??
                                                sharedSectionTags.sorted().first ??
                                                activeFilterTags.sorted().first(where: { startSectionTags.contains($0) || endSectionTags.contains($0) }) ??
                                                startSectionTags.union(endSectionTags).sorted().first

                                            let sectionLinkColor = preferredTag.map { colorForTag($0).opacity(0.65) } ?? Color.blue.opacity(0.35)

                                            var sectionPath = Path()
                                            addSeparatedCurve(&sectionPath, from: startPoint, to: endPoint, offset: sectionOffset)

                                            context.stroke(
                                                sectionPath,
                                                with: .color(sectionLinkColor),
                                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 6])
                                            )
                                        }
                                    }

                                    let orderedTags = textPointsByTag.keys.sorted()

                                    for (tagIndex, tag) in orderedTags.enumerated() {
                                        guard let points = textPointsByTag[tag], points.count > 1 else { continue }

                                        let textOffset = 18 + CGFloat(tagIndex % 6) * 8
                                        var textPath = Path()

                                        for pair in zip(points, points.dropFirst()) {
                                            let startPoint = pair.0
                                            let endPoint = pair.1

                                            addSeparatedCurve(&textPath, from: startPoint, to: endPoint, offset: textOffset)
                                        }

                                        context.stroke(
                                            textPath,
                                            with: .color(colorForTag(tag).opacity(0.80)),
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                        )
                                    }
                                }
                                .allowsHitTesting(false)

                                LazyVGrid(columns: gridItems, alignment: .leading, spacing: 28) {
                                    ForEach(displayedSections, id: \.id) { section in
                                        timelineCardView(section: section)
                                            .background(
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: LinkedTimelineFramePreferenceKey.self,
                                                        value: [LinkedTimelineFrame(id: section.id, frame: proxy.frame(in: .named("linkedTimelineCanvas")))]
                                                    )
                                                }
                                            )
                                    }
                                }
                            }
                            .coordinateSpace(name: "linkedTimelineCanvas")
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(.secondarySystemBackground), Color(.secondarySystemBackground).opacity(0.96)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .frame(width: canvasWidth, alignment: .leading)
                        .padding(.leading, 24)
                        .padding(.bottom, 24)

                        timelineTagFilterPanel(availableTags: timelineAvailableTags)
                            .frame(width: panelWidth)
                            .padding(.trailing, 24)
                            .padding(.top, 12)
                    }
                }
                .onPreferenceChange(LinkedTimelineFramePreferenceKey.self) { frames in
                    linkedTimelineFrames = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.frame) })
                }
                .onPreferenceChange(LinkedTimelineTextViewFramePreferenceKey.self) { frames in
                    linkedTimelineTextViewFrames = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.frame) })
                }
            }
        }
    }

    private func linkedTimelineTextPointsByTag(displayedSections: [Section]) -> [String: [CGPoint]] {
        var pointsByTag: [String: [(Int, CGPoint)]] = [:]

        for (sectionIndex, section) in displayedSections.enumerated() {
            guard let textFrame = linkedTimelineTextViewFrames[section.id],
                  let snippetPoints = linkedTimelineSnippetPoints[section.id],
                  let taggedSnippets = taggedTextBySection[section.id] else { continue }

            for (snippet, tags) in taggedSnippets {
                guard let points = snippetPoints[snippet], !points.isEmpty else { continue }

                for point in points {
                    let canvasPoint = CGPoint(x: textFrame.minX + point.x, y: textFrame.minY + point.y)
                    for tag in tags {
                        if !activeFilterTags.isEmpty && !activeFilterTags.contains(tag) {
                            continue
                        }
                        pointsByTag[tag, default: []].append((sectionIndex, canvasPoint))
                    }
                }
            }
        }

        return pointsByTag.mapValues { entries in
            entries
                .sorted { lhs, rhs in
                    if lhs.0 == rhs.0 {
                        return lhs.1.y < rhs.1.y
                    }
                    return lhs.0 < rhs.0
                }
                .map { $0.1 }
        }
    }
}
