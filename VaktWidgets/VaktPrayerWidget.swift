import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct VaktWidgetBundle: WidgetBundle {
    var body: some Widget {
        VaktPrayerWidget()
        VaktPrayerLiveActivity()
    }
}

struct VaktPrayerWidget: Widget {
    let kind = "VaktPrayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VaktPrayerTimelineProvider()) { entry in
            VaktPrayerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    VaktWidgetContainerBackground(atmosphere: entry.resolvedAtmosphere)
                }
        }
        .configurationDisplayName("Vakt")
        .description("widget.gallery.description")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

struct MarkPrayerPrayedIntent: AppIntent {
    static var title: LocalizedStringResource = "onboarding.mark_prayer.action.prayed"
    static var openAppWhenRun = false

    @Parameter(title: "Prayer")
    var prayerRawValue: String

    @Parameter(title: "Prayer date")
    var prayerTimestamp: Double

    init() {
        prayerRawValue = ""
        prayerTimestamp = 0
    }

    init(prayer: PrayerSurfacePrayerID, prayerDate: Date) {
        prayerRawValue = prayer.rawValue
        prayerTimestamp = prayerDate.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let prayer = PrayerSurfacePrayerID(rawValue: prayerRawValue),
              prayerTimestamp > 0 else {
            return .result()
        }

        let prayerDate = Date(timeIntervalSince1970: prayerTimestamp)
        let store = PrayerSurfaceStore.shared
        guard store.hasActiveAccess() else { return .result() }
        let action = PrayerSurfaceAction(
            kind: .markPrayed,
            prayer: prayer,
            prayerDate: prayerDate
        )
        _ = store.enqueue(action)
        _ = store.markPrayerPrayed(prayer: prayer, prayerDate: prayerDate)
        WidgetCenter.shared.reloadTimelines(ofKind: "VaktPrayerWidget")
        return .result()
    }
}

struct MarkPrayerNotYetIntent: AppIntent {
    static var title: LocalizedStringResource = "notification.action.missed"
    static var openAppWhenRun = false

    @Parameter(title: "Prayer")
    var prayerRawValue: String

    @Parameter(title: "Prayer date")
    var prayerTimestamp: Double

    init() {
        prayerRawValue = ""
        prayerTimestamp = 0
    }

    init(prayer: PrayerSurfacePrayerID, prayerDate: Date) {
        prayerRawValue = prayer.rawValue
        prayerTimestamp = prayerDate.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let prayer = PrayerSurfacePrayerID(rawValue: prayerRawValue),
              prayerTimestamp > 0 else {
            return .result()
        }

        let prayerDate = Date(timeIntervalSince1970: prayerTimestamp)
        let store = PrayerSurfaceStore.shared
        guard store.hasActiveAccess() else { return .result() }
        let action = PrayerSurfaceAction(
            kind: .markNotYet,
            prayer: prayer,
            prayerDate: prayerDate
        )
        _ = store.enqueue(action)
        _ = store.markPrayerNotYet(prayer: prayer, prayerDate: prayerDate)
        WidgetCenter.shared.reloadTimelines(ofKind: "VaktPrayerWidget")
        return .result()
    }
}

struct VaktPrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerLiveActivityAttributes.self) { context in
            VaktPrayerLiveActivityView(context: context)
                .activityBackgroundTint(Color(hex: 0x0B1018))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.deepLinkURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VaktWidgetMark()
                        .frame(width: 22, height: 25)
                        .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VaktLiveActivityTimer(
                        startedAt: context.attributes.startedAt,
                        phase: context.state.phase,
                        compact: true
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.attributes.prayer.localizedName)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)

                            Text("quiet.phone_aside")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    VaktWidgetMark()
                        .frame(width: 10, height: 12)

                    Text(context.attributes.prayer.localizedName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
            } compactTrailing: {
                VaktLiveActivityTimer(
                    startedAt: context.attributes.startedAt,
                    phase: context.state.phase,
                    compact: true
                )
                .frame(minWidth: 72, maxWidth: .infinity, alignment: .trailing)
            } minimal: {
                VaktWidgetMark()
                    .frame(width: 13, height: 15)
            }
            .keylineTint(VaktWidgetPalette.gold)
            .contentMargins(.leading, 8, for: .compactLeading)
            .contentMargins(.trailing, 8, for: .compactTrailing)
            .widgetURL(context.attributes.deepLinkURL)
        }
    }
}

