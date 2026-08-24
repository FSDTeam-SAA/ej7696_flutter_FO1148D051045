import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart' as rc_ui;
import 'package:url_launcher/url_launcher.dart';

import '../controllers/user_controller.dart';
import '../models/payment_success_details.dart';
import 'api_service.dart';
import 'storage_service.dart';

const Map<String, String> examIapProductIds = {
  'API_1184': 'com.inspectorspath.exam.api1184.sixmonth',
  'API_510': 'com.inspectorspath.exam.api510.sixmonth',
  'API_570': 'com.inspectorspath.exam.api570.sixmonth',
  'API_653': 'com.inspectorspath.exam.api653.sixmonth',
  'API_936': 'com.inspectorspath.exam.api936.sixmonth',
  'API_1169': 'com.inspectorspath.exam.api1169.sixmonth',
  'API_SIEE': 'com.inspectorspath.exam.siee.sixmonth',
  'API_SIFE': 'com.inspectorspath.exam.sife.sixmonth',
  'API_SIRE': 'com.inspectorspath.exam.sire.sixmonth',
};

const Map<String, String> examAndroidBasePlanIds = {
  'API_1184': 'api1184sixmonth',
  'API_510': 'api510sixmonth',
  'API_570': 'api570sixmonth',
  'API_653': 'api653sixmonth',
  'API_936': 'api936sixmonth',
  'API_1169': 'api1169sixmonth',
  'API_SIEE': 'sieesixmonth',
  'API_SIFE': 'sifesixmonth',
  'API_SIRE': 'siresixmonth',
};

const Map<String, String> legacyExamIapProductIds = {
  'API_1184': 'com.inspectorspath.exam.api1184.unlock',
  'API_510': 'com.inspectorspath.exam.api510.unlock',
  'API_570': 'com.inspectorspath.exam.api570.unlock',
  'API_653': 'com.inspectorspath.exam.api653.unlock',
  'API_936': 'com.inspectorspath.exam.api936.unlock',
  'API_1169': 'com.inspectorspath.exam.api1169.unlock',
  'API_SIEE': 'com.inspectorspath.exam.siee.unlock',
  'API_SIFE': 'com.inspectorspath.exam.sife.unlock',
  'API_SIRE': 'com.inspectorspath.exam.sire.unlock',
};

String examSubscriptionProductId(String code, {bool? isAndroid}) {
  final baseId = examIapProductIds[code] ?? '';
  if (baseId.isEmpty) return '';
  if (!(isAndroid ?? Platform.isAndroid)) return baseId;
  final basePlanId = examAndroidBasePlanIds[code] ?? '';
  return basePlanId.isEmpty ? '' : '$baseId:$basePlanId';
}

const String professionalSubscriptionId = 'six_month_subscriptions';
const String professionalSubscriptionBasePlanId = 'six-month';
const String androidProfessionalSubscriptionProductId =
    '$professionalSubscriptionId:$professionalSubscriptionBasePlanId';
const String appleProfessionalSubscriptionProductId =
    professionalSubscriptionId;
const String professionalEntitlementId = 'professional_access';

@visibleForTesting
Set<String> ownedExamCodes({
  required Iterable<String> purchasedProductIds,
  required Iterable<String> activeEntitlementIds,
}) {
  final purchasedIds = purchasedProductIds.toSet();
  final entitlementIds = activeEntitlementIds.toSet();
  return examIapProductIds.entries
      .where((entry) {
        final entitlementId =
            'exam_${entry.key.toLowerCase().replaceFirst('api_', '')}';
        final androidProductId = examSubscriptionProductId(
          entry.key,
          isAndroid: true,
        );
        return purchasedIds.contains(entry.value) ||
            purchasedIds.contains(androidProductId) ||
            purchasedIds.contains(legacyExamIapProductIds[entry.key]) ||
            entitlementIds.contains(entitlementId);
      })
      .map((entry) => entry.key)
      .toSet();
}

@visibleForTesting
bool refundRequestWasSubmitted(String status) =>
    status.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') == 'success';

