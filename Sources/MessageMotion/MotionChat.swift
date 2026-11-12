// SPDX-License-Identifier: MIT
#if canImport(UIKit)
import SwiftUI
import UIKit

/// A chat viewport with UIKit-owned scrolling/keyboard geometry and caller-owned SwiftUI content.
@MainActor
public struct MotionChat<Message: Identifiable & Equatable, Bubble: View, Composer: View>: UIViewControllerRepresentable
where Message.ID: Sendable {
    let messages: [Message]
    let isComposing: Bool
    let configuration: MotionConfiguration
    let layoutRevision: Int
    private let extraReduceMotion: Bool
    let outgoing: (Message) -> Bool
    let bubble: (Message) -> Bubble
    let composer: Composer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motionReduced: Bool { reduceMotion || extraReduceMotion }

    /// Increase layoutRevision when a custom bubble's geometry changes outside the message value.
    public init(messages: [Message], isComposing: Bool, configuration: MotionConfiguration = .messagesLike,
                layoutRevision: Int = 0, reduceMotion: Bool = false, isOutgoing: @escaping (Message) -> Bool,
                @ViewBuilder bubble: @escaping (Message) -> Bubble, @ViewBuilder composer: () -> Composer) {
        self.messages = messages
        self.isComposing = isComposing
        self.configuration = configuration
        self.layoutRevision = layoutRevision
        extraReduceMotion = reduceMotion
        outgoing = isOutgoing
        self.bubble = bubble
        self.composer = composer()
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        MotionTranscriptController(content: self, environment: context.environment, reduceMotion: motionReduced)
    }

    public func updateUIViewController(_ controller: UIViewController, context: Context) {
        (controller as? MotionTranscriptController<Message, Bubble, Composer>)?
            .update(content: self, environment: context.environment, reduceMotion: motionReduced)
    }

    public static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        (controller as? MotionTranscriptController<Message, Bubble, Composer>)?.stop()
    }

    /// Apply this to MotionChat so keyboardLayoutGuide is the single keyboard owner.
    public func nativeKeyboardLayout() -> some View { ignoresSafeArea(.keyboard) }
}

struct MotionHostedContent<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues
    var body: some View { content.environment(\.self, environment) }
}
#endif
