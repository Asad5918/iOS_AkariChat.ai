import SwiftUI

/// First-launch screen: choose a local model, download it, then load it into memory.
struct ModelSetupView: View {
    @Environment(ModelManager.self) private var manager

    var body: some View {
        @Bindable var manager = manager
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Set up Akari").font(.largeTitle.bold())
            Text("Your chats run entirely on this iPhone. Download a model once, then chat offline and privately.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(ModelOption.all) { option in
                    Button {
                        manager.selected = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.headline)
                                Text(option.sizeLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == ModelOption.recommended {
                                Text("Recommended").font(.caption2.bold()).foregroundStyle(.tint)
                            }
                            Image(systemName: manager.selected == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(manager.selected == option ? Color.accentColor : .secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal)

            statusView

            Spacer()
        }
        .padding()
    }

    private var isBusy: Bool {
        switch manager.state {
        case .downloading, .loading: true
        default: false
        }
    }

    @ViewBuilder private var statusView: some View {
        switch manager.state {
        case .idle:
            Button(manager.hasDownloadedSelected ? "Load model" : "Download & start") {
                Task { await manager.prepare() }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        case .downloading(let fraction):
            VStack(spacing: 8) {
                ProgressView(value: fraction)
                Text("Downloading… \(Int(fraction * 100))%").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading model into memory…").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try again") { Task { await manager.prepare() } }
                    .buttonStyle(.borderedProminent)
            }
        case .ready:
            EmptyView()
        }
    }
}
