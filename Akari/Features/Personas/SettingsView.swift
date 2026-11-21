import SwiftUI

/// Model switcher and sampling controls, for experimenting with how human the replies sound.
struct SettingsView: View {
    @Environment(ModelManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(GenerationParams.Keys.temperature) private var temperature = 0.85
    @AppStorage(GenerationParams.Keys.topP) private var topP = 0.9
    @AppStorage(GenerationParams.Keys.repetitionPenalty) private var repetitionPenalty = 1.1
    @AppStorage(GenerationParams.Keys.maxTokens) private var maxTokens = 160

    @State private var customID = ""

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                customSection
                generationSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    // MARK: Models

    private var modelSection: some View {
        Section {
            ForEach(ModelOption.all) { option in row(option) }
            if case .failed(let message) = manager.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Switching unloads the current model. Models download once, then load from storage. Chat is paused while a model loads.")
        }
    }

    private func row(_ option: ModelOption) -> some View {
        Button {
            Task { await manager.switchTo(option) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).foregroundStyle(.primary)
                    Text(option.sizeLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                trailing(for: option)
            }
        }
        .disabled(manager.isBusy || ModelManager.isSimulator)
    }

    @ViewBuilder private func trailing(for option: ModelOption) -> some View {
        if manager.selected == option, manager.isBusy {
            switch manager.state {
            case .downloading(let f):
                HStack(spacing: 6) { ProgressView(value: f).frame(width: 60); Text("\(Int(f * 100))%").font(.caption) }
            default:
                ProgressView()
            }
        } else if manager.loaded == option {
            Label("Active", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                .font(.caption).foregroundStyle(.green)
        } else if manager.isDownloaded(option) {
            Text("Downloaded").font(.caption).foregroundStyle(.secondary)
        } else {
            Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary)
        }
    }

    private var customSection: some View {
        Section {
            TextField("mlx-community/model-name", text: $customID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Download & use") {
                let id = customID.trimmingCharacters(in: .whitespaces)
                guard id.contains("/") else { return }
                Task { await manager.switchTo(.custom(id: id)) }
            }
            .disabled(manager.isBusy || !customID.contains("/"))
        } header: {
            Text("Custom model")
        } footer: {
            Text("Any MLX-format chat model on Hugging Face, e.g. mlx-community/…-Instruct-4bit. Large models may exceed this iPhone's memory.")
        }
    }

    // MARK: Generation

    private var generationSection: some View {
        Section {
            slider("Temperature", value: $temperature, range: 0.3...1.4, step: 0.05)
            slider("Top-p", value: $topP, range: 0.5...1.0, step: 0.05)
            slider("Repetition penalty", value: $repetitionPenalty, range: 1.0...1.4, step: 0.05)
            Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 40...400, step: 20)
            Button("Reset to defaults", role: .destructive) {
                temperature = 0.85; topP = 0.9; repetitionPenalty = 1.1; maxTokens = 160
            }
        } header: {
            Text("Generation")
        } footer: {
            Text("Higher temperature = more casual and unpredictable. Applies to the next message.")
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step)
        }
    }
}