@visibleForTesting
bool revenueCatSyncConfirmsProduct({
  required String? productId,
  required String? examId,
  required Map<String, dynamic>? data,
}) {
  final normalizedProductId = productId?.trim() ?? '';
  if (normalizedProductId.isEmpty) return true;
  if (data == null) return false;

  final isSubscription = <String>{
    appleProfessionalSubscriptionProductId,
    androidProfessionalSubscriptionProductId,
  }.contains(normalizedProductId);
  if (isSubscription) {
    final selectedExam = data['selectedExam'];
    return data['subscriptionTier']?.toString().trim().toLowerCase() ==
            'professional' &&
        data['hasProfessionalAccess'] == true &&
        examId?.trim().isNotEmpty == true &&
        selectedExam is Map &&
        selectedExam['unlocked'] == true &&
        selectedExam['examId']?.toString() == examId;
  }

  final isExamProduct = examIapProductIds.entries.any(
    (entry) =>
        normalizedProductId == entry.value ||
        normalizedProductId ==
            examSubscriptionProductId(entry.key, isAndroid: true),
  );
  if (!isExamProduct) return false;
  final normalizedExamId = examId?.trim() ?? '';
  if (normalizedExamId.isEmpty) return false;

  final selectedExam = data['selectedExam'];
  if (selectedExam is Map &&
      selectedExam['unlocked'] == true &&
      selectedExam['examId']?.toString() == normalizedExamId) {
    return true;
  }
  return false;
}

@visibleForTesting
bool revenueCatCustomerHasActiveProduct({
  required String productId,
  required Iterable<String> activeSubscriptionIds,
  required Iterable<String> activeEntitlementProductIds,
}) {
  final normalizedProductId = productId.trim();
  if (normalizedProductId.isEmpty) return false;
  return activeSubscriptionIds.contains(normalizedProductId) ||
      activeEntitlementProductIds.contains(normalizedProductId);
}

({bool subscriptionRequired, bool examPurchaseRequired})
mobileCheckoutRequirements({
  required bool isProfessionalActive,
  required bool examOwned,
}) => (
  subscriptionRequired: !isProfessionalActive,
  examPurchaseRequired: isProfessionalActive && !examOwned,
);

enum IapPurchaseKind { exam, professional }

class IapCompletedPurchase {
  final IapPurchaseKind kind;
  final String productId;
  final String? examId;
  final Map<String, dynamic>? payload;
  final PaymentSuccessDetails? paymentDetails;

  const IapCompletedPurchase({
    required this.kind,
    required this.productId,
    this.examId,
    this.payload,
    this.paymentDetails,
  });
}

class _PendingIapIntent {
  final IapPurchaseKind kind;
  final String productId;
  final String? examId;

  const _PendingIapIntent({
    required this.kind,
    required this.productId,
    this.examId,
  });
}

