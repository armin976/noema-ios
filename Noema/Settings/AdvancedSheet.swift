import SwiftUI

struct AdvancedSheet: View {
    @ObservedObject var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                memorySection
                retrievalSection
                diagnosticsSection
                developerFlagsSection
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.background.ignoresSafeArea())
            .listStyle(.insetGrouped)
            .navigationTitle("Advanced")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .a11yTarget()
                }
            }
        }
    }

    private var memorySection: some View {
        Section("Memory") {
            Toggle(isOn: $settings.bypassRAMCheck) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    Text("Bypass RAM safety checks")
                        .font(Tokens.Typography.body)
                    Text("Loads oversized models anyway. Use only if you understand the risks.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.muted)
                }
            }
            .a11yLabel("Bypass RAM safety checks")
            .a11yTarget()
        }
    }

    private var retrievalSection: some View {
        Section("Retrieval") {
            Stepper(value: $settings.ragMaxChunks, in: 1...8) {
                HStack {
                    Text("Max chunks: \(settings.ragMaxChunks)")
                        .font(Tokens.Typography.body)
                    Spacer()
                    Text("1–8")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.muted)
                }
            }
            .a11yLabel("Maximum retrieved chunks")
            .a11yHint("Controls how many passages can be inserted per answer.")
            .a11yTarget()

            VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
                HStack {
                    Text("Similarity threshold")
                        .font(Tokens.Typography.body)
                    Spacer()
                    Text(settings.ragMinScore.formatted(.number.precision(.fractionLength(2))))
                        .font(Tokens.Typography.mono)
                        .foregroundStyle(Tokens.Colors.muted)
                }
                Slider(value: $settings.ragMinScore, in: 0...1)
                    .a11yLabel("Similarity threshold slider")
                Text("Lower values add more results; higher values require stronger matches.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.muted)
            }
            .padding(.vertical, Tokens.Spacing.xSmall)
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle(isOn: $settings.verboseLogging) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    Text("Verbose logs")
                        .font(Tokens.Typography.body)
                    Text("Prints additional downloader and runtime diagnostics to the console.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.muted)
                }
            }
            .a11yLabel("Verbose logging")
            .a11yTarget()
        }
    }

    private var developerFlagsSection: some View {
        Section("Developer") {
            Toggle(isOn: $settings.pythonEnabled) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    Text("Offline Python runtime")
                        .font(Tokens.Typography.body)
                    Text("Disables notebooks when turned off. Restart sessions after changing.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.muted)
                }
            }
            .a11yLabel("Offline Python runtime")
            .a11yTarget()

            Toggle(isOn: $settings.showMultimodalUI) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    Text("Enable multimodal UI")
                        .font(Tokens.Typography.body)
                    Text("Reveals experimental image inputs and vision affordances.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.muted)
                }
            }
            .a11yLabel("Enable multimodal interface")
            .a11yTarget()
        }
    }
}
