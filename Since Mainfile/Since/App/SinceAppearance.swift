import SwiftUI

enum SinceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "sinceAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum SinceCornerRadius {
    static let compact: CGFloat = 12
    static let card: CGFloat = 18
    static let prominent: CGFloat = 24
}

enum SinceMotion {
    static let quickDuration = 0.18
    static let standardDuration = 0.22

    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: quickDuration)
    }

    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: standardDuration)
    }
}

private struct SinceCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                                lineWidth: 0.75
                            )
                    }
            }
    }
}

extension View {
    func sinceCardSurface(radius: CGFloat = SinceCornerRadius.card) -> some View {
        modifier(SinceCardSurface(radius: radius))
    }
}
