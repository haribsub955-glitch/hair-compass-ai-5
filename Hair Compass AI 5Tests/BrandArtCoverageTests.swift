//
//  BrandArtCoverageTests.swift
//  Hair Compass AI 5Tests
//
//  Keeps the brand-art catalog and the UI that renders it from drifting apart.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

/// The whole `BrandArt` catalog once drifted out of the interface without anything noticing.
/// Six plates — the Trends header art, the Plan and Photos narrative illustrations, a Today hero,
/// a photos empty-state and the ritual comb — were declared as constants, described in comments
/// that named the exact screen they belonged to, and then rendered by no view at all. Nothing
/// failed: an unused `static let String` is perfectly valid Swift, and a missing illustration
/// looks like a design decision rather than a bug. Meanwhile 19 more imagesets from a superseded
/// art direction sat in the catalog at ~17 MB, referenced by nothing.
///
/// Both failure modes are invisible at runtime and to the compiler, so they get tests instead.
///
/// These read the *source tree* rather than the built bundle: `#filePath` is baked in at compile
/// time and the simulator shares the host filesystem, so the tests can see the repo the same way a
/// reviewer would. That is what lets them answer "is this constant referenced by a view?", which
/// no amount of runtime introspection could.
struct BrandArtCoverageTests {

    // MARK: Repo layout

    /// Repo root, derived from this file's own path (`<root>/Hair Compass AI 5Tests/<this file>`).
    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Hair Compass AI 5Tests
        .deletingLastPathComponent()   // repo root

    private static let appSources = repoRoot.appendingPathComponent("Hair Compass AI 5")
    private static let catalog = appSources.appendingPathComponent("Assets.xcassets")
    private static let clinicalSwift = appSources.appendingPathComponent("Design/Clinical.swift")

    /// Every `.swift` file in the app target, as (filename, contents).
    private static func appSwiftFiles() throws -> [(name: String, text: String)] {
        guard let walker = FileManager.default.enumerator(
            at: appSources,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    /// Clinical.swift split into the `BrandArt` declaration block and everything else.
    ///
    /// The split matters: `CornerSprig` and `StrandDivider` render `BrandArt.sprig` and
    /// `BrandArt.divider` from inside this same file, so treating all of Clinical.swift as "the
    /// declaration" would report two perfectly live constants as unused. Only the enum body is
    /// excluded from the consumer search; the rest of the file counts like any other view code.
    private static func clinicalSplit() throws -> (declaration: String, rest: String) {
        let source = try String(contentsOf: clinicalSwift, encoding: .utf8)

        guard
            let enumStart = source.range(of: "enum BrandArt {"),
            // The catalog is a flat list of `static let`s; the first `\n}` closes it.
            let enumEnd = source.range(of: "\n}", range: enumStart.upperBound..<source.endIndex)
        else {
            Issue.record("Could not locate the BrandArt enum in Clinical.swift — has it been renamed or moved?")
            return ("", source)
        }

        let declaration = String(source[enumStart.upperBound..<enumEnd.lowerBound])
        let rest = String(source[source.startIndex..<enumStart.lowerBound])
            + String(source[enumEnd.upperBound...])
        return (declaration, rest)
    }

    /// The asset names declared in `BrandArt`, scraped from the source so the test can never fall
    /// behind a constant someone adds later — the exact drift this file exists to prevent.
    private static func declaredArtNames() throws -> [(constant: String, asset: String)] {
        let body = try clinicalSplit().declaration
        var found: [(String, String)] = []

        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Comments legitimately mention retired names ("`hero-today` was retired…"), so only
            // real declarations count.
            guard line.hasPrefix("static let"),
                  let equals = line.firstIndex(of: "="),
                  let openQuote = line[equals...].firstIndex(of: "\""),
                  let closeQuote = line[line.index(after: openQuote)...].firstIndex(of: "\"")
            else { continue }

            let constant = line
                .replacingOccurrences(of: "static let", with: "")
                .prefix(while: { $0 != "=" })
                .trimmingCharacters(in: .whitespaces)
            let asset = String(line[line.index(after: openQuote)..<closeQuote])
            found.append((constant, asset))
        }
        return found
    }

    // MARK: Tests

    /// Catches a typo'd or deleted asset: the constant still compiles, and `Image("…")` silently
    /// renders nothing at runtime rather than failing.
    @Test func everyDeclaredArtNameExistsInTheCatalog() throws {
        let declared = try Self.declaredArtNames()
        #expect(!declared.isEmpty, "Scraped zero constants from BrandArt — the parser is broken, not the catalog.")

        for (constant, asset) in declared {
            let imageset = Self.catalog.appendingPathComponent("\(asset).imageset")
            #expect(
                FileManager.default.fileExists(atPath: imageset.path),
                "BrandArt.\(constant) points at \"\(asset)\", which has no imageset in Assets.xcassets."
            )
        }
    }

