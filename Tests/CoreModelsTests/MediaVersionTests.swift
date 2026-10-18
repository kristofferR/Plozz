import XCTest
@testable import CoreModels

/// Tests for the `MediaVersion` value type, its labels, device-compatibility
/// prediction, and the smart "recommended selection" used as the picker default.
final class MediaVersionTests: XCTestCase {

    // MARK: - Labels

    func testResolutionLabelBuckets() {
        XCTAssertEqual(MediaVersion(id: "1", height: 2160).resolutionLabel, "4K")
        XCTAssertEqual(MediaVersion(id: "2", height: 1440).resolutionLabel, "1440p")
        XCTAssertEqual(MediaVersion(id: "3", height: 1080).resolutionLabel, "1080p")
        XCTAssertEqual(MediaVersion(id: "4", height: 720).resolutionLabel, "720p")
        XCTAssertEqual(MediaVersion(id: "5", height: 480).resolutionLabel, "SD")
        XCTAssertNil(MediaVersion(id: "6").resolutionLabel)
    }

    func testHDRAndAudioLabels() {
        let doviAtmos = MediaVersion(
            id: "1", height: 2160, videoRange: "DOVI",
            audioChannels: 8, audioProfile: "Dolby Atmos"
        )
        XCTAssertTrue(doviAtmos.isHDR)
        XCTAssertEqual(doviAtmos.hdrLabel, "Dolby Vision")
        XCTAssertEqual(doviAtmos.audioLabel, "Atmos")

        let sdr51 = MediaVersion(id: "2", height: 1080, videoRange: "SDR", audioChannels: 6)
        XCTAssertFalse(sdr51.isHDR)
        XCTAssertNil(sdr51.hdrLabel)
        XCTAssertEqual(sdr51.audioLabel, "5.1")

        let hdr10Plus = MediaVersion(id: "3", height: 2160, videoRange: "HDR10Plus")
        XCTAssertTrue(hdr10Plus.isHDR)
        XCTAssertEqual(hdr10Plus.hdrLabel, "HDR10+")
        XCTAssertTrue(hdr10Plus.displayLabel?.contains("HDR10+") == true)
        XCTAssertEqual(hdr10Plus.technicalBadges.map(\.label), ["4K", "HDR10+"])
    }

    func testHDR10PlusVersionRetainsItsHDR10CompatibleDirectPlay() {
        let version = MediaVersion(id: "hdr", videoCodec: "hevc", videoRange: "HDR10Plus", audioCodec: "aac")
        XCTAssertEqual(version.compatibility(with: .init(supportsHDR10: true)), .directPlay)
        XCTAssertEqual(version.compatibility(with: .init(supportsHDR10: false)), .transcode)
    }

    func testTechnicalBadgesUseDolbyGroupedOrder() {
        // A 4K DoVi+HDR10 Atmos version should emit
        // 4K · Dolby Vision · Dolby Atmos · HDR10 — Dolby logos grouped.
        let dovi = MediaVersion(
            id: "1",
            width: 3840,
            height: 2160,
            videoCodec: "hevc",
            videoRange: "DOVIWithHDR10",
            audioCodec: "eac3",
            audioChannels: 8,
            audioProfile: "Dolby Atmos"
        )
        XCTAssertEqual(dovi.technicalBadges.map(\.label),
                       ["4K", "Dolby Vision", "Dolby Atmos", "HDR10"])

        // A 720p SDR stereo version should emit just 720p · SDR — no audio
        // headline, no HDR badges, and channels < 6 are not surfaced.
        let sd = MediaVersion(
            id: "2",
            width: 1280,
            height: 720,
            videoCodec: "h264",
            videoRange: "SDR",
            audioCodec: "aac",
            audioChannels: 2
        )
        XCTAssertEqual(sd.technicalBadges.map(\.label), ["720p", "SDR"])

        // A 1080p HDR10 5.1 Dolby Digital+ version: resolution, HDR10 (not
        // Dolby-styled), then Dolby Digital+ (Dolby-styled) — verifying the
        // Dolby-grouping helper picks the audio-Dolby out of the trailing
        // group when there's no Dolby-styled range.
        let dd = MediaVersion(
            id: "3",
            width: 1920,
            height: 1080,
            videoCodec: "hevc",
            videoRange: "HDR10",
            audioCodec: "eac3",
            audioChannels: 6
        )
        let labels = dd.technicalBadges.map(\.label)
        XCTAssertEqual(labels.first, "1080p")
        // Dolby Digital+ (Dolby-styled audio) comes before HDR10 (non-Dolby range).
        XCTAssertEqual(labels.dropFirst().prefix(2), ArraySlice(["Dolby Digital+", "HDR10"]))
    }

