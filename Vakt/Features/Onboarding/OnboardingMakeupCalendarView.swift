import SwiftUI

struct OnboardingMakeupCalendarView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var phase: MakeupCalendarPhase = .month
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.makeup_calendar.eyebrow"),
            title: L10n.string("onboarding.makeup_calendar.title"),
            bodyText: L10n.string("onboarding.makeup_calendar.body"),
            actionTitle: L10n.string("action.continue"),
            onContinue: onContinue
        ) {
            MakeupCalendarScene(
                phase: phase,
                reduceMotion: reduceMotion,
                onSelectDay: stopDemoAndOpenDay,
                onComplete: stopDemoAndComplete
            )
        }
        .onAppear { startDemo() }
        .onDisappear { demoTask?.cancel() }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                setPhase(.month)
                try? await Task.sleep(for: .milliseconds(1_600))
                setPhase(.dayOpen)
                try? await Task.sleep(for: .milliseconds(2_100))
                setPhase(.completing)
                try? await Task.sleep(for: .milliseconds(1_100))
                setPhase(.completed)
                try? await Task.sleep(for: .milliseconds(2_700))
            }
        }
    }

    private func setPhase(_ nextPhase: MakeupCalendarPhase) {
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.88)) {
            phase = nextPhase
        }
    }

    private func stopDemoAndOpenDay() {
        demoTask?.cancel()
        UISelectionFeedbackGenerator().selectionChanged()
        setPhase(.dayOpen)
    }

    private func stopDemoAndComplete() {
        demoTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        setPhase(.completed)
    }
}

private enum MakeupCalendarPhase: Equatable {
    case month
    case dayOpen
    case completing
    case completed
}

private struct MakeupCalendarScene: View {
    let phase: MakeupCalendarPhase
    let reduceMotion: Bool
    let onSelectDay: () -> Void
    let onComplete: () -> Void

    private let debtDays = [4: 1, 9: 2, 14: 1, 18: 1]

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
                .padding(.top, 12)

            calendar
                .padding(.top, 12)