    /// The regression this file is named for: a constant that no view ever renders. Art that is
    /// declared but never shown is indistinguishable from art that was never commissioned.
    @Test func everyDeclaredArtNameIsRenderedBySomeView() throws {
        let declared = try Self.declaredArtNames()
        // Every app source except the enum body itself — including the rest of Clinical.swift,
        // where the shared art components live.
        var corpus = try Self.appSwiftFiles()
            .filter { $0.name != "Clinical.swift" }
            .map(\.text)
        corpus.append(try Self.clinicalSplit().rest)

        for (constant, asset) in declared {
            // Either `BrandArt.foo` (the normal path) or the raw literal, which a few models and
            // enums use to map a case onto its own art.
            let consumed = corpus.contains { text in
                text.contains("BrandArt.\(constant)") || text.contains("\"\(asset)\"")
            }
            #expect(
                consumed,
                """
                BrandArt.\(constant) (\"\(asset)\") is declared but rendered by no view.
                Either wire it into a screen or delete the constant and its imageset — \
                a catalog entry with no consumer is how the whole art library went missing before.
                """
            )
        }
    }

    /// The other direction: an imageset nothing can reach. These cost download size forever and
    /// are invisible in every code search, because there is no code to find.
    ///
    /// Art reached through a computed name is the one thing a literal search cannot see, so the
    /// known interpolations are listed explicitly rather than guessed at. `ClarityContrast`
    /// builds `"\(base)-male"`; if another screen starts composing names the same way, add it here
    /// and the test keeps telling the truth.
    @Test func noImagesetIsUnreachable() throws {
        let interpolated: Set<String> = [
            "clarity-with-male",     // ClarityContrast.artName(steady:)
            "clarity-without-male",
        ]
        let ignoredPrefixes = ["AppIcon", "AccentColor"]

        let entries = try FileManager.default.contentsOfDirectory(atPath: Self.catalog.path)
        let imagesets = entries
            .filter { $0.hasSuffix(".imageset") }
            .map { String($0.dropLast(".imageset".count)) }
            .filter { name in !ignoredPrefixes.contains { name.hasPrefix($0) } }

        #expect(!imagesets.isEmpty, "Found no imagesets — the catalog path is wrong, not the catalog.")

        let allSource = try Self.appSwiftFiles().map(\.text).joined()

        for asset in imagesets where !interpolated.contains(asset) {
            #expect(
                allSource.contains("\"\(asset)\""),
                """
                Imageset \"\(asset)\" is referenced by no Swift literal and is not a known \
                interpolated name. Delete it, or add it to `interpolated` if it is composed at runtime.
                """
            )
        }
    }

    /// Guards the deliberate retirements, so none comes back by reflex.
    ///
    /// `hero-today` was dropped because Today's hero is an edgeless elliptical glow built
    /// specifically so the screen would not break into sections — a banner behind it puts back the
    /// edge that change removed. `comb-tool` was dropped with the interaction it belonged to:
    /// `CombRitual` is an automatic smoothing pass now, so there is nothing to drag a comb across.
    /// `hero-photos-empty` was dropped on shape: a centered square composition cannot be cropped
    /// into a header band without landing its subject on the region-picker chips. `trends-journey-empty`
    /// was dropped when the Trends journey chart's two-log gate switched to the shared
    /// `ChartPlaceholder` pill every other locked chart uses — the bespoke illustration had no
    /// other user once that landed.
    @Test func retiredArtStaysRetired() throws {
        for retired in ["hero-today", "comb-tool", "hero-photos-empty", "trends-journey-empty"] {
            let imageset = Self.catalog.appendingPathComponent("\(retired).imageset")
            #expect(
                !FileManager.default.fileExists(atPath: imageset.path),
                "\(retired).imageset is back in the catalog. If it has a real home now, wire it up and delete this expectation."
            )
        }
    }
}
