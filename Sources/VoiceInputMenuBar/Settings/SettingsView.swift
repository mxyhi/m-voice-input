import SwiftUI
import VoiceInputCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppSettings
    @Published var statusMessage = ""
    @Published var isTesting = false

    private let onSave: @MainActor (AppSettings) -> Void
    private let onTest: @MainActor (AppSettings) async throws -> String

    init(
        initialSettings: AppSettings,
        onSave: @escaping @MainActor (AppSettings) -> Void,
        onTest: @escaping @MainActor (AppSettings) async throws -> String
    ) {
        draft = initialSettings
        self.onSave = onSave
        self.onTest = onTest
    }

    func reload(_ settings: AppSettings) {
        draft = settings
        statusMessage = ""
        isTesting = false
    }

    func save() {
        onSave(draft)
        statusMessage = "已保存"
    }

    func test() {
        isTesting = true
        statusMessage = "Testing..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let refined = try await onTest(draft)
                statusMessage = "Test 成功：\(refined)"
            } catch {
                statusMessage = error.localizedDescription
            }

            isTesting = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LLM Refinement Settings")
                .font(.system(size: 20, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("API Base URL")
                        .frame(width: 96, alignment: .leading)
                    TextField("https://api.openai.com/v1", text: $viewModel.draft.llm.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("API Key")
                        .frame(width: 96, alignment: .leading)
                    TextField("sk-...", text: $viewModel.draft.llm.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Model")
                        .frame(width: 96, alignment: .leading)
                    TextField("gpt-4.1-mini", text: $viewModel.draft.llm.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                Button("Test") {
                    viewModel.test()
                }
                .disabled(viewModel.isTesting)

                Button("Save") {
                    viewModel.save()
                }

                Spacer()

                Text(viewModel.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 280)
    }
}