private struct VaktPrayerLiveActivityView: View {
    let context: ActivityViewContext<PrayerLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(VaktWidgetPalette.gold.opacity(0.09))
                    .frame(width: 50, height: 50)

                VaktWidgetMark()
                    .frame(width: 22, height: 26)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("quiet.eyebrow")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(VaktWidgetPalette.gold.opacity(0.72))

                    Spacer(minLength: 8)

                    VaktLiveActivityTimer(
                        startedAt: context.attributes.startedAt,
                        phase: context.state.phase,
                        compact: false
                    )
                }

                Text(context.attributes.prayer.localizedName)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Group {
                    if context.state.phase == .completed {
                        Text("quiet.finished")
                    } else {
                        Text("quiet.phone_aside")
                    }
                }
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct VaktLiveActivityTimer: View {
    let startedAt: Date
    let phase: PrayerLiveActivityAttributes.ContentState.Phase
    let compact: Bool

    var body: some View {
        Group {
            if phase == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .accessibilityLabel(Text("quiet.finished"))
                    .foregroundStyle(VaktWidgetPalette.gold)
            } else if compact {
                elapsedTimer
                    .foregroundStyle(.white.opacity(0.86))
            } else {
                elapsedTimer
                    .foregroundStyle(VaktWidgetPalette.gold)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(VaktWidgetPalette.gold.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(VaktWidgetPalette.gold.opacity(0.16), lineWidth: 0.5)
                    )
            }
        }
    }

    private var elapsedTimer: some View {
        Text(
            timerInterval: startedAt...startedAt.addingTimeInterval(60 * 60),
            countsDown: false
        )
        .font(.system(
            size: compact ? 12 : 13,
            weight: .medium,
            design: .rounded
        ))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

struct VaktPrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerSurfaceSnapshot?
}

struct VaktPrayerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VaktPrayerEntry {
        VaktPrayerEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (VaktPrayerEntry) -> Void) {
        completion(
            VaktPrayerEntry(
                date: Date(),
                snapshot: PrayerSurfaceStore.shared.loadSnapshot() ?? .placeholder
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VaktPrayerEntry>) -> Void) {
        let now = Date()
        let snapshot = PrayerSurfaceStore.shared.loadSnapshot()
        let refreshDates = timelineDates(snapshot: snapshot, now: now)
        let entries = refreshDates.map { VaktPrayerEntry(date: $0, snapshot: snapshot) }
        let reloadDate = now.addingTimeInterval(125 * 60)
        completion(Timeline(entries: entries, policy: .after(reloadDate)))
    }

    private func timelineDates(snapshot: PrayerSurfaceSnapshot?, now: Date) -> [Date] {
        guard let snapshot else { return [now] }
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        let minuteRefreshHorizon = min(horizon, now.addingTimeInterval(2 * 60 * 60))
        let minuteRefreshDates = stride(from: 5, through: 120, by: 5).compactMap { minuteOffset -> Date? in
            let date = now.addingTimeInterval(TimeInterval(minuteOffset * 60))
            return date <= minuteRefreshHorizon ? date : nil
        }
        let boundaries = snapshot.schedule.flatMap { prayer -> [Date] in
            [prayer.startsAt, prayer.endsAt].compactMap { date in
                guard let date, date > now, date <= horizon else { return nil }
                return date.addingTimeInterval(1)
            }
        }
        let atmosphereBoundaries = atmosphereTimelineDates(snapshot: snapshot, now: now, horizon: horizon)
        return Array(Set([now] + minuteRefreshDates + boundaries + atmosphereBoundaries)).sorted()
    }

    private func atmosphereTimelineDates(
        snapshot: PrayerSurfaceSnapshot,
        now: Date,
        horizon: Date
    ) -> [Date] {
        let timeZone = snapshot.schedule.first
            .flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .autoupdatingCurrent
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)

        return (0...1).flatMap { dayOffset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                return []
            }
            return [5, 7, 11, 15, 18, 21].compactMap { hour in
                guard let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 1, of: day),
                      boundary > now,
                      boundary <= horizon else {
                    return nil
                }
                return boundary
            }
        }
    }
}

