import Foundation

/// Lemon Squeezy store details (dashboard: Settings → Stores, Products → Sticky Windows).
enum LicenseConfig {
    /// Settings → Stores: the numeric store ID. Keys from other stores are refused when this is set.
    static let storeID: Int? = 501260
    /// Products → Sticky Windows: the numeric product ID. Keys for other products are refused when this is set.
    static let productID: Int? = 1451168
    /// The product's checkout link (Share → Checkout link).
    static let checkoutURL = URL(string: "https://shirley.lemonsqueezy.com/checkout/buy/39e470b7-2a5a-48b6-90b3-b6e859ccbdce")!

    static let trialLength: TimeInterval = 14 * 24 * 3600
    /// How long a licensed copy keeps working without reaching the server.
    static let offlineGrace: TimeInterval = 30 * 24 * 3600
    /// How often a licensed copy re-validates in the background.
    static let revalidateInterval: TimeInterval = 24 * 3600
}