    func testDisplayLabelPrefersDerivedFactsThenName() {
        let derived = MediaVersion(id: "1", height: 2160, sizeBytes: 12_000_000_000, videoRange: "HDR10")
        XCTAssertTrue(derived.displayLabel?.contains("4K") == true)
        XCTAssertTrue(derived.displayLabel?.contains("HDR10") == true)
        XCTAssertTrue(derived.displayLabel?.contains("12 GB") == true)

        // A name that names a source-quality token now surfaces that token (the
        // edition/source recovery the picker needs) rather than echoing the raw
        // release string verbatim.
        XCTAssertEqual(MediaVersion(id: "2", name: "Bluray Remux").displayLabel, "Remux")
        // A name with no recognised edition/source/quality still falls back whole.
        XCTAssertEqual(MediaVersion(id: "2b", name: "Server Copy").displayLabel, "Server Copy")

        // No facts and no name: displayLabel is nil — the caller supplies its
        // own "Version" copy fallback rather than us baking English in here.
        XCTAssertNil(MediaVersion(id: "3").displayLabel)
    }

    func testRichMenuFactsKeepFileNameSeparate() {
        let version = MediaVersion(
            id: "1",
            name: "Extended Remux",
            fileName: "Movie.Extended.2160p.mkv",
            height: 2160,
            bitrate: 80_000_000,
            sizeBytes: 42_000_000_000,
            duration: 7_200,
            videoRange: "DOVI",
            audioChannels: 8,
            audioProfile: "Dolby Atmos"
        )

        XCTAssertEqual(version.menuTitle, "Extended")
        XCTAssertEqual(
            version.menuFacts,
            ["4K", "Dolby Vision", "Remux", "Atmos", "80 Mbps", "42 GB", "2h"]
        )
        XCTAssertEqual(version.fileName, "Movie.Extended.2160p.mkv")
    }

    func testSynthesizedVersionCarriesSourceFileSize() {
        let item = MediaItem(
            id: "movie",
            title: "Movie",
            kind: .movie,
            mediaInfo: MediaSourceMetadata(fileSizeBytes: 8_500_000_000)
        )

        let version = MediaVersion.synthesized(from: item)
        XCTAssertEqual(version.sizeBytes, 8_500_000_000)
        XCTAssertEqual(version.sizeLabel, "8.5 GB")
    }

