import CoreGraphics

extension CodexHotkeyMonitor {
    public static func matchesCommandR(
        bundleIdentifier: String?,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) -> Bool {
        guard bundleIdentifier == codexBundleIdentifier,
              keyCode == commandRKeyCode,
              !isAutoRepeat,
              flags.contains(.maskCommand) else {
            return false
        }

        let disallowed = CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue
        return flags.rawValue & disallowed == 0
    }
}
