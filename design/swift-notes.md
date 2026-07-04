// Ufuk çizgisi — Canvas ile
struct HorizonView: View {
    let dots: [SafMember]
    
    var body: some View {
        Canvas { ctx, size in
            let lineY = size.height * 0.6
            // Ufuk çizgisi
            ctx.stroke(Path { p in
                p.move(to: .init(x: 0, y: lineY))
                p.addLine(to: .init(x: size.width, y: lineY))
            }, with: .color(.accent.opacity(0.5)), lineWidth: 0.5)
            
            // Noktalar — durum bazlı boyut ve opaklık
            for dot in dots {
                let x = dot.normalizedPosition * size.width
                ctx.fill(Circle().path(in: .init(
                    x: x - dot.radius, y: lineY - dot.radius,
                    width: dot.radius*2, height: dot.radius*2
                )), with: .color(dot.color))
            }
        }
        .accessibilityLabel("\(dots.count) kişi seninle ufukta")
    }
}

// İmza etkileşim — basılı tut
.onLongPressGesture(minimumDuration: 1.5) {
    withAnimation(.easeInOut(duration: 0.3)) {
        isEnteringQuietMode = true
    }
}

// Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
.animation(reduceMotion ? .none : .easeInOut, value: dotPositions)

// ActivityKit — Live Activity
struct VaktActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prayerName: String
        var countdown: Int
        var memberCount: Int
        var userStatus: PrepStatus
    }
}