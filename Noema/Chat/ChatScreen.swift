import SwiftUI

struct ChatScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ChatViewModel

    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: viewModel.messages.count) { _ in
                        guard let last = viewModel.messages.last else { return }
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if let status = viewModel.statusText {
                    Text(status)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ChatStatusLabel")
                }
                HStack(spacing: 8) {
                    TextField("Ask something…", text: $viewModel.input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("ChatPromptField")
                        .onSubmit { viewModel.send() }
                    if viewModel.isStreaming {
                        Button(action: viewModel.stop) {
                            Image(systemName: "stop.fill")
                                .padding(8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier("ChatStopButton")
                    } else {
                        Button(action: viewModel.send) {
                            Image(systemName: "paperplane.fill")
                                .padding(8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSend)
                        .accessibilityIdentifier("ChatSendButton")
                    }
                }
            }
            .padding()
            .navigationTitle("Chat (Debug)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
        }
        .alert(item: $viewModel.alert) { info in
            Alert(title: Text("Error"), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatViewModel.Message) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            Text(messageDisplayText(message))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .padding(12)
                .background(bubbleColor(for: message))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier(message.role == .assistant ? "AssistantMessage" : "UserMessage")
        }
    }

    private func messageDisplayText(_ message: ChatViewModel.Message) -> String {
        if message.text.isEmpty && message.isStreaming {
            return "…"
        }
        return message.text
    }

    private func bubbleColor(for message: ChatViewModel.Message) -> Color {
        message.role == .user ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground)
    }
}
