import SwiftUI

struct MakeupPrayerCenterView: View {
    @ObservedObject var store: SocialPrayerStore

    @State private var visibleMonth = Date()
    @State private var selectedDay: LocalPrayerDay?

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = VaktLocalization.appLocale
        return calendar
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    overview
                    monthHeader
                        .padding(.top, 20)
                    calendarGrid
                        .padding(.top, 10)
                    dayDetail
                        .padding(.top, 18)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, 8)
                .padding(.bottom, max(12, geometry.safeAreaInsets.bottom + 4))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .navigationTitle(L10n.string("makeup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.vaktBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { loadMonth() }
        .onChange(of: visibleMonth) { _, _ in loadMonth() }
        .onChange(of: store.makeupDaySummaries) { _, summaries in
            if let selectedDay, isDayVisible(selectedDay) {
                return
            }
            self.selectedDay = summaries.last?.day ?? currentDayIfVisible
        }
    }

    private var overview: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.vaktGlow.opacity(store.openMakeupPrayerCount == 0 ? 0.06 : 0.12))
                Image(systemName: store.openMakeupPrayerCount == 0 ? "checkmark" : "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(store.openMakeupPrayerCount == 0 ? Color.vaktMuted : Color.vaktGlow)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.openMakeupPrayerCount == 0
                     ? L10n.string("makeup.overview.complete.title")
                     : L10n.string("makeup.overview.pending.title"))
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(store.openMakeupPrayerCount == 0
                     ? L10n.string("makeup.overview.complete.body")
                     : L10n.string("makeup.overview.pending.body"))
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            Text(MakeupNumberFormatter.string(store.openMakeupPrayerCount))
                .font(VaktFont.title(28))
                .monospacedDigit()
                .foregroundStyle(Color.vaktPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .background(Color.vaktSurface.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.5), lineWidth: 0.5)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(visibleMonth.formatted(
                .dateTime.month(.wide).year().locale(VaktLocalization.appLocale)
            ))
                .font(VaktFont.title(18))
                .foregroundStyle(Color.vaktPrimary)

            Spacer()

            monthButton(systemName: "chevron.left", offset: -1)
            monthButton(systemName: "chevron.right", offset: 1)
        }
        .frame(height: 38)
    }

    private func monthButton(systemName: String, offset: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            moveMonth(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vaktSecondary)
                .frame(width: 38, height: 38)
                .background(Color.vaktSurface.opacity(0.4))
                .clipShape(Circle())
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(offset < 0
                            ? L10n.string("makeup.month.previous")
                            : L10n.string("makeup.month.next"))
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(height: 22)
            }

            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    calendarDay(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color.vaktSurface.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.5), lineWidth: 0.5)
        }
        .overlay {
            if store.isLoadingMakeupCalendar {
                ProgressView().tint(Color.vaktSecondary)
            }
        }
    }

    private func calendarDay(_ day: LocalPrayerDay) -> some View {
        let count = summary(for: day)?.count ?? 0
        let selected = selectedDay == day

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedDay = day
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(dayBackground(selected: selected, count: count))

                Text(MakeupNumberFormatter.string(day.day))
                    .font(VaktFont.body(13))
                    .foregroundStyle(dayForeground(selected: selected, count: count))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if count > 0 {
                    Text(MakeupNumberFormatter.string(count))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color.vaktPrimary : Color.vaktBg)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(selected ? Color.vaktBg : Color.vaktPrimary)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selected ? Color.vaktPrimary.opacity(0.18) : Color.vaktBg.opacity(0.12),
                                    lineWidth: 0.5
                                )
                        }
                        .offset(x: 3, y: -3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .overlay {
                if count > 0 && !selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.vaktGlow.opacity(0.28), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(
            L10n.formatString(
                "makeup.calendar.day.accessibility",
                MakeupNumberFormatter.string(day.day),
                MakeupNumberFormatter.string(count)
            )
        )
    }

    @ViewBuilder
    private var dayDetail: some View {
        if let selectedDay {
            let prayers = store.makeupPrayers(on: selectedDay)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dayTitle(selectedDay))
                            .font(VaktFont.body(15))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(prayers.isEmpty
                             ? L10n.string("makeup.day.empty.subtitle")
                             : L10n.string("makeup.day.pending.subtitle"))
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    if !prayers.isEmpty {
                        Text(dayCountText(prayers.count))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.vaktSecondary)
                    }
                }

                if prayers.isEmpty {
                    emptyDay
                } else {
                    let compact = prayers.count >= 4
                    VStack(spacing: compact ? 4 : 7) {
                        ForEach(prayers) { makeup in
                            prayerRow(makeup, compact: compact)
                        }
                    }
                }
            }
        }
    }

    private var emptyDay: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.vaktMuted)
            Text(L10n.string("makeup.day.empty.message"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.vaktSurface.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private func prayerRow(_ makeup: MakeupPrayer, compact: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: prayerIcon(makeup.prayer))
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.vaktGlow)
                .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                .background(Color.vaktGlow.opacity(0.08))
                .clipShape(Circle())

            Text(prayerName(makeup.prayer))
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary)

            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeOut(duration: 0.25)) {
                    store.completeMakeupPrayer(makeup)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.string("makeup.action.complete"))
                        .font(VaktFont.body(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(Color.vaktBg)
                .frame(width: 94, height: compact ? 36 : 38)
                .background(Color.vaktPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 5, y: 2)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(
                L10n.formatString(
                    "makeup.action.complete.accessibility",
                    prayerName(makeup.prayer)
                )
            )
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 48 : 56)
        .background(Color.vaktSurface.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private var monthCells: [LocalPrayerDay?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let month = MakeupPrayerMonth(date: visibleMonth, calendar: calendar)
        return Array(repeating: nil, count: leading) + dayRange.map {
            LocalPrayerDay(year: month.year, month: month.month, day: $0)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var currentDayIfVisible: LocalPrayerDay? {
        let today = LocalPrayerDay(date: Date(), calendar: calendar)
        let month = MakeupPrayerMonth(date: visibleMonth, calendar: calendar)
        return today.year == month.year && today.month == month.month ? today : nil
    }

    private func summary(for day: LocalPrayerDay) -> MakeupPrayerDaySummary? {
        store.makeupDaySummaries.first { $0.day == day }
    }

    private func loadMonth() {
        selectedDay = nil
        store.loadMakeupCalendar(for: visibleMonth, calendar: calendar)
    }

    private func moveMonth(by value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func isDayVisible(_ day: LocalPrayerDay) -> Bool {
        let month = MakeupPrayerMonth(date: visibleMonth, calendar: calendar)
        return day.year == month.year && day.month == month.month
    }

    private func dayBackground(selected: Bool, count: Int) -> Color {
        if selected { return .vaktPrimary }
        if count > 0 { return .vaktGlow.opacity(0.09) }
        return .clear
    }

    private func dayForeground(selected: Bool, count: Int) -> Color {
        if selected { return .vaktBg }
        if count > 0 { return .vaktPrimary }
        return .vaktSecondary
    }

    private func dayTitle(_ day: LocalPrayerDay) -> String {
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
            return day.databaseValue
        }
        return date.formatted(
            .dateTime.day().month(.wide).weekday(.wide).locale(VaktLocalization.appLocale)
        )
    }

    private func dayCountText(_ count: Int) -> String {
        let key = count == 1 ? "makeup.day.count.one" : "makeup.day.count.many"
        return L10n.formatString(key, MakeupNumberFormatter.string(count))
    }

    private func prayerName(_ prayer: PrayerKey) -> String {
        switch prayer {
        case .fajr: Prayer.fajr.localizedName
        case .dhuhr: Prayer.dhuhr.localizedName
        case .asr: Prayer.asr.localizedName
        case .maghrib: Prayer.maghrib.localizedName
        case .isha: Prayer.isha.localizedName
        }
    }

    private func prayerIcon(_ prayer: PrayerKey) -> String {
        switch prayer {
        case .fajr: "sun.horizon"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon.stars"
        }
    }
}

private enum MakeupNumberFormatter {
    static func string(_ value: Int) -> String {
        value.formatted(.number.locale(VaktLocalization.appLocale))
    }
}
