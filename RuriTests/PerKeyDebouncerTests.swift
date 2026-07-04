//
//  PerKeyDebouncerTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class PerKeyDebouncerTests: XCTestCase {
    func testFiresActionAfterDelay() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fired: [String] = []

        debouncer.schedule(for: "key") { fired.append("action") }

        try await TestSupport.waitUntil("scheduled action fires") { fired == ["action"] }
    }

    func testCoalescesRapidSchedulesIntoLastAction() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fired: [String] = []

        debouncer.schedule(for: "key") { fired.append("first") }
        debouncer.schedule(for: "key") { fired.append("second") }
        debouncer.schedule(for: "key") { fired.append("third") }

        try await TestSupport.waitUntil("last action fires") { !fired.isEmpty }
        // A sentinel scheduled after the fire bounds the wait for stragglers:
        // any earlier action would have fired before the sentinel's delay ends.
        var sentinelFired = false
        debouncer.schedule(for: "sentinel") { sentinelFired = true }
        try await TestSupport.waitUntil("sentinel fires") { sentinelFired }

        XCTAssertEqual(fired, ["third"])
    }

    func testKeysDebounceIndependently() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fired: [String] = []

        debouncer.schedule(for: "a") { fired.append("a") }
        debouncer.schedule(for: "b") { fired.append("b") }

        try await TestSupport.waitUntil("both keys fire") { fired.count == 2 }
        XCTAssertEqual(Set(fired), Set(["a", "b"]))
    }

    func testActionCanRescheduleItsOwnKey() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fireCount = 0

        debouncer.schedule(for: "key") {
            fireCount += 1
            debouncer.schedule(for: "key") { fireCount += 1 }
        }

        try await TestSupport.waitUntil("rescheduled action fires") { fireCount == 2 }
    }

    func testCancelPreventsPendingAction() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fired: [String] = []

        debouncer.schedule(for: "cancelled") { fired.append("cancelled") }
        debouncer.cancel(for: "cancelled")

        var sentinelFired = false
        debouncer.schedule(for: "sentinel") { sentinelFired = true }
        try await TestSupport.waitUntil("sentinel fires") { sentinelFired }

        XCTAssertEqual(fired, [])
    }

    func testCancelAllPreventsAllPendingActions() async throws {
        let debouncer = PerKeyDebouncer<String>(delayNanoseconds: 20_000_000)
        var fired: [String] = []

        debouncer.schedule(for: "a") { fired.append("a") }
        debouncer.schedule(for: "b") { fired.append("b") }
        debouncer.cancelAll()

        var sentinelFired = false
        debouncer.schedule(for: "sentinel") { sentinelFired = true }
        try await TestSupport.waitUntil("sentinel fires") { sentinelFired }

        XCTAssertEqual(fired, [])
    }
}
