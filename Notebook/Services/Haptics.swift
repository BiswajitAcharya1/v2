import UIKit

@MainActor
enum Haptics {
    static func softTap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
    }

    static func press() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72)
    }

    static func open() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.78)
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.64)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
