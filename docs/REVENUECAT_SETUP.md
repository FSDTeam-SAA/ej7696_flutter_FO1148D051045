# RevenueCat setup for Inspector's Path

The Flutter integration is installed and uses:

- `purchases_flutter: ^10.5.0`
- `purchases_ui_flutter: ^10.5.0`
- Test Store public SDK key: `test_zIiSHVlGWkfVsHoxQhsRXlfqkcv`
- Subscription entitlement: `professional_access`
- Subscription product: `six_month_subscriptions`
- The RevenueCat **current Offering**, so products and paywalls can be changed without an app release

The test key is a public client SDK key, not a RevenueCat secret key. Never put a RevenueCat secret API key in Flutter code.

## 1. Install with Pub

Already run in this project:

```sh
flutter pub add purchases_flutter purchases_ui_flutter
```

Android is set to API 24 because RevenueCat Paywalls and Customer Center require it. iOS is set to 15.0 so native RevenueCat Paywalls are available on every supported iOS device. `MainActivity` already extends `FlutterFragmentActivity`, Android uses `singleTop`, and the Billing permission is present.

In Xcode, verify **Runner > Signing & Capabilities > In-App Purchase** is enabled. The project file has also been updated to declare that capability.

## 2. Create the first Test Store product

No dashboard products exist yet, so the SDK will deliberately show a clear configuration error until these steps are complete.

1. Open the RevenueCat project and select **Product catalog > Products**.
2. Choose **+ New product**, select **Test Store**, and create:
   - Identifier: `six_month_subscriptions`
   - Type/duration: subscription, six months
   - Set any test price you want.
3. Open **Product catalog > Entitlements** and create `professional_access`.
4. Attach `six_month_subscriptions` to `professional_access`.
5. Open **Product catalog > Offerings** and create an Offering such as `default`.
6. Add a **Six Month** package and attach `six_month_subscriptions`.
7. Make this the project's **current/default Offering**.
8. Create a RevenueCat Paywall for that Offering and publish it.

The app always requests `offerings.current`; do not hardcode the Offering ID in Flutter.

## 3. Configure real App Store and Play products

Before production:

1. Add the iOS app in RevenueCat with bundle ID `com.khalid.inspectorspath` and connect App Store Connect.
2. Add the Android app with the exact Play application ID used by the release build (`com.Khalid.inspectorspath`) and connect its Play service credentials.
3. Create the six-month auto-renewing subscription in App Store Connect and the corresponding subscription/base plan in Google Play Console.
4. Import both store products into RevenueCat instead of manually retyping identifiers where import is available.
5. Attach both platform products to the same `professional_access` entitlement.
6. Put the equivalent iOS and Android products into the same Six Month package in the current Offering.
7. Keep the Test Store Offering for development, and use the real store products/paywall for release testing.

The existing one-time exam product IDs are listed in `lib/services/iap_service.dart`. If those should also be sold through RevenueCat, create/import each as a non-consumable, attach any desired exam entitlement, and add packages only when you want them displayed by an Offering.

## 4. API key selection

The supplied Test Store key is the code default, so a debug build works without extra flags after the dashboard setup is finished. Production builds should override it with each app's public SDK key:

```sh
flutter run --dart-define=REVENUECAT_API_KEY=your_public_test_store_key

flutter build appbundle \
  --dart-define=REVENUECAT_GOOGLE_API_KEY=goog_your_public_google_sdk_key

flutter build ipa \
  --dart-define=REVENUECAT_APPLE_API_KEY=appl_your_public_apple_sdk_key
```

Platform-specific keys take precedence over `REVENUECAT_API_KEY` and the built-in Test Store key.

## 5. Flutter usage

`IapService` is initialized before `runApp`, identifies a signed-in backend user with RevenueCat, listens for CustomerInfo changes, loads the current Offering, and maps active entitlements to app access.

Get fresh customer information and check access with:

```dart
final purchases = Get.find<IapService>();
final customerInfo = await purchases.refreshCustomerInfo();

final hasProfessionalAccess =
    customerInfo?.entitlements.active.containsKey(
      professionalEntitlementId,
    ) ??
    false;
```

Present the dashboard-configured paywall only when the entitlement is missing:

```dart
final purchased = await Get.find<IapService>()
    .presentProfessionalPaywall(selectedExamId: examId);

if (!purchased) {
  final message = Get.find<IapService>().errorMessage.value;
  // Display message when non-empty. A user cancellation is not a crash.
}
```

The app's existing `buyProfessionalSubscription` method calls this paywall flow. A successful purchase or restore refreshes CustomerInfo and unlocks only when `professional_access` is active.

For one-time products, the service prefers `PurchaseParams.package(...)` when the product belongs to an Offering, and safely falls back to `PurchaseParams.storeProduct(...)` for catalog-only exam products.

Restore purchases directly with:

```dart
await Get.find<IapService>().restorePurchases();
```

## 6. Customer Center

The Profile screen now includes **Manage Subscription**, which opens Customer Center:

```dart
await Get.find<IapService>().presentCustomerCenter();
```

Enable and configure Customer Center in the RevenueCat dashboard before relying on this entry point. It is most useful once subscriptions are live because it can centralize cancellation, restore, refund/support, and plan-management paths. RevenueCat currently makes Customer Center available on Pro and Enterprise plans. Keep the direct Restore Purchase action as a fallback and for store-review clarity.

## 7. Error handling and subscription best practices

- Gate premium features with the entitlement (`professional_access`), not a product ID. Products and packages can then change remotely.
- Treat cancellation and pending purchases as normal states. Do not show them as application crashes.
- Call `getCustomerInfo()` when a protected screen needs a decision. RevenueCat caches CustomerInfo, so this is safe to call repeatedly.
- CustomerInfo listeners update only after an SDK/network operation; they are not server push notifications.
- Call `logIn` after your app login and `logOut` before clearing the local session. This project already does both.
- Use stable, non-email backend user IDs as RevenueCat App User IDs. Do not use anonymous IDs for users who already have accounts.
- Keep purchase buttons disabled when no Offering/product is available and show the configuration message from `errorMessage`.
- Test new purchases, restore, cancellation, billing retry, expiration, account switching, and reinstall behavior before release.
- For authoritative backend access, add RevenueCat webhooks and verify webhook authorization/idempotency. The client entitlement is appropriate for responsive UI, but your API should independently enforce paid server resources.
- Configure App Store Server Notifications and Google Real-Time Developer Notifications through RevenueCat before production.

## 8. Expected test checklist

1. Start the app and sign in so RevenueCat receives the backend user ID.
2. Open Subscribe and choose the professional upgrade.
3. Confirm the RevenueCat Paywall appears from the current Offering.
4. Complete a Test Store purchase.
5. Confirm `professional_access` appears active in the RevenueCat customer profile and the app unlocks professional access.
6. Log out, log back into the same account, and confirm access returns.
7. Use **Restore Purchase** and **Manage Subscription** from Profile.
8. Test a second app account and verify purchases are not accidentally attributed to the first account.
