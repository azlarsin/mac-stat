// Build with: swiftc -parse-as-library Tests/LocalizationTests.swift -o /tmp/macstat-localization-tests
// Run from the repository root with the built MacStat.app and arm64 stringsdata directory as arguments.
import Foundation

@main
enum LocalizationTests {
    static func main() throws {
        precondition(CommandLine.arguments.count == 3, "Pass MacStat.app and the stringsdata directory")
        let app = Bundle(path: CommandLine.arguments[1])!
        let catalogData = try Data(contentsOf: URL(fileURLWithPath: "MacStat/MacStat/Localizable.xcstrings"))
        let catalog = try JSONSerialization.jsonObject(with: catalogData) as! [String: Any]
        let strings = catalog["strings"] as! [String: [String: Any]]
        let languages = ["en", "zh-Hans", "zh-Hant"]
        precondition(Set(app.localizations) == Set(languages))

        var checked = 0
        for language in languages {
            let localized = Bundle(url: app.url(forResource: language, withExtension: "lproj")!)!
            for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
                let translations = entry["localizations"] as! [String: [String: Any]]
                let unit = translations[language]!["stringUnit"] as! [String: String]
                precondition(unit["state"] == "translated")
                let expected = unit["value"]!
                precondition(localized.localizedString(forKey: key, value: nil, table: nil) == expected,
                             "Missing or incorrect bundled translation: \(language) / \(key)")
                precondition(placeholders(key) == placeholders(expected),
                             "Changed format placeholders: \(language) / \(key)")
                checked += 1
            }
            let version = localized.localizedString(forKey: "Version %@ (%@)", value: nil, table: nil)
            precondition(String(format: version, "1.6", "1").contains("1.6 (1)"))
            let fan = localized.localizedString(forKey: "Fan %lld %%", value: nil, table: nil)
            precondition(String(format: fan, Int64(2)).hasSuffix("2 %"))
        }

        for (preference, expected) in [("en-GB", "en"), ("zh-CN", "zh-Hans"),
                                       ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("fr", "en")] {
            let selected = Bundle.preferredLocalizations(from: app.localizations, forPreferences: [preference])
            precondition(selected.first == expected, "Incorrect fallback for \(preference): \(selected)")
        }

        let extractionDir = URL(fileURLWithPath: CommandLine.arguments[2])
        var extractedKeys = Set<String>()
        for file in try FileManager.default.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)
            where file.pathExtension == "stringsdata" {
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let tables = data["tables"] as? [String: [[String: Any]]] ?? [:]
            for entry in tables["Localizable"] ?? [] {
                extractedKeys.insert(entry["key"] as! String)
            }
        }
        precondition(!extractedKeys.isEmpty)
        precondition(extractedKeys.isSubset(of: Set(strings.keys)),
                     "Untranslated extracted strings: \(extractedKeys.subtracting(strings.keys))")

        // Enum labels and section titles reach SwiftUI through dynamic keys,
        // so the compiler cannot extract them. Check their coverage separately.
        let settings = try String(contentsOfFile: "MacStat/MacStat/SettingsView.swift", encoding: .utf8)
        let blocks = try NSRegularExpression(pattern: #"var (?:label|sectionTitle): String \{.*?\n    \}"#,
                                             options: .dotMatchesLineSeparators)
        let returns = try NSRegularExpression(pattern: #"return "([^"]+)""#)
        let nsSettings = settings as NSString
        for block in blocks.matches(in: settings, range: NSRange(location: 0, length: nsSettings.length)) {
            let text = nsSettings.substring(with: block.range)
            let nsText = text as NSString
            for match in returns.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let key = nsText.substring(with: match.range(at: 1))
                precondition(strings[key] != nil, "Untranslated dynamic label: \(key)")
            }
        }
        print("Passed: \(checked) bundled translations, placeholders, regional fallback, \(extractedKeys.count) extracted keys, dynamic labels")
    }

    private static func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:[0-9]+\$)?(?:lld|ld|@|d|u|f|%)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range) }.sorted()
    }
}
