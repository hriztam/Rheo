import Foundation

public extension String {
    /// Decodes common HTML entities (&amp;, &#39;, &quot;, &lt;, &gt;, &nbsp;, numeric entities, etc.)
    /// into their plain text equivalent.
    var decodingHTMLEntities: String {
        guard self.contains("&") else { return self }
        
        // Fast path: replace the most frequent named & special entities directly
        var result = self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&rsquo;", with: "’")
            .replacingOccurrences(of: "&lsquo;", with: "‘")
            .replacingOccurrences(of: "&rdquo;", with: "”")
            .replacingOccurrences(of: "&ldquo;", with: "“")
            .replacingOccurrences(of: "&copy;", with: "©")
            .replacingOccurrences(of: "&reg;", with: "®")
            .replacingOccurrences(of: "&trade;", with: "™")
        
        // Also handle numeric entities (decimal &#123; and hex &#x1F600;) via regular expressions
        if result.contains("&#") {
            let pattern = "&#(x[0-9a-fA-F]+|[0-9]+);"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
                // Process in reverse so string indices don't shift
                for match in matches.reversed() {
                    guard let fullRange = Range(match.range, in: result),
                          let captureRange = Range(match.range(at: 1), in: result) else { continue }
                    let capture = String(result[captureRange])
                    let codePoint: UInt32?
                    if capture.lowercased().hasPrefix("x") {
                        let hexStr = String(capture.dropFirst())
                        codePoint = UInt32(hexStr, radix: 16)
                    } else {
                        codePoint = UInt32(capture, radix: 10)
                    }
                    if let codePoint = codePoint, let scalar = UnicodeScalar(codePoint) {
                        result.replaceSubrange(fullRange, with: String(Character(scalar)))
                    }
                }
            }
        }
        
        return result
    }
}