    func testPickerPresentationIncludesSourceAudioLanguagesFormatsAndRelease() {
        let version = MediaVersion(
            id: "file", name: "Extended Remux", fileName: "Film.Extended.2160p.REMUX-GROUP.mkv",
            height: 2160, bitrate: 80_000_000, sizeBytes: 42_000_000_000, duration: 7_200,
            sourceMetadata: .init(
                video: .init(codec: "hevc", width: 3840, height: 2160, bitDepth: 10, videoRangeType: "DOVIWithHDR10"),
                audio: .init(codec: "truehd", profile: "Atmos", channels: 8, language: "eng"),
                audioLanguages: ["eng", "en", "fra", "und", ""]
            )
        )
        let row = MediaVersion.PickerPresentation(version, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(row.title, "Extended · 4K · Dolby Vision · Remux · 42 GB")
        XCTAssertEqual(row.supplementalFacts, [
            "HDR10", "HEVC", "10-bit", "English, French", "Dolby TrueHD + Dolby Atmos", "80 Mbps", "2h"
        ])
        XCTAssertEqual(row.releaseName, "Film.Extended.2160p.REMUX-GROUP.mkv")
        XCTAssertEqual(
            version.audioLanguageNames(in: Locale(identifier: "es_ES")),
            ["Inglés", "Francés"]
        )
    }

    func testPickerAudioKeepsCodecProfileAndChannelsWithoutGuessingMissingFacts() {
        XCTAssertEqual(MediaVersion(id: "a", audioCodec: "aac", audioChannels: 2).audioFormatLabel, "AAC Stereo")
        XCTAssertEqual(
            MediaVersion(id: "b", audioCodec: "dts", audioChannels: 8, audioProfile: "DTS-HD MA").audioFormatLabel,
            "DTS-HD MA 7.1"
        )
        XCTAssertEqual(
            MediaVersion(id: "c", audioCodec: "truehd", audioChannels: 6).audioFormatLabel,
            "Dolby TrueHD 5.1"
        )
        XCTAssertEqual(MediaVersion(id: "d", audioCodec: "aac").audioFormatLabel, "AAC")
        XCTAssertNil(MediaVersion(id: "e").audioFormatLabel)
        let unknown = MediaVersion.PickerPresentation(.init(id: "unknown", sizeBytes: -1, duration: 0))
        XCTAssertNil(unknown.title)
        XCTAssertTrue(unknown.supplementalFacts.isEmpty)
        XCTAssertNil(unknown.releaseName)
        XCTAssertNil(MediaVersion(id: "invalid", duration: .infinity).durationLabel)
        XCTAssertNil(MediaVersion(id: "invalid", duration: .nan).durationLabel)
    }

    func testPickerReleaseFallbackAndFilenameQualityDoNotChangeVersionIdentity() {
        let original = MediaVersion(id: "raw", fileName: "Movie.2160p.WEB-DL-GROUP.mkv", height: 2160)
        let qualified = original.qualified(accountID: "account", itemID: "item")
        let row = MediaVersion.PickerPresentation(qualified)
        XCTAssertEqual(row.title, "4K")
        XCTAssertEqual(row.supplementalFacts, ["WEB-DL"])
        XCTAssertEqual(row.releaseName, original.fileName)
        XCTAssertEqual(qualified.playbackMediaSourceID, "raw")
        XCTAssertNotEqual(qualified.id, "raw")
        XCTAssertEqual(MediaVersion.PickerPresentation(.init(id: "a", name: "Release", height: 1080)).releaseName, "Release")
        XCTAssertNil(MediaVersion.PickerPresentation(.init(id: "b", name: "Server Copy")).releaseName)
    }

    func testCachedMetadataAndSynthesizedVersionsPreserveLanguageFacts() throws {
        let legacy = try JSONDecoder().decode(
            MediaSourceMetadata.self, from: Data(#"{"audio":{"codec":"aac","language":"eng"}}"#.utf8)
        )
        XCTAssertNil(legacy.audioLanguages)
        let metadata = MediaSourceMetadata(
            fileName: "Movie.mkv", audio: legacy.audio, audioLanguages: ["eng", "jpn"]
        )
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, mediaInfo: metadata)
        let version = MediaVersion.synthesized(from: item)
        let restored = try JSONDecoder().decode(MediaVersion.self, from: JSONEncoder().encode(version))
        XCTAssertEqual(restored, version)
        XCTAssertEqual(restored.audioLanguageNames(in: Locale(identifier: "en_US")), ["English", "Japanese"])
        XCTAssertEqual(MediaVersion.PickerPresentation(restored).releaseName, "Movie.mkv")
        XCTAssertNil(restored.playbackMediaSourceID)
        XCTAssertEqual(
            MediaVersion(id: "legacy", sourceMetadata: legacy).audioLanguageNames(in: Locale(identifier: "en_US")),
            ["English"]
        )
    }

    func testPortsydeTorrentNamesAreDecodedWithoutChangingStoredSourceOrIdentity() throws {
        let query = "torrent_name=Film%20%26%20Friends.Extended.2160p.REMUX-GROUP.mkv&id=tt123&media_type=movie"
        for rawName in [
            "https://media.example/stream?\(query)",
            "n?\n\(query)",
            query
        ] {
            let version = MediaVersion(
                id: "raw-source", fileName: rawName, height: 2160,
                sourceMetadata: .init(fileName: rawName)
            ).qualified(accountID: "account", itemID: "item")
            let cached = try JSONDecoder().decode(MediaVersion.self, from: JSONEncoder().encode(version))
            let row = MediaVersion.PickerPresentation(cached)
            XCTAssertEqual(row.title, "Extended · 4K")
            XCTAssertEqual(row.supplementalFacts, ["Remux"])
            XCTAssertEqual(row.releaseName, "Film & Friends.Extended.2160p.REMUX-GROUP.mkv")
            XCTAssertEqual(cached.fileName, rawName)
            XCTAssertEqual(cached.sourceMetadata?.fileName, rawName)
            XCTAssertEqual(cached.playbackMediaSourceID, "raw-source")
            XCTAssertEqual(cached.id, version.id)
            XCTAssertTrue(cached.audioLanguageNames().isEmpty)
            XCTAssertNil(cached.audioFormatLabel)
        }
    }

    func testURLBackedProviderNameCannotLeakQueryTextIntoPickerTitles() {
        let version = MediaVersion(
            id: "source", name: "https://media.example/stream?torrent_name=Release%20Name&id=tt123"
        )
        XCTAssertEqual(version.displayLabel, "Release Name")
        XCTAssertEqual(version.menuTitle, "Release Name")
        XCTAssertNil(MediaVersion.PickerPresentation(version).releaseName)

        let endpoint = MediaVersion(
            id: "endpoint",
            name: "https://media.example/stream?token=Extended.REMUX",
            fileName: "stream?token=Extended.REMUX"
        )
        let row = MediaVersion.PickerPresentation(endpoint)
        XCTAssertNil(row.title)
        XCTAssertTrue(row.supplementalFacts.isEmpty)
        XCTAssertNil(row.releaseName)
    }

    func testSourceDisplayNamesDecodeOnlyURLValuesAndPreserveOrdinaryNames() {
        let cases: [(String, String?)] = [
            ("torrent_name=%E6%8C%87%E7%8E%AF%E7%8E%8B.mkv&id=tt123", "指环王.mkv"),
            ("torrent_name=Film%20%26%20Friends%2BPlus.mkv&id=tt123", "Film & Friends+Plus.mkv"),
            ("torrent_name=Film+Plus.mkv&id=tt123", "Film+Plus.mkv"),
            ("torrent_name=Film%2520Name.mkv&id=tt123", "Film%20Name.mkv"),
            ("https://media.example/Film%20Name.mkv?token=fixture#fragment", "Film Name.mkv"),
            ("Film.mkv?token=fixture#fragment", "Film.mkv"),
            ("/movies/Film%20Name.mkv", "Film%20Name.mkv"),
            (#"C:\Movies\Film.mkv"#, "Film.mkv"),
            ("Film & Friends+Plus.mkv", "Film & Friends+Plus.mkv"),
            ("https://media.example/stream?torrent_name=&id=tt123", nil),
            ("torrent_name=%E6%8C&id=tt123", nil),
            ("https://media.example/stream?token=fixture", nil),
            ("?token=fixture", nil),
            ("torrent_name=https%3A%2F%2Fmedia.example%2Fstream%3Ftoken%3Dfixture", nil)
        ]
        for (input, expected) in cases {
            XCTAssertEqual(MediaSourceDisplayName.fileName(from: input), expected, input)
        }
        XCTAssertEqual(MediaSourceDisplayName.name(from: "Theatrical / Original"), "Theatrical / Original")
        let fallback = MediaVersion.PickerPresentation(.init(
            id: "fallback", name: "Server copy", fileName: "stream?token=fixture", height: 1080
        ))
        XCTAssertEqual(fallback.releaseName, "Server copy")
    }

    func testFileSizeUsesAtMostOneFractionDigit() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            MediaFileSizeFormatter.string(
                fromByteCount: 65_270_000_000,
                locale: locale
            ),
            "65.3 GB"
        )
        XCTAssertEqual(
            MediaFileSizeFormatter.string(
                fromByteCount: 682_600_000,
                locale: locale
            ),
            "682.6 MB"
        )
        XCTAssertEqual(
            MediaFileSizeFormatter.string(
                fromByteCount: 12_000_000_000,
                locale: locale
            ),
            "12 GB"
        )
    }

