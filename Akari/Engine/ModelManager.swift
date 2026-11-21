import Foundation
import Observation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

struct ModelOption: Identifiable, Hashable {
    let id: String          // Hugging Face repo id
    let title: String
    let sizeLabel: String
    let minRAMGB: Double

    /// Known models resolve to their tuned configuration (EOS tokens etc.); unknown ids load as-is.
    var configuration: ModelConfiguration { LLMRegistry.shared.configuration(id: id) }

    /// Gemma 2's chat template has no system role.
    var foldsSystemPrompt: Bool { id.lowercased().contains("gemma-2") }

    static let all: [ModelOption] = [
        .init(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", title: "Llama 3.2 3B", sizeLabel: "~1.8 GB · best quality", minRAMGB: 7),
        .init(id: "mlx-community/Phi-3.5-mini-instruct-4bit", title: "Phi 3.5 mini (3.8B)", sizeLabel: "~2.2 GB · strong, a bit formal", minRAMGB: 7),
        .init(id: "mlx-community/gemma-2-2b-it-4bit", title: "Gemma 2 2B", sizeLabel: "~1.5 GB · natural chat tone", minRAMGB: 5),
        .init(id: "mlx-community/gemma-3-1b-it-qat-4bit", title: "Gemma 3 1B", sizeLabel: "~0.7 GB · small, chatty", minRAMGB: 4),
        .init(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", title: "Qwen 2.5 1.5B", sizeLabel: "~0.9 GB · balanced", minRAMGB: 5),
        .init(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", title: "Llama 3.2 1B", sizeLabel: "~0.7 GB · fastest", minRAMGB: 3),
        .init(id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit", title: "Llama 3.1 8B (heavy)", sizeLabel: "~4.5 GB · needs 8 GB+ iPhone", minRAMGB: 8),
    ]

    static func custom(id: String) -> ModelOption {
        .init(id: id, title: id.split(separator: "/").last.map(String.init) ?? id, sizeLabel: "custom", minRAMGB: 0)
    }

    static var recommended: ModelOption {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let preferred = [
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "mlx-community/gemma-3-1b-it-qat-4bit",
            "mlx-community/Llama-3.2-1B-Instruct-4bit",
        ]
        for id in preferred {
            if let o = all.first(where: { $0.id == id }), ramGB >= o.minRAMGB { return o }
        }
        return all[all.count - 2]
    }

    static func resolve(id: String?) -> ModelOption {
        guard let id else { return recommended }
        return all.first { $0.id == id } ?? custom(id: id)
    }
}

@Observable
final class ModelManager {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private static let selectedKey = "selectedModelID"
    private static let downloadedKey = "downloadedModelIDs"

    var state: State = .idle
    var selected: ModelOption {
        didSet { UserDefaults.standard.set(selected.id, forKey: Self.selectedKey) }
    }
    /// The model currently loaded in memory (nil while loading or before first load).
    private(set) var loaded: ModelOption?
    private(set) var engine: LLMEngine?
    /// Once a model has loaded, the main UI stays up even while switching models.
    private(set) var hasLoadedOnce = false

    /// MLX needs a real GPU; the Simulator can't run it, so it falls back to the mock engine.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    init() {
        selected = ModelOption.resolve(id: UserDefaults.standard.string(forKey: Self.selectedKey))
        if Self.isSimulator {
            engine = MockEngine()
            hasLoadedOnce = true
            state = .ready
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .loading: true
        default: false
        }
    }

    func isDownloaded(_ option: ModelOption) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.downloadedKey) ?? []).contains(option.id)
    }

    var hasDownloadedSelected: Bool { isDownloaded(selected) }

    /// Called at launch: silently loads the model if it was already downloaded.
    func autoLoadIfDownloaded() async {
        guard engine == nil, hasDownloadedSelected else { return }
        await prepare()
    }

    /// Switches to another model (downloading it first if needed).
    func switchTo(_ option: ModelOption) async {
        guard !isBusy else { return }
        if option == loaded, engine != nil { selected = option; return }
        selected = option
        await prepare()
    }

    func prepare() async {
        guard !Self.isSimulator, !isBusy else { return }
        let option = selected
        let alreadyDownloaded = isDownloaded(option)
        state = alreadyDownloaded ? .loading : .downloading(0)
        // Release the current model first so two models are never resident at once.
        engine = nil
        loaded = nil
        do {
            let container = try await loadModelContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: option.configuration,
                progressHandler: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
            )
            markDownloaded(option.id)
            engine = MLXEngine(container: container, foldSystemPrompt: option.foldsSystemPrompt)
            loaded = option
            hasLoadedOnce = true
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func markDownloaded(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.downloadedKey) ?? []
        if !ids.contains(id) { ids.append(id) }
        UserDefaults.standard.set(ids, forKey: Self.downloadedKey)
    }
}
