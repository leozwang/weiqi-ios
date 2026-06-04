# In-App Purchase Setup & Implementation Guide

This guide walks you through setting up a **Non-Consumable** In-App Purchase (IAP) to unlock the Advanced and Pro difficulty levels of the Go application, both in **App Store Connect** and in the local development environment using **StoreKit 2**.

---

## 1. App Store Connect Configuration

To offer in-app purchases, you must first configure them in your Apple Developer Account and App Store Connect dashboard.

### Step A: Agreements, Tax, and Banking
Before testing or offering any purchase:
1. Log in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Navigate to **Agreements, Tax, and Banking**.
3. Under **Agreements**, accept the **Paid Apps Agreement**.
4. Fill out your **Tax** and **Banking** info. If this is not complete, IAP products will return an empty list in development.

### Step B: Create the In-App Purchase
1. Go to **Apps** in App Store Connect and select your Weiqi application.
2. In the left sidebar, scroll down to **Features** and select **In-App Purchases**.
3. Click the **➕** button next to In-App Purchases.
4. Select **Non-Consumable** as the type.
5. Fill in the product details:
   - **Reference Name**: `Unlock Elite Difficulty` (internal name for dashboard use).
   - **Product ID**: `com.cwave.weiqi.unlock_levels` (Must match the ID in [StoreManager.swift](file:///Users/leozwang/src/weiqi-ios/Weiqi/StoreManager.swift)).
6. Choose a pricing tier (e.g., $1.99 or $2.99 USD).
7. Under **App Store Information**, add at least one localization:
   - **Display Name**: `Unlock Elite Levels`
   - **Description**: `Unlock Advanced and Pro levels of KataGo forever.`
8. Save your changes. Keep in mind that a **Screenshot** (1024x768 size representing the purchase screen) and **Review Notes** are required before submitting to the App Store for review.

### Step C: Create a Sandbox Tester Account
To test purchases on a physical device without spending real money:
1. Go to **Users and Access** in App Store Connect.
2. In the left sidebar under **Sandbox**, click **Testers**.
3. Click the **➕** button to create a new tester account.
4. Use a real or throwaway email address that is **not** currently linked to an active Apple ID.
5. On your test iOS Device, sign in to this account under **Settings > App Store > Sandbox Account** (do not sign out of your main Apple ID from the top iCloud banner; sign in strictly in the sandbox field).

---

## 2. Local Xcode Testing (Using StoreKit Configuration)

You can test the entire purchase flow, including success, pending states, and failure edge cases directly on the Xcode Simulator without configuring App Store Connect first. We have added a local configuration file for this purpose.

### The StoreKit Configuration File
- The file is located at [Products.storekit](file:///Users/leozwang/src/weiqi-ios/Weiqi/Products.storekit).
- It lists `com.cwave.weiqi.unlock_levels` as a Non-Consumable product.

### How to Enable Local StoreKit Testing:
1. Open the project in Xcode.
2. Click on the scheme selector in the top toolbar (currently labeled **Weiqi**) and select **Edit Scheme...** (or press `CMD + <`).
3. Select the **Run** action on the left sidebar.
4. Switch to the **Options** tab at the top.
5. Locate the **StoreKit Configuration** dropdown.
6. Select **Products.storekit** from the list.
7. Click **Close**.

Now, when you run the app on the simulator, StoreKit will mock App Store network calls locally using the product configurations defined in `Products.storekit`.

### Managing Local Transactions:
1. In Xcode, while the application is running, go to the debug area.
2. Click the **StoreKit Transaction Manager** icon (it looks like a credit card with an arrow on it, next to the console area).
3. From there, you can view active purchases, refund them, delete them to test buying again, or toggle simulated network delays and failure codes.

---

## 3. Code Architecture & Implementation

We have added a clean, robust, and asynchronous implementation using **StoreKit 2** (iOS 15+).

### Step A: StoreKit Transaction Manager
The class [StoreManager.swift](file:///Users/leozwang/src/weiqi-ios/Weiqi/StoreManager.swift) handles all native App Store interactions:
- **Transaction Listener Task**: Listens in the background for real-time transactions processed by the App Store (e.g., successful purchases, refunds, or parental consent approvals).
- **Product Loading**: Asynchronously loads localized prices and description metadata for `com.cwave.weiqi.unlock_levels`.
- **Purchase Action**: Dispatches the purchase intent and securely verifies the transaction cryptographic signature from Apple (`VerificationResult`).
- **Restore Purchases**: Triggers `AppStore.sync()` to force-sync purchase history from the user's Apple account.

### Step B: UI Integration
In [GameView.swift](file:///Users/leozwang/src/weiqi-ios/Weiqi/Views/GameView.swift), we updated the UI within the `SettingsView` modal:
1. **Selection Lock State**: The selector buttons for **Advanced** and **Pro** display a lock icon (🔒) if the user has not purchased the feature yet.
2. **Selective Paywall Display**: When a locked level is selected, the **START GAME** button is hidden, replaced by a beautiful purchase card.
3. **App Store Details**: The card pulls live pricing and description strings from the App Store (e.g. "Unlock for $2.99").
4. **Purchase and Restore Flow**: Displays loading indicator spinners during asynchronous tasks (`isPurchasing`), and provides detailed error messages in case of cancellations or failures.

---

## 4. Submitting to App Store Review

When you are ready to release:
1. Ensure the IAP product state in App Store Connect is **Ready to Submit**.
2. When creating your new app version release, scroll down to the **In-App Purchases** section of the version detail page and select your product.
3. Submit the app version and the In-App Purchase together. They must be reviewed and approved at the same time for the first release.
