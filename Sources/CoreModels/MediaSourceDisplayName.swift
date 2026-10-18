import Foundation

/// Display-only names from provider labels, file paths, or streaming locators.
/// Never use the result to construct a playback URL or provider identity.
public enum MediaSourceDisplayName {
    public static func name(from rawValue: String?) -> String? {
        guard let value = nonempty(rawValue) else { return nil }
        let isQueryOnly = value.lowercased().hasPrefix("torrent_name=")
        guard isQueryOnly || value.contains("?") || value.contains("://")
                || value.hasPrefix("//") || value.hasPrefix("file:") else { return value }
        // Raw line breaks make Foundation re-escape existing percent sequences.
        // Remove display wrapping before decoding, never decode the result twice.
        let locator = value.components(separatedBy: .newlines).joined()
        guard let components = URLComponents(string: isQueryOnly ? "?" + locator : locator) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        if let torrentName = queryItems.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("torrent_name") == .orderedSame
        }) {
            // URLComponents decodes the value once, retaining literal '+' and
            // encoded '&' characters instead of treating them as separators.
            guard let name = nonempty(torrentName.value), !name.contains("://") else { return nil }
            return basename(name)
        }
        let isLocator = components.host != nil || value.contains("://")
            || components.scheme == "file" || isQueryOnly
            || queryItems.contains { $0.value != nil }
        guard isLocator else { return value }
        guard let fileName = basename(components.path) else { return nil }
        // A query-bearing endpoint such as /stream is not a release filename.
        if components.query != nil, (fileName as NSString).pathExtension.isEmpty { return nil }
        return fileName
    }

    public static func fileName(from path: String?) -> String? {
        name(from: path).flatMap(basename)
    }

    private static func basename(_ value: String) -> String? {
        let path = value.replacingOccurrences(of: "\\", with: "/")
        guard let result = nonempty((path as NSString).lastPathComponent),
              result != "/", result != ".", result != ".." else { return nil }
        return result
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
