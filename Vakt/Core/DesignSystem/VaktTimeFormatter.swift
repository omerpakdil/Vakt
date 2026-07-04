import Foundation

enum VaktTimeFormatter {
    static func string(
        from date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone

        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: date)
    }
}
