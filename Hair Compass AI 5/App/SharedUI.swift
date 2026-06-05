import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

let appBackground = LinearGradient(
    colors: [
        Color(red: 0.957, green: 0.933, blue: 0.875), // #F4EEDF
        Color(red: 0.910, green: 0.918, blue: 0.867), // #E8EADD
        Color(red: 0.965, green: 0.957, blue: 0.925)  // #F6F4EC
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

extension View {
    /// Hero/primary cards: glass card — rgba(255,255,255,0.82) + forest border
    func heroCardStyle() -> some View {
        self
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: PremiumTheme.forest.opacity(0.06), radius: 18, y: 8)
    }

    /// Standard glass cards: 16–22px radius
    func cardStyle() -> some View {
        self
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: PremiumTheme.forest.opacity(0.05), radius: 12, y: 6)
    }

    /// Recessed/secondary cards: lighter glass
    func secondaryCardStyle() -> some View {
        self
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PremiumTheme.forest.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: PremiumTheme.forest.opacity(0.04), radius: 6, y: 3)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [HairProfile.self, CheckInEntry.self, RoutineTask.self, PhotoRecord.self, MedicationLog.self, MedicationDoseEntry.self, RoutineCompletionEntry.self, ProcedureEvent.self, LifestyleEntry.self, LabResultEntry.self, HairTriggerEvent.self], inMemory: true)
}
