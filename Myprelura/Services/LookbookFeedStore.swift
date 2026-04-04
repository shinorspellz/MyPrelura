//
//  LookbookFeedStore.swift
//  Prelura-swift
//
//  Shared store for lookbook uploads that appear in the Discover feed.
//

import Foundation

enum LookbookFeedStore {
    private static let defaults = UserDefaults.standard
    private static let feedKey = "lookbook_feed_records"

    /// Append an uploaded record to the feed (called from LookbooksUploadView after successful upload).
    static func append(_ record: LookbookUploadRecord) {
        var list = load()
        list.append(record)
        save(list)
    }

    /// All uploaded records to show in the lookbook feed, newest first.
    static func load() -> [LookbookUploadRecord] {
        guard let data = defaults.data(forKey: feedKey),
              let list = try? JSONDecoder().decode([LookbookUploadRecord].self, from: data) else { return [] }
        return list.reversed() // newest first
    }

    private static func save(_ list: [LookbookUploadRecord]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: feedKey)
    }
}
