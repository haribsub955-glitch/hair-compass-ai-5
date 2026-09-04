import SwiftUI

extension TrendHighlight.Kind {
    var tint: Color {
        switch self {
        case .regrowth: return Clinical.positive
        case .photo, .note: return Clinical.sage
        case .sideEffect, .trigger: return Clinical.warning
        case .stop: return Clinical.tertiary
        case .procedure, .start: return Clinical.accent
        }
    }
}

struct TrendHighlightsCard: View {
    let highlights: [TrendHighlight]
    var onSelect: (TrendHighlight) -> Void
    @State private var filter: TrendHighlight.Kind?
    @State private var expanded = false
    @State private var selectedPhoto: PhotoRecord?

    private var filtered: [TrendHighlight] {
        highlights.filter { filter == nil || $0.kind == filter }
    }

    var body: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Highlights").font(Clinical.headline(23)).foregroundStyle(Clinical.ink)
                    Spacer()
                    Menu {
                        Button("All highlights") { filter = nil; expanded = false }
                        ForEach(TrendHighlight.Kind.allCases) { kind in
                            Button(kind.rawValue) { filter = kind; expanded = false }
                        }
                    } label: {
                        Label(filter?.rawValue ?? "All", systemImage: "line.3.horizontal.decrease")
                            .font(Clinical.body(12, weight: .medium)).foregroundStyle(Clinical.accent)
                    }
                    .accessibilityIdentifier("trendHighlightFilter")
                }
                Text("Photos, baby hairs you notice, plan changes, and completed procedures — dated alongside your trends.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                if filtered.isEmpty {
                    Text(highlights.isEmpty ? "Your next photo or recorded event will appear here. Tag baby hairs when saving or reviewing a photo." : "No matching highlights in this range.")
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                }
                ForEach(Array(filtered.prefix(expanded ? filtered.count : 5))) { item in
                    Button {
                        if let photo = item.photo { selectedPhoto = photo }
                        else { onSelect(item) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.kind.symbol)
                                .font(Clinical.body(16)).foregroundStyle(item.kind.tint)
                                .frame(width: 30, height: 34)
                                .background(item.kind.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                                Text(item.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                                if !item.detail.isEmpty {
                                    Text(item.detail).font(Clinical.caption(11)).foregroundStyle(Clinical.secondary).lineLimit(3)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(Clinical.caption(10)).foregroundStyle(Clinical.tertiary)
                                .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(item.photo == nil ? "Compare observations around this date" : "Open photo and edit its highlight")
                }
                if filtered.count > 5 {
                    Button(expanded ? "Show fewer" : "Show all \(filtered.count) highlights") { expanded.toggle() }
                        .font(Clinical.body(12, weight: .semibold)).foregroundStyle(Clinical.accent)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trendHighlights")
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(record: photo, onDelete: { selectedPhoto = nil })
        }
    }
}