class IapService extends GetxService {
  static const String _revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: 'test_zIiSHVlGWkfVsHoxQhsRXlfqkcv',
  );
  static const String _revenueCatGoogleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
    defaultValue: 'goog_uLvOSubEioODfankUqvoYaTLTxX',
  );
  static const String _revenueCatAppleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
    defaultValue: 'appl_HYHXtAdEYRVNrYzLmMQuqWLOOcc',
  );

  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  final Map<String, _PendingIapIntent> _pendingIntents = {};
  final Map<String, rc.StoreProduct> _revenueCatProducts = {};
  final Map<String, rc.Package> _revenueCatPackages = {};
  rc.Offerings? _offerings;
  rc.CustomerInfo? _latestCustomerInfo;
  bool _revenueCatConfigured = false;
  Map<String, dynamic>? _lastBackendSyncData;
  Future<bool>? _reconciliationInFlight;
  Future<bool>? _refundRequestUpdateInFlight;
  late final rc.CustomerInfoUpdateListener _customerInfoListener =
      _handleRevenueCatCustomerInfo;

  final RxBool isStoreAvailable = false.obs;
  final RxBool isLoadingProducts = false.obs;
  final RxBool isRestoring = false.obs;
  final RxString errorMessage = ''.obs;

  /// Confirmations and neutral progress notes. Kept apart from [errorMessage]
  /// so the UI can style "it worked" differently from "it failed" — the two
  /// used to share one field and every success rendered in the error colour.
  final RxString successMessage = ''.obs;
  final RxSet<String> missingProductIds = <String>{}.obs;
  final RxSet<String> inFlightProductIds = <String>{}.obs;
  final Rx<IapCompletedPurchase?> lastCompletedPurchase =
      Rx<IapCompletedPurchase?>(null);

  void _clearMessages() {
    errorMessage.value = '';
    successMessage.value = '';
  }

  bool get isMobileStore => Platform.isIOS || Platform.isAndroid;
  String get professionalSubscriptionProductId => Platform.isAndroid
      ? androidProfessionalSubscriptionProductId
      : appleProfessionalSubscriptionProductId;
  bool get hasLoadedProducts => _revenueCatProducts.isNotEmpty;
  bool get isRevenueCatConfigured => _revenueCatConfigured;
  rc.CustomerInfo? get customerInfo => _latestCustomerInfo;
  rc.Offering? get currentOffering => _offerings?.current;
  bool get hasActiveProfessionalEntitlement =>
      _latestCustomerInfo?.entitlements.active.containsKey(
        professionalEntitlementId,
      ) ??
      false;

  Set<String> get allProductIds => <String>{
    ...examIapProductIds.keys.map(examSubscriptionProductId),
    professionalSubscriptionProductId,
  };

  Future<IapService> init() async {
    if (!isMobileStore) {
      debugPrint('IAP: mobile store purchases disabled on this platform.');
      return this;
    }

    await _configureRevenueCat();
    await loadProducts();
    return this;
  }

  @override
  void onClose() {
    if (_revenueCatConfigured) {
      rc.Purchases.removeCustomerInfoUpdateListener(_customerInfoListener);
    }
    super.onClose();
  }

  Future<void> loadProducts() async {
    if (!isMobileStore || isLoadingProducts.value) return;
    await _loadRevenueCatProducts();
  }

  String? priceForExam({required String? examCode, required String? examName}) {
    final code = resolveExamCode(code: examCode, name: examName);
    final productId = code == null ? null : examSubscriptionProductId(code);
    return productId == null
        ? null
        : _revenueCatProducts[productId]?.priceString;
  }

  bool get hasProfessionalProduct =>
      _revenueCatProducts.containsKey(professionalSubscriptionProductId);

  String? get professionalPrice =>
      _revenueCatProducts[professionalSubscriptionProductId]?.priceString;

  String? resolveExamCode({String? code, String? name}) {
    final rawCode = (code ?? '').trim();
    final candidates = <String>[
      rawCode,
      rawCode.replaceAll('-', '_'),
      rawCode.replaceAll(' ', '_'),
      (name ?? '').trim(),
    ];

    for (final candidate in candidates) {
      final normalized = candidate
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      if (examIapProductIds.containsKey(normalized)) return normalized;

      final apiMatch = RegExp(
        r'API_?(1184|510|570|653|936|1169|SIEE|SIFE|SIRE)',
      ).firstMatch(normalized);
      if (apiMatch != null) {
        return 'API_${apiMatch.group(1)}';
      }
    }
    return null;
  }

  Future<bool> buyExamUnlock({
    required String examId,
    required String? examCode,
    required String examName,
  }) async {
    if (!isMobileStore) return false;
    final resolvedCode = resolveExamCode(code: examCode, name: examName);
    final productId = resolvedCode == null
        ? null
        : examSubscriptionProductId(resolvedCode);
    if (productId == null) {
      errorMessage.value = 'Purchase is not available for this exam.';
      return false;
    }
    final intent = _PendingIapIntent(
      kind: IapPurchaseKind.exam,
      productId: productId,
      examId: examId,
    );
    return _buyRevenueCatProduct(productId: productId, intent: intent);
  }

  Future<bool> buyProfessionalSubscription({String? examId}) async {
    if (!isMobileStore) return false;
    final productId = professionalSubscriptionProductId;
    final intent = _PendingIapIntent(
      kind: IapPurchaseKind.professional,
      productId: productId,
      examId: examId,
    );
    return _buyRevenueCatProduct(productId: productId, intent: intent);
  }

  Future<void> restorePurchases() async {
    if (!isMobileStore) return;
    if (isRestoring.value) return;
    isRestoring.value = true;
    _clearMessages();
    debugPrint('IAP: restore started.');
    try {
      if (!_revenueCatConfigured) {
        errorMessage.value = 'Purchases are not configured for this app build.';
        return;
      }
      final backendSynced = await reconcilePurchases(restoreFromStore: true);
      if (backendSynced) {
        successMessage.value =
            'Your purchases have been restored. Your exams are ready to use.';
      }
    } catch (e, stackTrace) {
      debugPrint('IAP: restore failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'We could not restore your purchases just now. '
          'Please check your connection and tap Restore Purchase again.';
    } finally {
      isRestoring.value = false;
      debugPrint('IAP: restore request finished.');
    }
  }

  Future<void> _configureRevenueCat() async {
    final platformApiKey = Platform.isAndroid
        ? _revenueCatGoogleApiKey.trim()
        : _revenueCatAppleApiKey.trim();
    final apiKey = platformApiKey.isNotEmpty
        ? platformApiKey
        : _revenueCatApiKey.trim();
    if (apiKey.isEmpty) {
      debugPrint('RevenueCat: API key is not set for this platform.');
      if (isMobileStore) {
        errorMessage.value = 'Purchases are not configured for this app build.';
      }
      return;
    }

    try {
      await rc.Purchases.setLogLevel(
        kDebugMode ? rc.LogLevel.debug : rc.LogLevel.warn,
      );
      var alreadyConfigured = await rc.Purchases.isConfigured;
      // A Flutter hot restart keeps the Android RevenueCat singleton alive.
      // Reset it in debug mode so changes to dart-define/default API keys are
      // applied without requiring the emulator process to be killed manually.
      if (kDebugMode && Platform.isAndroid && alreadyConfigured) {
        await rc.Purchases.close();
        alreadyConfigured = await rc.Purchases.isConfigured;
      }
      if (!alreadyConfigured) {
        final userId = (await _storageService.getUserId())?.trim();
        final configuration = rc.PurchasesConfiguration(apiKey)
          ..appUserID = userId == null || userId.isEmpty ? null : userId
          ..diagnosticsEnabled = kDebugMode;
        await rc.Purchases.configure(configuration);
      }
      _revenueCatConfigured = true;
      rc.Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: configuration failed: $e');
      debugPrint('$stackTrace');
      _revenueCatConfigured = false;
      if (isMobileStore) {
        errorMessage.value =
            'Purchases are currently unavailable. Please try again later.';
      }
    }
  }

  Future<void> _loadRevenueCatProducts() async {
    isLoadingProducts.value = true;
    _clearMessages();
    try {
      if (!_revenueCatConfigured) {
        isStoreAvailable.value = false;
        errorMessage.value = 'Purchases are not configured for this app build.';
        return;
      }

      _offerings = await rc.Purchases.getOfferings();
      final packages = _offerings!.all.values
          .expand((offering) => offering.availablePackages)
          .toList(growable: false);
      _revenueCatPackages
        ..clear()
        ..addEntries(
          packages.map(
            (package) => MapEntry(package.storeProduct.identifier, package),
          ),
        );
      var subscriptionProducts = packages
          .map((package) => package.storeProduct)
          .where(
            (product) =>
                product.identifier == professionalSubscriptionProductId,
          )
          .toList(growable: false);
      if (subscriptionProducts.isEmpty) {
        subscriptionProducts = await rc.Purchases.getProducts(<String>[
          professionalSubscriptionProductId,
        ], productCategory: rc.ProductCategory.subscription);
      }
      final examProducts = await rc.Purchases.getProducts(
        examIapProductIds.keys
            .map(examSubscriptionProductId)
            .toList(growable: false),
        productCategory: rc.ProductCategory.subscription,
      );
      _revenueCatProducts
        ..clear()
        ..addEntries(
          <rc.StoreProduct>[
            ...subscriptionProducts,
            ...examProducts,
          ].map((product) => MapEntry(product.identifier, product)),
        );
      missingProductIds.assignAll(
        allProductIds.difference(_revenueCatProducts.keys.toSet()),
      );
      isStoreAvailable.value = _revenueCatProducts.isNotEmpty;
      if (!isStoreAvailable.value) {
        errorMessage.value =
            'No RevenueCat products are available. Configure products and a current offering in the RevenueCat dashboard.';
      }
      debugPrint(
        'RevenueCat: products returned: '
        '${_revenueCatProducts.values.map((p) => '${p.identifier}=${p.priceString}').join(', ')}',
      );
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: failed to load products: $e');
      debugPrint('$stackTrace');
      isStoreAvailable.value = false;
      errorMessage.value =
          'Purchases are currently unavailable. Please try again later.';
    } finally {
      isLoadingProducts.value = false;
    }
  }

  Future<bool> _buyRevenueCatProduct({
    required String productId,
    required _PendingIapIntent intent,
  }) async {
    if (inFlightProductIds.contains(productId)) {
      errorMessage.value = 'A purchase is already in progress.';
      return false;
    }
    if (!_revenueCatConfigured || _revenueCatProducts[productId] == null) {
      await loadProducts();
    }
    final product = _revenueCatProducts[productId];
    if (!_revenueCatConfigured || product == null) {
      errorMessage.value =
          'Purchases are currently unavailable. Please try again later.';
      return false;
    }

    _pendingIntents[productId] = intent;
    inFlightProductIds.add(productId);
    _clearMessages();
    try {
      final identified = await _identifyRevenueCatUserForPurchase();
      if (!identified) return false;
      final package = _revenueCatPackages[productId];
      debugPrint(
        'RevenueCat: starting purchase '
        'product=$productId package=${package?.identifier ?? 'store_product'}',
      );
      final purchaseParams = package == null
          ? rc.PurchaseParams.storeProduct(product)
          : rc.PurchaseParams.package(package);
      final result = await rc.Purchases.purchase(purchaseParams);
      return _deliverRevenueCatPurchase(intent, product, result);
    } on PlatformException catch (e) {
      final code = rc.PurchasesErrorHelper.getErrorCode(e);
      debugPrint(
        'RevenueCat: purchase exception '
        'code=$code platformCode=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      switch (code) {
        case rc.PurchasesErrorCode.purchaseCancelledError:
          if (Platform.isIOS) {
            final restored = await _recoverCancelledIosPurchase(
              productId: productId,
              intent: intent,
            );
            if (restored) return true;
            if (errorMessage.value.isNotEmpty) break;
          }
          errorMessage.value = 'Purchase cancelled. Nothing was charged.';
          break;
        case rc.PurchasesErrorCode.paymentPendingError:
          errorMessage.value =
              'Your payment is still being processed by the store. '
              'We will unlock your exam as soon as it is approved.';
          break;
        case rc.PurchasesErrorCode.productAlreadyPurchasedError:
          final backendSynced = await reconcilePurchases(
            restoreFromStore: true,
            examId: intent.examId,
            productId: productId,
          );
          if (backendSynced) {
            successMessage.value =
                'You already own this. Access has been restored.';
          } else {
            errorMessage.value =
                'You already own this, but we are still unlocking it. '
                'Please tap Restore Purchase in a moment.';
          }
          return backendSynced;
        default:
          debugPrint('RevenueCat: purchase failed ($code): ${e.message}');
          errorMessage.value = 'Purchase failed. Please try again.';
      }
      return false;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: purchase failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value = 'Purchase failed. Please try again.';
      return false;
    } finally {
      inFlightProductIds.remove(productId);
      _pendingIntents.remove(productId);
    }
  }

  Future<bool> _recoverCancelledIosPurchase({
    required String productId,
    required _PendingIapIntent intent,
  }) async {
    debugPrint(
      'RevenueCat: iOS reported a cancelled purchase; checking the App Store receipt for an existing active purchase.',
    );
    try {
      final customerInfo = await rc.Purchases.restorePurchases();
      _latestCustomerInfo = customerInfo;
      final hasActiveProduct = revenueCatCustomerHasActiveProduct(
        productId: productId,
        activeSubscriptionIds: customerInfo.activeSubscriptions,
        activeEntitlementProductIds: customerInfo.entitlements.active.values
            .map((entitlement) => entitlement.productIdentifier),
      );
      if (!hasActiveProduct) {
        debugPrint(
          'RevenueCat: cancelled purchase recovery found no active product for $productId.',
        );
        return false;
      }

      final backendSynced = await _syncBackendAccess(
        examId: intent.examId,
        productId: productId,
      );
      if (!backendSynced) return false;
      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshProfile();
      }
      successMessage.value =
          'Your existing purchase has been restored. Access is now active.';
      debugPrint(
        'RevenueCat: recovered active App Store purchase for $productId.',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: cancelled purchase recovery failed: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  Future<bool> _deliverRevenueCatPurchase(
    _PendingIapIntent intent,
    rc.StoreProduct product,
    rc.PurchaseResult result,
  ) async {
    _latestCustomerInfo = result.customerInfo;
    final backendSynced = await _syncBackendAccess(
      examId: intent.examId,
      productId: product.identifier,
    );
    final userController = Get.isRegistered<UserController>()
        ? Get.find<UserController>()
        : null;
    if (backendSynced && userController != null) {
      // Flip the exam to unlocked locally first. The backend has already
      // confirmed the entitlement at this point, so waiting for the profile
      // round-trip only leaves the card showing "Unlock" for no reason —
      // which previously lasted until the 60s poll caught up.
      final purchasedExamId = intent.examId?.trim() ?? '';
      if (purchasedExamId.isNotEmpty) {
        await userController.addUnlockedExamId(purchasedExamId);
      }
      // The backend is authoritative for each exam's independent expiry.
      await userController.refreshProfile();
      // refreshProfile replaces the id set with the server's list, so re-apply
      // the purchase in case /unlocks has not caught up yet. Without this the
      // card flips back to "Unlock" right after appearing unlocked.
      if (purchasedExamId.isNotEmpty &&
          !userController.unlockedExamIds.value.contains(purchasedExamId)) {
        await userController.addUnlockedExamId(purchasedExamId);
      }
    }

    final transactionId = result.storeTransaction.transactionIdentifier;
    final selectedExam = _lastBackendSyncData?['selectedExam'];
    final selectedExamData = selectedExam is Map
        ? Map<String, dynamic>.from(selectedExam)
        : const <String, dynamic>{};
    final payload = <String, dynamic>{
      'provider': 'revenuecat',
      'store': Platform.isIOS ? 'app_store' : 'google_play',
      'productId': product.identifier,
      'transactionId': transactionId,
      'appUserId': result.customerInfo.originalAppUserId,
      'activeEntitlements': result.customerInfo.entitlements.active.keys.toList(
        growable: false,
      ),
      'backendSynced': backendSynced,
    };
    lastCompletedPurchase.value = IapCompletedPurchase(
      kind: intent.kind,
      productId: product.identifier,
      examId: intent.examId,
      payload: payload,
      paymentDetails: PaymentSuccessDetails(
        purchaseType: intent.kind == IapPurchaseKind.exam ? 'exam' : 'plan',
        title: intent.kind == IapPurchaseKind.exam
            ? 'Exam Unlock'
            : 'Professional Plan',
        amountPaid: product.price,
        currency: product.currencyCode,
        billingCycleLabel: intent.kind == IapPurchaseKind.professional
            ? '6 months'
            : null,
        unlockDurationLabel: '6 months',
        expiresAt: DateTime.tryParse(
          selectedExamData['expiresAt']?.toString() ?? '',
        ),
        expiryMonths: 6,
        paymentMethodLabel: Platform.isIOS
            ? 'Apple In-App Purchase'
            : 'Google Play In-App Purchase',
        receiptNumber: transactionId,
        transactionReference: transactionId,
        paidAt: DateTime.tryParse(result.storeTransaction.purchaseDate),
        subscriptionStartedAt: DateTime.tryParse(
          selectedExamData['startedAt']?.toString() ?? '',
        ),
        provider: Platform.isIOS ? 'apple' : 'google',
        status: 'successful',
      ),
    );
    return backendSynced;
  }

  void _handleRevenueCatCustomerInfo(rc.CustomerInfo customerInfo) {
    // CustomerInfo can update several times during one purchase/restore. Cache
    // it here; explicit purchase, restore, login, and app-resume flows perform
    // the single server-authoritative reconciliation.
    _latestCustomerInfo = customerInfo;
  }

  Future<bool> identifyCurrentUser() => reconcilePurchases();

  Future<bool> _identifyRevenueCatUserForPurchase() async {
    final userId = (await _storageService.getUserId())?.trim() ?? '';
    if (userId.isEmpty) {
      errorMessage.value = 'Please sign in before making a purchase.';
      return false;
    }

    try {
      final rc.CustomerInfo customerInfo;
      if (await rc.Purchases.appUserID != userId) {
        customerInfo = (await rc.Purchases.logIn(userId)).customerInfo;
      } else {
        customerInfo = await rc.Purchases.getCustomerInfo();
      }
      _latestCustomerInfo = customerInfo;
      return true;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: user identification failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to connect your account to the store. Please try again.';
      return false;
    }
  }

  Future<bool> reconcilePurchases({
    bool restoreFromStore = false,
    String? examId,
    String? productId,
    bool refreshProfileAfterSync = true,
  }) async {
    if (!_revenueCatConfigured) return false;
    final userId = (await _storageService.getUserId())?.trim() ?? '';
    if (userId.isEmpty) return false;

    final existing = _reconciliationInFlight;
    final isNormalRefresh =
        !restoreFromStore && examId == null && productId == null;
    if (existing != null && isNormalRefresh) return existing;
    if (existing != null) await existing;

    final reconciliation = _performReconciliation(
      userId: userId,
      restoreFromStore: restoreFromStore,
      examId: examId,
      productId: productId,
      refreshProfileAfterSync: refreshProfileAfterSync,
    );
    _reconciliationInFlight = reconciliation;
    try {
      return await reconciliation;
    } finally {
      if (identical(_reconciliationInFlight, reconciliation)) {
        _reconciliationInFlight = null;
      }
    }
  }

  Future<bool> _performReconciliation({
    required String userId,
    required bool restoreFromStore,
    required String? examId,
    required String? productId,
    required bool refreshProfileAfterSync,
  }) async {
    try {
      rc.CustomerInfo customerInfo;
      if (await rc.Purchases.appUserID != userId) {
        final result = await rc.Purchases.logIn(userId);
        customerInfo = result.customerInfo;
        if (restoreFromStore) {
          customerInfo = await rc.Purchases.restorePurchases();
        }
      } else {
        customerInfo = restoreFromStore
            ? await rc.Purchases.restorePurchases()
            : await rc.Purchases.getCustomerInfo();
      }

      _latestCustomerInfo = customerInfo;
      final backendSynced = await _syncBackendAccess(
        examId: examId,
        productId: productId,
      );
      if (backendSynced &&
          refreshProfileAfterSync &&
          Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshProfile();
      }
      return backendSynced;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: purchase reconciliation failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'We could not confirm your purchases with our server. '
          'Your purchase is safe — please try Restore Purchase again.';
      return false;
    }
  }

  Future<bool> _syncBackendAccess({String? examId, String? productId}) async {
    _lastBackendSyncData = null;
    final requiresPurchaseConfirmation = productId?.trim().isNotEmpty == true;
    final maxAttempts = requiresPurchaseConfirmation ? 4 : 1;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _apiService.syncRevenueCatAccess(
          examId: examId,
          productId: productId,
        );
        final confirmed =
            response.success &&
            revenueCatSyncConfirmsProduct(
              productId: productId,
              examId: examId,
              data: response.data,
            );
        if (confirmed) {
          _lastBackendSyncData = response.data;
          return true;
        }
        debugPrint(
          'RevenueCat: backend sync not confirmed '
          'attempt=$attempt/$maxAttempts product=$productId '
          'status=${response.statusCode} message=${response.message}',
        );
        if (response.statusCode == 400 ||
            response.statusCode == 401 ||
            response.statusCode == 403) {
          break;
        }
      } catch (e) {
        debugPrint(
          'RevenueCat: backend access sync failed '
          'attempt=$attempt/$maxAttempts: $e',
        );
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    errorMessage.value =
        'Payment went through, but unlocking is taking longer than usual. '
        'Your purchase is safe — tap Restore Purchase in a moment.';
    return false;
  }

  Future<bool> _recordCustomerCenterRefundRequest({
    required String productId,
    required String status,
  }) async {
    if (!refundRequestWasSubmitted(status)) return false;
    try {
      final response = await _apiService.recordRevenueCatRefundRequest(
        productId: productId,
        status: status,
      );
      if (!response.success) {
        errorMessage.value =
            'Your refund was submitted, but your access has not updated yet. '
            'Please pull down to refresh in a moment.';
        return false;
      }
      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshProfile();
      }
      return true;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: refund request sync failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Your refund was submitted, but your access has not updated yet. '
          'Please pull down to refresh in a moment.';
      return false;
    }
  }

  Future<void> resetRevenueCatUser() async {
    if (!_revenueCatConfigured) return;
    try {
      if (!await rc.Purchases.isAnonymous) {
        _latestCustomerInfo = await rc.Purchases.logOut();
      }
    } catch (e) {
      debugPrint('RevenueCat: logout failed: $e');
    }
  }

  Future<rc.CustomerInfo?> refreshCustomerInfo() async {
    if (!_revenueCatConfigured) return null;
    try {
      final customerInfo = await rc.Purchases.getCustomerInfo();
      _latestCustomerInfo = customerInfo;
      return customerInfo;
    } on PlatformException catch (e) {
      debugPrint('RevenueCat: customer info failed: ${e.message}');
      errorMessage.value =
          'Unable to refresh subscription status. Please try again.';
      return null;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: customer info failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to refresh subscription status. Please try again.';
      return null;
    }
  }

  /// Loads subscription data only for the authenticated backend user.
  /// This prevents the management UI from accidentally showing an anonymous
  /// RevenueCat customer's purchase history.
  Future<rc.CustomerInfo?> loadSubscriptionCustomerInfo() async {
    if (!_revenueCatConfigured) {
      errorMessage.value = 'Purchases are not configured for this app build.';
      return null;
    }

    final userId = (await _storageService.getUserId())?.trim() ?? '';
    if (userId.isEmpty) {
      errorMessage.value = 'Please log in again to manage your subscription.';
      return null;
    }

    try {
      rc.CustomerInfo customerInfo;
      if (await rc.Purchases.appUserID != userId) {
        customerInfo = (await rc.Purchases.logIn(userId)).customerInfo;
      } else {
        customerInfo = await rc.Purchases.getCustomerInfo();
      }

      if (await rc.Purchases.appUserID != userId) {
        errorMessage.value =
            'Your subscription account could not be linked. Please log in again.';
        return null;
      }

      _latestCustomerInfo = customerInfo;
      final backendSynced = await _syncBackendAccess();
      if (backendSynced && Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshProfile();
      }
      return customerInfo;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: subscription details failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to load subscription details. Please try again.';
      return null;
    }
  }

  Future<bool> openSubscriptionManagement() async {
    final customerInfo = await loadSubscriptionCustomerInfo();
    if (customerInfo == null) return false;
    return _openNativeSubscriptionManagement(customerInfo: customerInfo);
  }

  Future<rc.RefundRequestStatus?>
  requestProfessionalSubscriptionRefund() async {
    if (!Platform.isIOS) {
      errorMessage.value =
          'Refund requests are available here only for Apple subscriptions.';
      return null;
    }

    final customerInfo = await loadSubscriptionCustomerInfo();
    final entitlement =
        customerInfo?.entitlements.active[professionalEntitlementId];
    if (entitlement == null) {
      errorMessage.value = 'No active Professional subscription was found.';
      return null;
    }

    try {
      final status = await rc.Purchases.beginRefundRequestForEntitlement(
        entitlement,
      );
      if (status == rc.RefundRequestStatus.success) {
        await _recordCustomerCenterRefundRequest(
          productId: entitlement.productIdentifier,
          status: status.name,
        );
      }
      return status;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: subscription refund request failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to start the refund request. Please try again.';
      return null;
    }
  }

  Future<bool> presentProfessionalPaywall({required String examId}) async {
    if (!_revenueCatConfigured) {
      errorMessage.value = 'Purchases are not configured for this app build.';
      return false;
    }

    _clearMessages();
    try {
      await identifyCurrentUser();
      _offerings ??= await rc.Purchases.getOfferings();
      final offering = _offerings?.current;
      if (offering == null || offering.availablePackages.isEmpty) {
        errorMessage.value =
            'No current RevenueCat offering is configured. Add products and packages in the RevenueCat dashboard.';
        return false;
      }

      final result = await rc_ui.RevenueCatUI.presentPaywallIfNeeded(
        professionalEntitlementId,
        offering: offering,
        displayCloseButton: true,
      );
      final customerInfo = await refreshCustomerInfo();
      final hasAccess =
          customerInfo?.entitlements.active.containsKey(
            professionalEntitlementId,
          ) ??
          false;

      switch (result) {
        case rc_ui.PaywallResult.purchased:
        case rc_ui.PaywallResult.restored:
          if (!hasAccess) {
            errorMessage.value =
                'The purchase completed, but access is still syncing. Please refresh in a moment.';
            return false;
          }
          final backendSynced = await _syncBackendAccess(
            examId: examId,
            productId: professionalSubscriptionProductId,
          );
          if (backendSynced && Get.isRegistered<UserController>()) {
            await Get.find<UserController>().refreshProfile();
          }
          lastCompletedPurchase.value = IapCompletedPurchase(
            kind: IapPurchaseKind.professional,
            productId: professionalSubscriptionProductId,
            examId: examId,
            payload: <String, dynamic>{
              'provider': 'revenuecat',
              'appUserId': customerInfo?.originalAppUserId,
              'activeEntitlements': customerInfo?.entitlements.active.keys
                  .toList(growable: false),
              'backendSynced': backendSynced,
            },
          );
          return true;
        case rc_ui.PaywallResult.notPresented:
          return hasAccess;
        case rc_ui.PaywallResult.cancelled:
          errorMessage.value = 'Purchase cancelled.';
          return false;
        case rc_ui.PaywallResult.error:
          errorMessage.value =
              'The paywall could not complete the purchase. Please try again.';
          return false;
      }
    } on PlatformException catch (e) {
      debugPrint('RevenueCat: paywall failed: ${e.message}');
      errorMessage.value = 'Unable to open the subscription paywall.';
      return false;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: paywall failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value = 'Unable to open the subscription paywall.';
      return false;
    }
  }

  Future<bool> presentCustomerCenter() async {
    if (!_revenueCatConfigured) {
      errorMessage.value = 'Purchases are not configured for this app build.';
      return false;
    }

    _clearMessages();
    try {
      await identifyCurrentUser();
      await rc_ui.RevenueCatUI.presentCustomerCenter(
        onRestoreCompleted: (customerInfo) {
          _latestCustomerInfo = customerInfo;
        },
        onRestoreFailed: (error) {
          debugPrint('RevenueCat: Customer Center restore failed: $error');
          errorMessage.value = 'Restore failed. Please try again.';
        },
        onRefundRequestCompleted: (productId, status) {
          if (!refundRequestWasSubmitted(status)) return;
          _refundRequestUpdateInFlight = _recordCustomerCenterRefundRequest(
            productId: productId,
            status: status,
          );
        },
      );
      final refundUpdate = _refundRequestUpdateInFlight;
      _refundRequestUpdateInFlight = null;
      if (refundUpdate != null) await refundUpdate;
      return reconcilePurchases();
    } on PlatformException catch (e) {
      debugPrint('RevenueCat: Customer Center failed: ${e.message}');
      return _openNativeSubscriptionManagement();
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: Customer Center failed: $e');
      debugPrint('$stackTrace');
      return _openNativeSubscriptionManagement();
    }
  }

  Future<bool> _openNativeSubscriptionManagement({
    rc.CustomerInfo? customerInfo,
  }) async {
    try {
      final resolvedCustomerInfo =
          customerInfo ??
          _latestCustomerInfo ??
          await rc.Purchases.getCustomerInfo();
      final managementUrl = resolvedCustomerInfo.managementURL?.trim() ?? '';
      final uri = Uri.tryParse(managementUrl);
      if (uri == null || !uri.hasScheme) {
        errorMessage.value =
            'Subscription management is unavailable for this purchase.';
        return false;
      }

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        errorMessage.value =
            'Unable to open subscription management. Please try again.';
      }
      return opened;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: native subscription management failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to open subscription management. Please try again.';
      return false;
    }
  }
}
