import SwiftUI
import UIKit

extension Color {
    /// Initialise depuis un hex `#rrggbb` / `rrggbb` / `#rgb`.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 3 else { return nil }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard let number = UInt64(value, radix: 16) else { return nil }
        let red = Double((number & 0xFF0000) >> 16) / 255
        let green = Double((number & 0x00FF00) >> 8) / 255
        let blue = Double(number & 0x0000FF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    /// Représentation hex `#rrggbb`.
    func toHex() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
