import Foundation

/// Lemon Squeezy store details. Fill these in from the Lemon Squeezy dashboard before shipping.
enum LicenseConfig {
    /// Settings → Stores: the numeric store ID. Keys from other stores are refused when this is set.
    static let storeID: Int? = nil
    /// Products → Ledge: the numeric product ID. Keys for other products are refused when this is set.
    static let productID: Int? = nil
    /// The product's checkout link (Share → Checkout link).
    static let checkoutURL = URL(string: "https://theshirleycompany.lemonsqueezy.com/checkout")!

    static let trialLength: TimeInterval = 14 * 24 * 3600
    /// How long a licensed copy keeps working without reaching the server.
    static let offlineGrace: TimeInterval = 30 * 24 * 3600
    /// How often a licensed copy re-validates in the background.
    static let revalidateInterval: TimeInterval = 24 * 3600
}
