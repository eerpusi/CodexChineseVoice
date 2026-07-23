public enum APIKeyPresentation {
    public static func maskedValue(isConfigured: Bool) -> String? {
        isConfigured ? "********" : nil
    }
}
