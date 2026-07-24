public enum APIKeyPresentation {
    public static func maskedValue(isConfigured: Bool) -> String? {
        isConfigured ? "********" : nil
    }

    public static func inputPrompt(isConfigured: Bool) -> String {
        maskedValue(isConfigured: isConfigured) ?? ""
    }
}
