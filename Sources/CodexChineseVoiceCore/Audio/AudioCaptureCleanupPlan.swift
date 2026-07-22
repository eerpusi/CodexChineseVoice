struct AudioCaptureCleanupPlan: Sendable {
    let shouldRemoveTap: Bool
    let shouldStopEngine: Bool

    init(active: Bool, tapInstalled: Bool, hasConverter: Bool) {
        shouldRemoveTap = tapInstalled
        shouldStopEngine = tapInstalled || hasConverter
    }
}
