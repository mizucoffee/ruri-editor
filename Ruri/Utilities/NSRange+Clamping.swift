//
//  NSRange+Clamping.swift
//  ruri
//

import Foundation

extension NSRange {
    /// Clamps the range into `0...length` in UTF-16 units. A range whose
    /// location is `NSNotFound` collapses to an empty range at the end.
    nonisolated func clamped(toUTF16Length length: Int) -> NSRange {
        guard location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }
        let clampedLocation = min(max(0, location), length)
        let maximumLength = max(0, length - clampedLocation)
        return NSRange(location: clampedLocation, length: min(max(0, self.length), maximumLength))
    }
}