    func testQualityScoreRanksHDRAndResolution() {
        let uhdHDR = MediaVersion(id: "1", height: 2160, videoRange: "HDR10")
        let uhdSDR = MediaVersion(id: "2", height: 2160, videoRange: "SDR")
        let hd = MediaVersion(id: "3", height: 1080, videoRange: "SDR")
        XCTAssertGreaterThan(uhdHDR.qualityScore, uhdSDR.qualityScore)
        XCTAssertGreaterThan(uhdSDR.qualityScore, hd.qualityScore)
    }

    // MARK: - Compatibility prediction

    func testCompatibilityUnknownWithoutCodec() {
        let v = MediaVersion(id: "1", height: 1080)
        XCTAssertEqual(v.compatibility(with: .default), .unknown)
    }

    func testCompatibilityDirectPlayForSupportedH264AAC() {
        // h264 + SDR + AAC is universally decodable on any Apple TV 4K.
        let v = MediaVersion(id: "1", height: 1080, videoCodec: "h264", videoRange: "SDR", audioCodec: "aac")
        XCTAssertEqual(v.compatibility(with: .default), .directPlay)
    }

    func testCompatibilityTranscodeWhenHDRUnsupported() {
        // Dolby Vision falls outside the default native profile. The provider or
        // Plozzigen may still handle it without a server transcode.
        let dovi = MediaVersion(id: "1", height: 2160, videoCodec: "hevc", videoRange: "DOVI", audioCodec: "aac")
        XCTAssertEqual(dovi.compatibility(with: .default), .transcode)

        let doviCapable = MediaCapabilities(supportsDolbyVision: true)
        XCTAssertEqual(dovi.compatibility(with: doviCapable), .directPlay)
    }

