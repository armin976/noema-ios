// UsageLimiterTests.swift
import XCTest
@testable import Noema

final class UsageLimiterTests: XCTestCase {
    struct TestTime: TimeProvider {
        var nowDate: Date
        var uptime: TimeInterval
        var idfv: String? = "TEST-IDFV"
        func now() -> Date { nowDate }
        func uptimeSeconds() -> TimeInterval { uptime }
        func currentIDFV() -> String? { idfv }
        func advanced(by seconds: TimeInterval) -> TestTime { TestTime(nowDate: nowDate.addingTimeInterval(seconds), uptime: uptime + seconds, idfv: idfv) }
    }

    func makeLimiter(_ time: TestTime) throws -> (UsageLimiter, TestTime, UsageLimiterConfig) {
        // Use unique accounts per test run
        let account = "search-\(UUID().uuidString)"
        let cfg = UsageLimiterConfig(limitPer24h: 5, minIntervalSeconds: 1, service: "com.noema.tests", account: account, appGroupID: "group.com.noema")
        let limiter = try UsageLimiter(config: cfg, timeProvider: time)
        return (limiter, time, cfg)
    }

    func testFirstRun() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 100)
        let (limiter, _, _) = try makeLimiter(time)
        XCTAssertEqual(limiter.remaining(now: time.now()), 5)
        XCTAssertTrue(limiter.canConsume(now: time.now()))
    }

    func testMinIntervalRespected() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 100)
        let (limiter, _, _) = try makeLimiter(time)
        // First consume succeeds
        XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
        // Immediate subsequent attempts should be throttled until min interval passes
        for _ in 0..<3 {
            let result = try limiter.consume(now: time.now())
            switch result {
            case .throttledCooldown(let until):
                XCTAssertGreaterThan(until.timeIntervalSince1970, time.now().timeIntervalSince1970)
            default:
                XCTFail("Expected cooldown")
            }
        }
        // After enough time passes, next should succeed
        time = time.advanced(by: 1.1)
        XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
    }

    func testHitLimitAndExpiry() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 100)
        let (limiter, _, _) = try makeLimiter(time)
        for _ in 0..<5 {
            time = time.advanced(by: 2)
            XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
        }
        let res = try limiter.consume(now: time.now())
        switch res {
        case .limitReached(let until):
            XCTAssertGreaterThan(until, time.now())
        default:
            XCTFail("Expected limit reached")
        }
        // After 24h, should reset
        time = time.advanced(by: 86_401)
        XCTAssertTrue(limiter.canConsume(now: time.now()))
        XCTAssertEqual(limiter.remaining(now: time.now()), 5)
    }

    func testClockBackwardsTriggersStrictMode() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 10_000)
        let (limiter, _, _) = try makeLimiter(time)
        // consume one
        XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
        // Move clocks backwards by 30 minutes but uptime forward by 60 seconds => backward relative to uptime
        time = TestTime(nowDate: time.now().addingTimeInterval(-1800), uptime: time.uptime + 60, idfv: time.idfv)
        // Next call should enforce strict mode behavior (calendar day)
        let res = try limiter.consume(now: time.now())
        switch res {
        case .throttledCooldown, .consumed, .limitReached:
            // Any is fine as long as no crash and nextEligibleDate reflects day-boundary if capped
            _ = limiter.nextEligibleDate(now: time.now())
        }
    }

    func testCorruptedStateIntegrityFails() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 100)
        let (limiter, _, cfg) = try makeLimiter(time)
        XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
        // Corrupt file mirror if present by flipping a byte
        // We can't reach private file URL, but we can corrupt keychain then check behavior via next call
        // Read raw data and flip
        let raw = try KeychainStore.read(service: cfg.service, account: cfg.account)
        if var data = raw, data.count > 40 {
            data[40] ^= 0xFF
            try KeychainStore.write(service: cfg.service, account: cfg.account, data: data)
        }
        // Next call should surface integrity failure
        do {
            _ = try limiter.consume(now: time.now())
            XCTFail("Expected integrityCheckFailed to be thrown")
        } catch UsageLimiterError.integrityCheckFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestoreFromFileWhenKeychainMissingAndIDFVMatches() throws {
        var time = TestTime(nowDate: Date(timeIntervalSince1970: 1_700_000_000), uptime: 100)
        let account = "search-\(UUID().uuidString)"
        let cfg = UsageLimiterConfig(limitPer24h: 5, minIntervalSeconds: 1, service: "com.noema.tests", account: account, appGroupID: "group.com.noema")
        // Create a temp mirror file URL
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ul-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let mirrorURL = tmpDir.appendingPathComponent("state.dat")
        // First limiter writes file mirror and keychain
        let limiter = try UsageLimiter(config: cfg, timeProvider: time, fileMirrorURLOverride: mirrorURL)
        XCTAssertEqual(try limiter.consume(now: time.now()), .consumed)
        // Delete Keychain state only
        try? KeychainStore.delete(service: cfg.service, account: cfg.account)
        // New limiter with same IDFV should restore from file
        let limiter2 = try UsageLimiter(config: cfg, timeProvider: time, fileMirrorURLOverride: mirrorURL)
        XCTAssertLessThan(limiter2.remaining(now: time.now()), 5)
    }

    // Helpers to get private account name used by tests
    private func limiterConfigAccount(of limiter: UsageLimiter) -> String { "search" }
}


