import UIKit
import UserNotifications

/// Builds a reusable image attachment so reminders render with a warm brand thumbnail instead of
/// bare text. Writes a bundled gouache asset to a Caches JPEG once and reuses it on every call.
///
/// Asset choice: `brand-medallion` (a centered laurel wreath — see `BrandArt.medallion` in
/// Design/Clinical.swift), not `brand-sprig`. `brand-sprig` is a corner-anchored botanical
/// cluster that bleeds from one corner of its 1024x1024 canvas — most of the frame is empty, so
/// at notification-thumbnail size (iOS crops/scales this to a small square) it would read as
/// mostly blank. The medallion is a symmetric, centered motif that stays legible that small and
/// its "milestone emblem" framing fits a routine-consistency reminder.
///
/// Fail-soft: returns nil if the asset or file write fails — callers schedule the reminder
/// without an attachment rather than dropping it.
enum NotificationArt {
    private static let attachmentIdentifier = "reminderArt"
    private static let cacheFileName = "reminder-art.jpg"

    static func attachment() -> UNNotificationAttachment? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let image = UIImage(named: "brand-medallion"),
                  let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            guard (try? data.write(to: url)) != nil else { return nil }
        }
        return try? UNNotificationAttachment(identifier: attachmentIdentifier, url: url, options: nil)
    }
}
