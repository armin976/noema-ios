#if os(visionOS)
import SwiftUI
import UIKit

/// Simplified chat experience tailored for visionOS builds. The main iOS chat
/// surface relies heavily on UIKit-specific modifiers, so we provide a native
/// visionOS-friendly variant that focuses on core messaging functionality.
struct ChatView: View {
    @EnvironmentObject private var vm: ChatVM
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var scrollProxy: ScrollViewProxy?
    @State private var focusedMessageID: ChatVM.Msg.ID?

    private var bindingForPrompt: Binding<String> {
        Binding(get: { vm.prompt }, set: { vm.prompt = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.4)

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).opacity(0.6))

            Divider()
                .opacity(0.4)

            inputBar
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .glassBackgroundEffect()
        }
        .task(id: vm.msgs.count) {
            await scrollToBottom(animated: true)
        }
        .onChange(of: tabRouter.selection) { _, newValue in
            guard newValue == .chat else { return }
            Task { await scrollToBottom(animated: false) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chat")
                    .font(.system(size: 28, weight: .semibold))
                if let loadError = vm.loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if vm.isStreaming {
                    Text("Streaming response…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if vm.prompt.isEmpty {
                    Text("Ask Noema anything")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                vm.startNewSession()
            } label: {
                Label("New Chat", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 28)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(messagesForDisplay) { msg in
                        messageBubble(for: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Message", text: bindingForPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemBackground).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .disabled(vm.isStreaming)

                Button {
                    if vm.isStreaming {
                        vm.stop()
                    } else {
                        let text = vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        Task { await vm.send() }
                    }
                } label: {
                    Label(vm.isStreaming ? "Stop" : "Send", systemImage: vm.isStreaming ? "stop.fill" : "paperplane.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isStreaming ? .red : .accentColor)
                .disabled(vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isStreaming)
            }

            if vm.crossSessionSendBlocked {
                Text("Complete the streaming response in the active chat before sending again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var messagesForDisplay: [ChatVM.Msg] {
        vm.msgs.filter { $0.role.lowercased() != "system" }
    }

    private func title(for msg: ChatVM.Msg) -> String {
        switch msg.role {
        case "🧑‍💻":
            return "You"
        case "🤖":
            return "Noema"
        default:
            return msg.role
        }
    }

    @ViewBuilder
    private func messageBubble(for msg: ChatVM.Msg) -> some View {
        let isUser = msg.role == "🧑‍💻"
        let isFocused = focusedMessageID == msg.id

        VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(for: msg))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(msg.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isUser ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(isFocused ? 0.18 : 0.05), lineWidth: 1.5)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if isFocused {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = msg.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.medium))
                            .padding(10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                focusedMessageID = focusedMessageID == msg.id ? nil : msg.id
            }
        }
    }

    @MainActor
    private func scrollToBottom(animated: Bool) async {
        guard let last = messagesForDisplay.last else { return }
        if animated {
            withAnimation { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
        } else {
            scrollProxy?.scrollTo(last.id, anchor: .bottom)
        }
    }
}
#endif