            dayDetail
                .padding(.top, 14)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, VaktSpace.lg)
    }

    private var calendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(OnboardingMakeupCalendarFormatter.monthName)
                .font(VaktFont.eyebrow(9))
                .tracking(1.7)
                .foregroundStyle(Color.vaktSecondary)

            Spacer()

            Text(remainingText)
                .font(VaktFont.caption(10))
                .foregroundStyle(phase == .completed ? Color.vaktPrimary : Color.vaktMuted)
                .contentTransition(.numericText())
        }
    }

    private var calendar: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(OnboardingMakeupCalendarFormatter.weekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(VaktFont.caption(8))
                        .foregroundStyle(Color.vaktMuted.opacity(0.72))
                        .frame(height: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(1...21, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    }

    private func dayCell(_ day: Int) -> some View {
        let selected = day == 9 && phase != .month
        let debtCount = debtCount(for: day)

        return Button {
            guard day == 9 else { return }
            onSelectDay()
        } label: {
            VStack(spacing: 5) {
                Text(OnboardingMakeupCalendarFormatter.number(day))
                    .font(VaktFont.body(11))
                    .foregroundStyle(selected ? Color.vaktDeep : day == 12 ? Color.vaktPrimary : Color.vaktSecondary)

                HStack(spacing: 2) {
                    ForEach(0..<max(1, debtCount), id: \.self) { index in
                        Capsule()
                            .fill(index < debtCount ? Color.vaktAccent.opacity(selected ? 0.72 : 0.42) : Color.clear)
                            .frame(width: 7, height: 1.5)
                    }
                }
                .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 43)
            .background(selected ? Color.vaktPrimary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .disabled(day != 9)
        .accessibilityLabel(dayAccessibilityLabel(day: day, debtCount: debtCount))
        .accessibilityHint(day == 9
            ? L10n.string("onboarding.makeup_calendar.day.hint.select")
            : "")
    }

    private var dayDetail: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phase == .month
                        ? L10n.string("onboarding.makeup_calendar.day.select")
                        : OnboardingMakeupCalendarFormatter.dayAndMonth(9))
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(detailSubtitle)
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                        .contentTransition(.opacity)
                }

                Spacer()

                Image(systemName: phase == .completed ? "checkmark" : "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(phase == .completed ? Color.vaktPrimary : Color.vaktSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(height: 46)

            if phase != .month {
                Rectangle()
                    .fill(Color.vaktBorder.opacity(0.7))
                    .frame(height: 0.5)

                prayerRow(
                    prayer: .dhuhr,
                    time: OnboardingDemoTimeFormatter.string(hour: 13, minute: 11),
                    completed: false,
                    interactive: false
                )

                Rectangle()
                    .fill(Color.vaktBorder.opacity(0.7))
                    .frame(height: 0.5)

                prayerRow(
                    prayer: .asr,
                    time: OnboardingDemoTimeFormatter.string(hour: 17, minute: 8),
                    completed: phase == .completed,
                    interactive: true
                )
            }
        }
        .padding(.horizontal, 14)
        .background(Color.vaktElevated.opacity(phase == .month ? 0.28 : 0.52))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.58), lineWidth: 0.5)
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.38), value: phase)
    }

    private func prayerRow(prayer: Prayer, time: String, completed: Bool, interactive: Bool) -> some View {
        Button {
            guard interactive else { return }
            onComplete()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(completed ? Color.vaktPrimary : Color.vaktMuted)
                    .contentTransition(.symbolEffect(.replace))

                Text(L10n.prayerName(prayer))
                    .font(VaktFont.body(11))
                    .foregroundStyle(completed ? Color.vaktMuted : Color.vaktSecondary)

                Spacer()

                Text(completed ? L10n.string("onboarding.makeup_calendar.status.completed") : time)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(completed ? Color.vaktPrimary : Color.vaktMuted)
                    .monospacedDigit()
                    .contentTransition(.opacity)
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .disabled(!interactive)
    }

    private func debtCount(for day: Int) -> Int {
        guard day == 9, phase == .completed else { return debtDays[day] ?? 0 }
        return 1
    }

    private var remainingText: String {
        L10n.formatString(
            phase == .completed
                ? "onboarding.makeup_calendar.remaining.after"
                : "onboarding.makeup_calendar.remaining.pending",
            OnboardingMakeupCalendarFormatter.number(phase == .completed ? 4 : 5)
        )
    }

    private var detailSubtitle: String {
        switch phase {
        case .month:
            L10n.string("onboarding.makeup_calendar.detail.idle")
        case .dayOpen:
            L10n.formatString(
                "onboarding.makeup_calendar.detail.count",
                OnboardingMakeupCalendarFormatter.number(2)
            )
        case .completing:
            L10n.string("onboarding.makeup_calendar.detail.completing")
        case .completed:
            L10n.string("onboarding.makeup_calendar.detail.completed")
        }
    }

    private func dayAccessibilityLabel(day: Int, debtCount: Int) -> String {
        let date = OnboardingMakeupCalendarFormatter.dayAndMonth(day)
        guard debtCount > 0 else { return date }

        return L10n.formatString(
            debtCount == 1
                ? "onboarding.makeup_calendar.day.accessibility.one"
                : "onboarding.makeup_calendar.day.accessibility.many",
            date,
            OnboardingMakeupCalendarFormatter.number(debtCount)
        )
    }
}

private enum OnboardingMakeupCalendarFormatter {
    private static let locale = VaktLocalization.appLocale

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static var date: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)) ?? Date(timeIntervalSince1970: 0)
    }

    static var monthName: String {
        monthFormatter.string(from: date).uppercased(with: locale)
    }

    static var weekdaySymbols: [String] {
        let symbols = monthFormatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    static func dayAndMonth(_ day: Int) -> String {
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: day)) else {
            return number(day)
        }
        return dayMonthFormatter.string(from: date)
    }

    static func number(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