private extension VaktPrayerEntry {
    var usableSnapshot: PrayerSurfaceSnapshot? {
        guard let snapshot,
              PrayerSurfaceStore.shared.hasActiveAccess(at: date),
              date.timeIntervalSince(snapshot.generatedAt) < 26 * 60 * 60 else {
            return nil
        }
        return snapshot
    }

    var resolvedAtmosphere: PrayerSurfaceAtmosphere {
        let timeZone = usableSnapshot?.schedule.first
            .flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .autoupdatingCurrent
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        switch calendar.component(.hour, from: date) {
        case 0..<5, 21..<24: return .night
        case 5..<7: return .dawn
        case 7..<11: return .morning
        case 11..<15: return .midday
        case 15..<18: return .afternoon
        case 18..<21: return .sunset
        default: return .night
        }
    }
}

private struct VaktPrayerWidgetView: View {
    let entry: VaktPrayerEntry

    @Environment(\.widgetFamily) private var family

    private var moment: VaktWidgetMoment? {
        VaktWidgetMoment.resolve(snapshot: entry.usableSnapshot, at: entry.date)
    }

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemMedium:
            VaktMediumPrayerWidgetView(entry: entry, moment: moment)
        case .accessoryInline:
            VaktInlinePrayerWidgetView(entry: entry, moment: moment)
        case .accessoryCircular:
            VaktCircularPrayerWidgetView(entry: entry, moment: moment)
        case .accessoryRectangular:
            VaktRectangularPrayerWidgetView(entry: entry, moment: moment)
        default:
            VaktSmallPrayerWidgetView(entry: entry, moment: moment)
        }
    }
}

private struct VaktSmallPrayerWidgetView: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VaktWidgetMark()
                    .frame(width: 24, height: 27)

                Spacer()

                if let moment, moment.isCurrent {
                    if moment.prayer.status == .prayed {
                        VaktWidgetStatusMark(status: moment.prayer.status)
                    } else {
                        VaktWidgetResponseActions(moment: moment, circular: true)
                    }
                }
            }

            Spacer(minLength: 12)

            if let moment {
                Text(moment.prayer.prayer.localizedName)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(moment.prayer.startsAt, format: .dateTime.hour().minute())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VaktWidgetPalette.gold.opacity(0.92))
                    .monospacedDigit()
                    .padding(.top, 3)

                Spacer(minLength: 8)

                VaktWidgetCountdownLine(entry: entry, moment: moment)
            } else {
                VaktWidgetEmptyState()
            }
        }
        .padding(17)
        .widgetURL(moment?.deepLinkURL)
    }
}

