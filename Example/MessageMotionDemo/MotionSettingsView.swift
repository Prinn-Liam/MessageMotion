import SwiftUI
import UIKit
import MessageMotion

struct MotionSettingsView: View {
    @Binding var configuration: MotionConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Native springs") {
                    parameter("Frequency", value: $configuration.frequency, range: 0.4...8, step: 0.1,
                              detail: "Hz. Higher values respond and settle faster. The starting preset is 4.5 Hz.")
                    parameter("Damping", value: $configuration.damping, range: 0.2...1, step: 0.05,
                              detail: "1 is critical damping for UIKit attachments. Lower values allow more oscillation.")
                    parameter("Deformation strength", value: $configuration.dragStrength, range: 0...2.5, step: 0.05,
                              detail: "Scales distance-weighted scroll input. No additional velocity compensation is used.")
                }
                Section("Spacing and deceleration") {
                    parameter("Minimum gap ratio", value: $configuration.minimumGapRatio, range: 0...1, step: 0.05,
                              detail: "Fraction of normal gap. 0 permits touching; 1 prevents compression below normal.")
                    parameter("Normal gap", value: $configuration.normalGap, range: 0...32, step: 1,
                              detail: "Resting visible bubble spacing, in points. Changing it remeasures the rows.")
                    Toggle("Deform while decelerating", isOn: $configuration.deformsDuringDeceleration)
                        .accessibilityIdentifier("demo.coastInjection")
                    Text("The last finger position remains the reference during native momentum. Edge rubber-banding adds no new deformation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Reset default preset") { configuration = .messagesLike }
                        .accessibilityIdentifier("demo.resetPreset")
                    Button("Copy configuration") {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        if let data = try? encoder.encode(configuration), let string = String(data: data, encoding: .utf8) {
                            UIPasteboard.general.string = string
                            copied = true
                        }
                    }
                } footer: { Text("Session-only settings. No account, network or persistent storage.") }
            }
            .navigationTitle("Motion settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Configuration copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit() }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
