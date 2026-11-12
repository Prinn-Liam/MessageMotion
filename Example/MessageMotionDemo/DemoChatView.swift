import SwiftUI
import MessageMotion

struct DemoMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    let outgoing: Bool

    static func fixtures(count: Int = 40) -> [Self] {
        let text = [
            "The light along the trail was beautiful this morning. We should go again next weekend.",
            "I'd love that. Let's start early and bring coffee for the walk.",
            "Sounds good! I can bring a thermos and something for breakfast.",
            "Perfect. I'll check the weather and find a quiet spot by the lake."
        ]
        return (0..<count).map { index in
            Self(id: UUID(), text: "\(index + 1) · \(text[index % text.count])", outgoing: index.isMultiple(of: 2))
        }
    }
}

struct DemoChatView: View {
    @State private var messages = DemoMessage.fixtures(count: ProcessInfo.processInfo.arguments.contains("--empty") ? 0 :
        (ProcessInfo.processInfo.arguments.contains("--long-thread") ? 400 : 40))
    @State private var draft = ""
    @State private var configuration = MotionConfiguration.messagesLike
    @State private var settingsPresented = false
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MessageMotion").font(.headline)
                    Text("Native chat physics").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    messages.append(.init(id: UUID(), text: "An incoming message. History stays put when you're reading earlier messages.", outgoing: false))
                } label: { Image(systemName: "plus.bubble") }
                    .accessibilityLabel("Receive message")
                    .accessibilityIdentifier("demo.receive")
                Button { settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Motion settings")
                    .accessibilityIdentifier("demo.settings")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            MotionChat(messages: messages, isComposing: composing, configuration: configuration,
                       reduceMotion: ProcessInfo.processInfo.arguments.contains("--reduce-motion"), isOutgoing: { $0.outgoing }) { message in
                HStack {
                    if message.outgoing { Spacer(minLength: 72) }
                    Text(message.text)
                        .font(.body).foregroundStyle(message.outgoing ? Color.white : Color.primary)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(message.outgoing ? Color.blue : Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("demo.message.\(message.id)")
                    if !message.outgoing { Spacer(minLength: 72) }
                }
                .padding(.horizontal, 16)
            } composer: {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5).focused($composing)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("demo.composer")
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        messages.append(.init(id: UUID(), text: text, outgoing: true))
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up").font(.headline.bold())
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.blue, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message").accessibilityIdentifier("demo.send")
                    if composing {
                        Button { composing = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down").frame(width: 32, height: 40)
                        }.accessibilityLabel("Dismiss keyboard").accessibilityIdentifier("demo.dismissKeyboard")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                .background(Color(uiColor: .systemBackground))
            }
            .nativeKeyboardLayout()
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $settingsPresented) {
            MotionSettingsView(configuration: $configuration)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}

#Preview { DemoChatView() }