private struct VaktMediumPrayerWidgetView: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment?

    private var schedule: [PrayerSurfacePrayer] {
        Array((entry.usableSnapshot?.schedule ?? []).sorted { $0.startsAt < $1.startsAt }.prefix(5))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                VaktWidgetMark()
                    .frame(width: 21, height: 24)

                Spacer(minLength: 8)

                if let moment {
                    Text(moment.isCurrent
                         ? LocalizedStringKey("home.current_prayer")
                         : LocalizedStringKey("home.next_prayer"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(VaktWidgetPalette.gold.opacity(0.78))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(moment.prayer.prayer.localizedName)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.top, 2)

                    Text(moment.prayer.startsAt, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .monospacedDigit()
                        .padding(.top, 2)

                    Spacer(minLength: 5)
                    if moment.isCurrent {
                        VaktMediumWidgetActions(moment: moment)
                    } else {
                        VaktWidgetCountdownLine(entry: entry, moment: moment)
                    }
                } else {
                    VaktWidgetEmptyState()
                }
            }
            .frame(width: 104, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 0.5)

            VStack(spacing: 1) {
                ForEach(schedule) { prayer in
                    VaktMediumPrayerRow(
                        prayer: prayer,
                        isFocused: prayer.id == moment?.prayer.id
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .widgetURL(moment?.deepLinkURL)
    }
}

private struct VaktMediumWidgetActions: View {
    let moment: VaktWidgetMoment

    var body: some View {
        HStack(spacing: 7) {
            if moment.prayer.status != .prayed {
                VaktWidgetResponseActions(moment: moment, circular: false)
            }

            if let url = moment.startPrayerURL {
                Link(destination: url) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 27, height: 25)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .accessibilityLabel(Text("prayer.action.begin"))
            }

            Spacer(minLength: 0)
        }
    }
}

private struct VaktWidgetResponseActions: View {
    let moment: VaktWidgetMoment
    let circular: Bool

    var body: some View {
        HStack(spacing: 5) {
            Button(intent: MarkPrayerNotYetIntent(
                prayer: moment.prayer.prayer,
                prayerDate: moment.prayer.startsAt
            )) {
                responseIcon(
                    "clock",
                    isSelected: moment.prayer.status == .notYet
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("notification.action.missed"))

            Button(intent: MarkPrayerPrayedIntent(
                prayer: moment.prayer.prayer,
                prayerDate: moment.prayer.startsAt
            )) {
                responseIcon("checkmark", isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("onboarding.mark_prayer.action.prayed"))
        }
    }

    private func responseIcon(_ systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isSelected ? Color(hex: 0x0B1018) : VaktWidgetPalette.gold)
            .frame(width: circular ? 24 : 27, height: circular ? 24 : 25)
            .background(isSelected ? VaktWidgetPalette.gold : VaktWidgetPalette.gold.opacity(0.1))
            .clipShape(circular
                ? AnyShape(Circle())
                : AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous)))
    }
}

private struct VaktMediumPrayerRow: View {
    let prayer: PrayerSurfacePrayer
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(isFocused ? VaktWidgetPalette.gold : .white.opacity(0.16))
                .frame(width: isFocused ? 14 : 5, height: 2)

            Text(prayer.prayer.localizedName)
                .font(.system(size: 11, weight: isFocused ? .semibold : .regular, design: .rounded))
                .foregroundStyle(.white.opacity(isFocused ? 0.94 : 0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 4)

            Text(prayer.startsAt, format: .dateTime.hour().minute())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isFocused ? VaktWidgetPalette.gold : .white.opacity(0.46))
                .monospacedDigit()

            VaktWidgetStatusMark(status: prayer.status, compact: true)
                .frame(width: 9)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isFocused ? VaktWidgetPalette.gold.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct VaktInlinePrayerWidgetView: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment?

    var body: some View {
        if let moment {
            ViewThatFits {
                inlineText(moment, includesTimer: true)
                inlineText(moment, includesTimer: false)
            }
            .widgetURL(moment.deepLinkURL)
        } else {
            Text("Vakt · ") + Text("widget.empty.open_app")
        }
    }

    private func inlineText(_ moment: VaktWidgetMoment, includesTimer: Bool) -> Text {
        let name = Text(verbatim: moment.prayer.prayer.localizedName)
        guard includesTimer, let boundary = moment.boundary(after: entry.date) else {
            return name + Text(" · ") + Text(moment.prayer.startsAt, style: .time)
        }
        return name + Text(" · ") + Text(verbatim: VaktWidgetRemainingTime.string(
            from: entry.date,
            until: boundary
        ))
    }
}

private struct VaktCircularPrayerWidgetView: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment?

    var body: some View {
        if let moment {
            Gauge(value: progress(for: moment)) {
                Text(verbatim: moment.prayer.prayer.localizedName)
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Text(verbatim: moment.prayer.prayer.localizedName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text(moment.prayer.startsAt, format: .dateTime.hour().minute())
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .widgetURL(moment.deepLinkURL)
        } else {
            VaktWidgetMark()
                .padding(13)
        }
    }

    private func progress(for moment: VaktWidgetMoment) -> Double {
        let end = moment.boundary(after: entry.date) ?? entry.date.addingTimeInterval(30 * 60)
        let start = moment.isCurrent
            ? moment.prayer.startsAt
            : min(entry.usableSnapshot?.generatedAt ?? entry.date, moment.prayer.startsAt.addingTimeInterval(-30 * 60))
        let duration = max(1, end.timeIntervalSince(start))
        return min(1, max(0, entry.date.timeIntervalSince(start) / duration))
    }
}

private struct VaktRectangularPrayerWidgetView: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment?

    var body: some View {
        if let moment {
            HStack(spacing: 9) {
                VaktWidgetMark()
                    .frame(width: 16, height: 19)
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 1) {
                    Text(moment.isCurrent
                         ? LocalizedStringKey("home.current_prayer")
                         : LocalizedStringKey("home.next_prayer"))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: moment.prayer.prayer.localizedName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Text(moment.prayer.startsAt, format: .dateTime.hour().minute())
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let boundary = moment.boundary(after: entry.date) {
                        Text(verbatim: VaktWidgetRemainingTime.string(
                            from: entry.date,
                            until: boundary
                        ))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(moment.deepLinkURL)
        } else {
            HStack(spacing: 8) {
                VaktWidgetMark()
                    .frame(width: 16, height: 19)
                Text("widget.empty.open_app")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
    }
}

private struct VaktWidgetEmptyState: View {
    var body: some View {
        Text("Vakt")
            .font(.system(size: 26, weight: .light, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))

        Spacer()

        HStack(alignment: .bottom, spacing: 8) {
            Capsule()
                .fill(VaktWidgetPalette.gold.opacity(0.48))
                .frame(width: 17, height: 2)

            Text("widget.empty.open_app")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct VaktWidgetStatusMark: View {
    let status: PrayerSurfaceStatus
    var compact = false

    @ViewBuilder
    var body: some View {
        switch status {
        case .prayed:
            Image(systemName: "checkmark")
                .font(.system(size: compact ? 7 : 11, weight: .semibold))
                .foregroundStyle(VaktWidgetPalette.gold)
                .accessibilityLabel(Text("home.status.prayed"))
        case .quiet:
            Image(systemName: "moon.fill")
                .font(.system(size: compact ? 6 : 10, weight: .medium))
                .foregroundStyle(VaktWidgetPalette.gold)
                .accessibilityLabel(Text("onboarding.mark_prayer.quiet.active"))
        case .notYet:
            Image(systemName: "clock")
                .font(.system(size: compact ? 6 : 10, weight: .medium))
                .foregroundStyle(VaktWidgetPalette.gold)
                .accessibilityLabel(Text("notification.action.missed"))
        case .unmarked, .later, .missed:
            Circle()
                .fill(VaktWidgetPalette.gold)
                .frame(width: compact ? 3 : 6, height: compact ? 3 : 6)
                .shadow(color: VaktWidgetPalette.gold.opacity(0.6), radius: compact ? 2 : 5)
                .accessibilityLabel(Text("home.status.unmarked"))
        }
    }
}

private struct VaktWidgetCountdownLine: View {
    let entry: VaktPrayerEntry
    let moment: VaktWidgetMoment

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(VaktWidgetPalette.gold.opacity(moment.isCurrent ? 0.92 : 0.48))
                .frame(width: moment.isCurrent ? 28 : 17, height: 2)

            if let boundary = moment.boundary(after: entry.date) {
                Text(verbatim: VaktWidgetRemainingTime.string(
                    from: entry.date,
                    until: boundary
                ))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

private enum VaktWidgetRemainingTime {
    static func string(from start: Date, until end: Date) -> String {
        let remaining = max(60, end.timeIntervalSince(start))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 60 * 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: remaining) ?? ""
    }
}

private struct VaktWidgetMoment {
    let prayer: PrayerSurfacePrayer
    let isCurrent: Bool

    var deepLinkURL: URL? {
        VaktDeepLink.openPrayer(
            prayer: prayer.prayer,
            prayerDate: prayer.startsAt
        ).url
    }

    var startPrayerURL: URL? {
        guard isCurrent else { return nil }
        return VaktDeepLink.startPrayer(
            prayer: prayer.prayer,
            prayerDate: prayer.startsAt
        ).url
    }

    func boundary(after date: Date) -> Date? {
        if isCurrent, let endsAt = prayer.endsAt, endsAt > date {
            return endsAt
        }
        if !isCurrent, prayer.startsAt > date {
            return prayer.startsAt
        }
        return nil
    }

    static func resolve(snapshot: PrayerSurfaceSnapshot?, at date: Date) -> VaktWidgetMoment? {
        guard let snapshot else { return nil }
        let sorted = snapshot.schedule.sorted { $0.startsAt < $1.startsAt }

        if let current = sorted.last(where: { prayer in
            prayer.startsAt <= date && (prayer.endsAt.map { date < $0 } ?? false)
        }) {
            return VaktWidgetMoment(prayer: current, isCurrent: true)
        }

        guard let next = sorted.first(where: { $0.startsAt > date }) else { return nil }
        return VaktWidgetMoment(prayer: next, isCurrent: false)
    }
}

private struct VaktWidgetContainerBackground: View {
    let atmosphere: PrayerSurfaceAtmosphere

    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall, .systemMedium:
            VaktWidgetAtmosphere(atmosphere: atmosphere)
        default:
            Color.clear
        }
    }
}

private struct VaktWidgetAtmosphere: View {
    let atmosphere: PrayerSurfaceAtmosphere

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [VaktWidgetPalette.gold.opacity(0.16), .clear],
                center: glowCenter,
                startRadius: 4,
                endRadius: 150
            )
        }
    }

    private var colors: [Color] {
        switch atmosphere {
        case .night: return [Color(hex: 0x111827), Color(hex: 0x090B11)]
        case .dawn: return [Color(hex: 0x473B4A), Color(hex: 0x171724)]
        case .morning: return [Color(hex: 0x384A50), Color(hex: 0x111D24)]
        case .midday: return [Color(hex: 0x405157), Color(hex: 0x18252A)]
        case .afternoon: return [Color(hex: 0x49483D), Color(hex: 0x1D2020)]
        case .sunset: return [Color(hex: 0x5A413C), Color(hex: 0x1D1820)]
        }
    }

    private var glowCenter: UnitPoint {
        switch atmosphere {
        case .dawn, .morning: return UnitPoint(x: 0.18, y: 0.16)
        case .midday, .afternoon: return UnitPoint(x: 0.82, y: 0.12)
        case .sunset: return UnitPoint(x: 0.82, y: 0.82)
        case .night: return UnitPoint(x: 0.18, y: 0.2)
        }
    }
}

private struct VaktWidgetMark: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = max(1.7, size.width * 0.09)
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.92))
            path.addLine(to: CGPoint(x: size.width * 0.2, y: size.height * 0.47))
            path.addQuadCurve(
                to: CGPoint(x: size.width * 0.5, y: size.height * 0.1),
                control: CGPoint(x: size.width * 0.27, y: size.height * 0.2)
            )
            path.addQuadCurve(
                to: CGPoint(x: size.width * 0.8, y: size.height * 0.47),
                control: CGPoint(x: size.width * 0.73, y: size.height * 0.2)
            )
            path.addLine(to: CGPoint(x: size.width * 0.8, y: size.height * 0.92))
            context.stroke(
                path,
                with: .color(VaktWidgetPalette.gold),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private enum VaktWidgetPalette {
    static let gold = Color(red: 0.79, green: 0.66, blue: 0.42)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension PrayerSurfacePrayerID {
    var localizedName: String {
        NSLocalizedString("prayer.\(rawValue)", comment: "Prayer name")
    }
}

private extension PrayerLiveActivityAttributes {
    var deepLinkURL: URL? {
        VaktDeepLink.startPrayer(
            prayer: prayer,
            prayerDate: prayerDate
        ).url
    }
}

private extension PrayerSurfaceSnapshot {
    static var placeholder: PrayerSurfaceSnapshot {
        let now = Date()
        let prayer = PrayerSurfacePrayer(
            prayer: .asr,
            startsAt: now.addingTimeInterval(28 * 60),
            endsAt: now.addingTimeInterval(2 * 60 * 60),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            status: .unmarked
        )
        return PrayerSurfaceSnapshot(
            generatedAt: now,
            phase: .approaching,
            currentPrayer: nil,
            nextPrayer: prayer,
            schedule: [prayer],
            atmosphere: .afternoon
        )
    }
}
