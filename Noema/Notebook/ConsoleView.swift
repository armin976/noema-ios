import SwiftUI

struct ConsoleLine: Identifiable, Equatable {
    let id = UUID()
    let kind: PythonLogKind
    let text: String
    let timestamp: Date

    init(kind: PythonLogKind, text: String, timestamp: Date) {
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }

    init(persisted: ConsolePersistedLine) {
        self.init(kind: persisted.kind, text: persisted.text, timestamp: persisted.timestamp)
    }

    func toPersisted() -> ConsolePersistedLine {
        ConsolePersistedLine(kind: kind, text: text, timestamp: timestamp)
    }
}

struct ConsoleView: View {
    let lines: [ConsoleLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: lines.last?.id) { lastID in
                guard let lastID else { return }
                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: PythonLogKind) -> Color {
        switch kind {
        case .stderr:
            return .red
        case .status:
            return .secondary
        case .stdout:
            return .primary
        }
    }
}
