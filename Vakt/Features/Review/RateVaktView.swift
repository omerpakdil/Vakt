import StoreKit
import SwiftUI

struct RateVaktView: View {
    let completedPrayerCount: Int
    let onRate: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @State private var appeared = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: VaktSpace.xxl)

                reviewSymbol
                    .padding(.bottom, 34)

                VStack(spacing: 12) {
                    Text(L10n.string("review.title"))
                        .font(VaktFont.title(31))
                        .foregroundStyle(Color.vaktPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(L10n.string("review.body"))
                        .font(VaktFont.body(15))
                        .foregroundStyle(Color.vaktMuted)
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Spacer(minLength: VaktSpace.xl)

                VStack(spacing: 11) {
                    VaktButton(title: L10n.string("review.action.rate"), style: .primary) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        requestReview()
                        onRate()
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onNotNow()
                    } label: {
                        Text(L10n.string("action.not_now"))
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(VaktPressStyle())
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .padding(.bottom, VaktSpace.xl)
            }
            .padding(.horizontal, VaktSpace.lg)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.75)) {
                appeared = true
            }
        }
    }

    private var background: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.vaktElevated.opacity(0.58),
                    Color.vaktBg.opacity(0.28),
                    Color.vaktDeep.opacity(0)
                ],
                center: .center,
                startRadius: 10,
                endRadius: 360
            )
            .scaleEffect(1.2)
            .ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [
                        Color.vaktGlow.opacity(0.09),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)

                Spacer()
            }
            .ignoresSafeArea()
        }
    }

    private var reviewSymbol: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.vaktGlow.opacity(0.12 - Double(index) * 0.025), lineWidth: 0.7)
                    .frame(width: CGFloat(118 + index * 42), height: CGFloat(118 + index * 42))
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(
                        reduceMotion ? .none : .easeOut(duration: 0.8).delay(Double(index) * 0.09),
                        value: appeared
                    )
            }

            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.vaktPrimary.opacity(0.82))
                            .scaleEffect(appeared ? 1 : 0.72)
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82).delay(0.16 + Double(index) * 0.055),
                                value: appeared
                            )
                    }
                }

                Text(
                    L10n.formatString(
                        "review.prayers_marked",
                        ReviewNumberFormatter.string(completedPrayerCount)
                    )
                )
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(0.4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 132, height: 132)
            .background(Color.vaktSurface.opacity(0.72))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.vaktGlow.opacity(0.22), lineWidth: 0.7)
            )
            .shadow(color: Color.vaktGlow.opacity(0.12), radius: 28, y: 14)
        }
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.formatString(
                "review.prayers_marked",
                ReviewNumberFormatter.string(completedPrayerCount)
            )
        )
    }
}

private enum ReviewNumberFormatter {
    static func string(_ value: Int) -> String {
        value.formatted(.number.locale(VaktLocalization.appLocale))
    }
}
