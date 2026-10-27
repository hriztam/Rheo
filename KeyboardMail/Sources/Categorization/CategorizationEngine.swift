import Foundation

/// Smart email categorization engine.
///
/// Runs when new emails are synced from Gmail. Inspects headers and sender
/// domains to classify each message into one of four categories:
/// `.important`, `.newsletters`, `.promotions`, or `.spam`.
struct CategorizationEngine {

    /// Common newsletter / marketing sender domains.
    private static let newsletterDomains: Set<String> = [
        "mailchi.mp", "substack.com", "revue.cc", "buttondown.email",
        "convertkit.com", "mailerlite.com", "mailchimp.com",
        "constantcontact.com", "aweber.com", "getdrip.com",
        "medium.com", "ghost.io", "tinyletter.com"
    ]

    /// Common promotional / marketing domains.
    private static let promotionDomains: Set<String> = [
        "amazon.com", "amazon.co.uk", "ebay.com", "etsy.com",
        "target.com", "walmart.com", "bestbuy.com", "nike.com",
        "adidas.com", "sephora.com", "ulta.com", "aliexpress.com"
    ]

    /// Categorize a freshly-fetched Gmail message before inserting into the local DB.
    static func categorize(
        message: GmailMessage,
        hasSpamLabel: Bool
    ) -> EmailCategory {
        // Spam takes precedence.
        if hasSpamLabel {
            return .spam
        }

        let listUnsubscribe = message.header("List-Unsubscribe") ?? ""
        let precedence = message.header("Precedence") ?? ""
        let senderEmail = (message.senderEmail ?? "").lowercased()
        let senderDomain = senderEmail.components(separatedBy: "@").last ?? ""

        // Newsletter signals: List-Unsubscribe header, Precedence: bulk,
        // or known newsletter sender domain.
        if !listUnsubscribe.isEmpty
            || precedence.lowercased().contains("bulk")
            || newsletterDomains.contains(senderDomain) {
            return .newsletters
        }

        // Promotional signals: known promo domains or subject keywords.
        if promotionDomains.contains(senderDomain) {
            return .promotions
        }
        let subject = message.header("Subject") ?? ""
        if isPromotional(subject: subject) {
            return .promotions
        }

        return .important
    }

    private static func isPromotional(subject: String) -> Bool {
        let lowercased = subject.lowercased()
        let keywords = ["sale", "discount", "promo", "offer", "deal", "coupon",
                        "limited time", "free shipping", "new arrival", "clearance"]
        return keywords.contains { lowercased.contains($0) }
    }
}
