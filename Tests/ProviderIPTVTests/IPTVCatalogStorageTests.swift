import CoreModels
import Foundation
import SQLite3
import XCTest
@testable import ProviderIPTV

final class IPTVCatalogStorageTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32)

    private func location() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("catalog.sqlite")
    }

    private func importRows(_ count: Int, into catalog: IPTVCatalog) throws {
        try catalog.beginImport()
        defer { catalog.discardImport() }
        for index in 0..<count {
            try catalog.insert(IPTVRecord(item: .init(
                id: "movie-\(index)", title: String(repeating: "x", count: 1_000),
                kind: .movie, libraryID: "movies"
            )), into: .incoming)
        }
        try catalog.commitImport(library: nil, scope: "playlist")
    }

    private func walBytes(_ url: URL) throws -> Int {
        try URL(fileURLWithPath: url.path + "-wal").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    func testRepeatedImportsBoundTheRetainedJournalWithoutLosingRows() throws {
        let url = try location()
        let catalog = try IPTVCatalog(url: url, key: key)
        for count in [2_000, 2_000, 10, 2_000] {
            try importRows(count, into: catalog)
            XCTAssertLessThanOrEqual(try walBytes(url), IPTVCatalog.maximumRetainedJournalBytes)
            XCTAssertEqual(try catalog.count(where: "1 = 1"), count)
            XCTAssertEqual(try catalog.record("movie-0").item.title.count, 1_000)
        }
        let reopened = try IPTVCatalog(url: url, key: key)
        XCTAssertEqual(try reopened.count(where: "1 = 1"), 2_000)
        XCTAssertEqual(try reopened.record("movie-1999").item.title.count, 1_000)
    }

    func testPinnedReaderDefersReclamationWithoutBlockingOrInvalidatingItsSnapshot() throws {
        let url = try location()
        let catalog = try IPTVCatalog(url: url, key: key)
        try importRows(1, into: catalog)
        var reader: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let db = try XCTUnwrap(reader)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "BEGIN; SELECT * FROM entries", nil, nil, nil), SQLITE_OK)
        try importRows(2_000, into: catalog)
        XCTAssertGreaterThan(try walBytes(url), IPTVCatalog.maximumRetainedJournalBytes)
        let start = ContinuousClock.now
        catalog.reclaimJournal()
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM entries", -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        XCTAssertEqual(try catalog.count(where: "1 = 1"), 2_000)
        XCTAssertEqual(sqlite3_exec(db, "COMMIT", nil, nil, nil), SQLITE_OK)
        catalog.reclaimJournal()
        XCTAssertLessThanOrEqual(try walBytes(url), IPTVCatalog.maximumRetainedJournalBytes)
        XCTAssertEqual(try catalog.record("movie-1999").item.title.count, 1_000)
    }

    func testOpeningLegacyOversizedJournalCanReclaimItWithoutRedownloading() throws {
        let url = try location()
        let legacy = try IPTVCatalog(url: url, key: key)
        try legacy.execute("PRAGMA wal_autocheckpoint=0; PRAGMA journal_size_limit=-1; BEGIN IMMEDIATE")
        for index in 0..<2_000 {
            try legacy.insert(IPTVRecord(item: .init(
                id: "movie-\(index)", title: String(repeating: "x", count: 1_000), kind: .movie
            )))
        }
        try legacy.execute("COMMIT")
        XCTAssertGreaterThan(try walBytes(url), IPTVCatalog.maximumRetainedJournalBytes)
        let opened = try IPTVCatalog(url: url, key: key)
        opened.reclaimJournal()
        XCTAssertLessThanOrEqual(try walBytes(url), IPTVCatalog.maximumRetainedJournalBytes)
        XCTAssertEqual(try opened.record("movie-1999").item.title.count, 1_000)
    }
}
