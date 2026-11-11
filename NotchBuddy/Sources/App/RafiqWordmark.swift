import SwiftUI

/// "Rafiq رفيق": the name in both scripts, the Arabic in kufi and gold.
/// Drawn with fonts macOS already has (KufiStandardGK, then the system Arabic font).
struct RafiqWordmark: View {
    var size: CGFloat = 15
    var weight: Font.Weight = .bold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.35) {
            Text(verbatim: "Rafiq")
                .font(.system(size: size, weight: weight))
            Text(verbatim: "رفيق")
                .font(.custom("KufiStandardGK", size: size * 1.02))
                .foregroundColor(RafiqLook.gold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Rafiq"))
    }
}

enum RafiqName {
    static let arabic = "رفيق"
    static let vocalised = "رَفِيق"

    /// The name for AppKit (the menu): "Rafiq" then "رفيق" in gold.
    @MainActor static func attributed(size: CGFloat = 13) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "Rafiq ", attributes: [.font: NSFont.systemFont(ofSize: size, weight: .bold)])
        let arabicFont = NSFont(name: "KufiStandardGK", size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
        s.append(NSAttributedString(string: arabic, attributes: [.font: arabicFont, .foregroundColor: NSColor(RafiqLook.gold)]))
        return s
    }
}
