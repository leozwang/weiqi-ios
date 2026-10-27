import XCTest
import StoreKit
import StoreKitTest
@testable import Weiqi

/// Payment tests: the app's real StoreManager (StoreKit 2) against Xcode's local StoreKit test
/// environment, configured from Weiqi/Products.storekit (bundled into this test target). They
/// cover the non-consumable "com.cwave.weiqi.unlock_levels" that unlocks Advanced and Pro.
@MainActor
final class StoreTests: XCTestCase {
    private let productID = "com.cwave.weiqi.unlock_levels"
    private var session: SKTestSession!

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: StoreTests.self).url(forResource: "Products", withExtension: "storekit"),
                                "Products.storekit must be a resource of WeiqiTests")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true   // auto-confirm purchases, no system sheet
        session.clearTransactions()     // start every test with "payment disabled"
    }

    override func tearDown() async throws {
        session?.clearTransactions()
    }

    // MARK: - Helpers

    /// A StoreManager as the app creates it at launch, with its product loaded.
    private func makeStore() async -> StoreManager {
        let store = StoreManager()
        await store.loadProducts()
        await store.updatePurchaseStatus()
        return store
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return condition()
    }

    private func transactionID() throws -> UInt {
        try XCTUnwrap(session.allTransactions().last { $0.productIdentifier == productID }?.identifier,
                      "no transaction for \(productID)")
    }

    // MARK: - Tests

    func testProductIsConfiguredAsNonConsumable() async throws {
        let store = await makeStore()
        let product = try XCTUnwrap(store.product, "\(productID) did not load")
        XCTAssertEqual(product.id, productID)
        XCTAssertEqual(product.type, .nonConsumable, "the unlock must be bought once and kept forever")
        XCTAssertEqual(product.displayName, "Unlock Elite Levels")
        XCTAssertGreaterThan(product.price, 0)
        XCTAssertFalse(product.displayPrice.isEmpty)
    }

    func testLevelsAreLockedWithoutPurchase() async {
        let store = await makeStore()
        XCTAssertFalse(store.isPurchased)
    }

    func testPurchaseUnlocksLevels() async {
        let store = await makeStore()
        await store.purchase()
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isPurchasing)
        XCTAssertTrue(store.isPurchased)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == self.productID }.count, 1)
    }

    func testPurchaseIsRememberedAtNextLaunch() async throws {
        let buyer = await makeStore()
        await buyer.purchase()
        XCTAssertTrue(buyer.isPurchased)
        // A fresh StoreManager (= app relaunch) must find the entitlement on its own.
        let relaunched = StoreManager()
        let unlocked = await waitUntil { relaunched.isPurchased }
        XCTAssertTrue(unlocked, "purchase not restored from current entitlements at launch")
    }

    func testRefundLocksLevelsAgain() async throws {
        let store = await makeStore()
        await store.purchase()
        XCTAssertTrue(store.isPurchased)
        try session.refundTransaction(identifier: transactionID())
        let locked = await waitUntil { !store.isPurchased }
        XCTAssertTrue(locked, "a refunded purchase must lock Advanced and Pro again")
    }

    func testRestorePurchases() async throws {
        let buyer = await makeStore()
        await buyer.purchase()
        let store = await makeStore()
        await store.restorePurchases()
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isPurchasing)
        XCTAssertTrue(store.isPurchased)
    }

    func testAskToBuyStaysLockedUntilApproved() async throws {
        session.askToBuyEnabled = true
        let store = await makeStore()
        await store.purchase()
        XCTAssertFalse(store.isPurchased, "a pending (Ask to Buy) purchase must not unlock")
        try session.approveAskToBuyTransaction(identifier: transactionID())
        let unlocked = await waitUntil { store.isPurchased }
        XCTAssertTrue(unlocked, "an approved Ask to Buy purchase must unlock via Transaction.updates")
    }

    func testFailedPurchaseShowsErrorAndStaysLocked() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("simulated StoreKit errors need iOS 17") }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let store = await makeStore()
        await store.purchase()
        XCTAssertFalse(store.isPurchased)
        XCTAssertFalse(store.isPurchasing)
        XCTAssertNotNil(store.errorMessage, "the user must see why the purchase failed")
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    /// Offline (Android P4): the product cannot load, nothing can be bought and nothing crashes;
    /// Advanced and Pro stay locked. "Load Store Info" (the paywall's retry) loads the product once
    /// the App Store can be reached again.
    func testOfflineStoreKeepsLevelsLockedAndCanRetry() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("simulated StoreKit errors need iOS 17") }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let store = await makeStore()
        XCTAssertNil(store.product, "no product can load offline")
        XCTAssertFalse(store.isPurchased)
        await store.purchase()
        XCTAssertFalse(store.isPurchased, "nothing can be bought offline")
        XCTAssertFalse(store.isPurchasing, "the paywall must not stay busy")
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadProducts()
        XCTAssertEqual(store.product?.id, productID, "the retry must load the product when online again")
        XCTAssertFalse(store.isPurchased)
    }
}
