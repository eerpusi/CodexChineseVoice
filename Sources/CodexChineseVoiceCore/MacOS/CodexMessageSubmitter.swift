import CoreGraphics

struct CodexMessageSubmitter {
    private let makeEvent: (_ keyDown: Bool) -> CGEvent?
    private let post: (CGEvent) -> Void

    init() {
        makeEvent = { keyDown in
            CGEvent(
                keyboardEventSource: nil,
                virtualKey: 36,
                keyDown: keyDown
            )
        }
        post = { event in
            event.post(tap: .cghidEventTap)
        }
    }

    init(
        makeEvent: @escaping (_ keyDown: Bool) -> CGEvent?,
        post: @escaping (CGEvent) -> Void
    ) {
        self.makeEvent = makeEvent
        self.post = post
    }

    func submit(validate: () throws -> Void = {}) throws {
        guard let keyDown = makeEvent(true),
              let keyUp = makeEvent(false) else {
            throw CodexInputBridgeError.autoSubmitUnavailable
        }
        keyDown.flags = []
        keyUp.flags = []
        try validate()
        post(keyDown)
        post(keyUp)
    }
}