    func testCompatibilityTranscodeWhenVideoCodecUnsupported() {
        let av1 = MediaVersion(id: "1", height: 2160, videoCodec: "av1", videoRange: "SDR", audioCodec: "aac")
        XCTAssertEqual(av1.compatibility(with: .default), .transcode) // default native profile has no AV1
        XCTAssertEqual(av1.compatibility(with: MediaCapabilities(supportsAV1: true)), .directPlay)
    }

    func testCompatibilityTranscodeForDTSWithoutPassthrough() {
        let dts = MediaVersion(id: "1", height: 1080, videoCodec: "h264", videoRange: "SDR", audioCodec: "dts")
        XCTAssertEqual(dts.compatibility(with: .default), .transcode)
        XCTAssertEqual(dts.compatibility(with: MediaCapabilities(supportsDTSPassthrough: true)), .directPlay)
    }

    // MARK: - Recommended selection (smart default)

    func testRecommendedSelectionPicksBestDirectPlayable() {
        // On a default (non-DoVi) profile, the conservative recommended default is
        // the highest-quality known-native version — the 1080p.
        let versions = [
            MediaVersion(id: "4k", height: 2160, isDefault: true, videoCodec: "hevc", videoRange: "DOVI", audioCodec: "aac"),
            MediaVersion(id: "1080", height: 1080, videoCodec: "h264", videoRange: "SDR", audioCodec: "aac")
        ]
        XCTAssertEqual(versions.recommendedSelection(for: .default)?.id, "1080")
    }

    func testRecommendedSelectionPrefersDirectPlayUHDWhenCapable() {
        // A DoVi-capable device direct-plays the 4K, so it wins.
        let versions = [
            MediaVersion(id: "4k", height: 2160, videoCodec: "hevc", videoRange: "DOVI", audioCodec: "aac"),
            MediaVersion(id: "1080", height: 1080, videoCodec: "h264", videoRange: "SDR", audioCodec: "aac")
        ]
        XCTAssertEqual(versions.recommendedSelection(for: MediaCapabilities(supportsDolbyVision: true))?.id, "4k")
    }

    func testRecommendedSelectionFallsBackToServerDefaultWhenNoneDirectPlay() {
        // Device can't HEVC-decode anything offered → fall back to server default.
        let caps = MediaCapabilities(supportsHEVC: false)
        let versions = [
            MediaVersion(id: "a", height: 2160, videoCodec: "hevc", videoRange: "SDR", audioCodec: "aac"),
            MediaVersion(id: "b", height: 2160, isDefault: true, videoCodec: "hevc", videoRange: "SDR", audioCodec: "aac")
        ]
        XCTAssertEqual(versions.recommendedSelection(for: caps)?.id, "b")
    }

    func testRecommendedSelectionEmptyIsNil() {
        XCTAssertNil([MediaVersion]().recommendedSelection(for: .default))
    }

    func testPickerOrderSortsKnownSizesLargestFirstAndUnknownLast() {
        let versions = [
            MediaVersion(id: "small", height: 2160, sizeBytes: 5_510_000_000),
            MediaVersion(id: "unknown", height: 4320),
            MediaVersion(id: "largest", height: 2160, sizeBytes: 65_270_000_000),
            MediaVersion(id: "medium", height: 480, sizeBytes: 11_410_000_000)
        ]

        XCTAssertEqual(
            versions.sortedForPicker().map(\.id),
            ["largest", "medium", "small", "unknown"]
        )
    }
}
