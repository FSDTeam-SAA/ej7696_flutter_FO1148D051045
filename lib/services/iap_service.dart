import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart' as rc_ui;

import '../controllers/user_controller.dart';
import '../models/payment_success_details.dart';
import 'exam_service.dart';
import 'storage_service.dart';

const Map<String, String> examIapProductIds = {
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

const String professionalSubscriptionProductId = 'six_month_subscriptions';
const String professionalEntitlementId = 'professional_access';

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
  );
  static const String _revenueCatAppleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
  );

  final ExamService _examService = ExamService();
  final StorageService _storageService = StorageService();

  final Map<String, _PendingIapIntent> _pendingIntents = {};
  final Map<String, rc.StoreProduct> _revenueCatProducts = {};
  final Map<String, rc.Package> _revenueCatPackages = {};
  rc.Offerings? _offerings;
  rc.CustomerInfo? _latestCustomerInfo;
  bool _revenueCatConfigured = false;
  late final rc.CustomerInfoUpdateListener _customerInfoListener =
      _handleRevenueCatCustomerInfo;

  final RxBool isStoreAvailable = false.obs;
  final RxBool isLoadingProducts = false.obs;
  final RxBool isRestoring = false.obs;
  final RxString errorMessage = ''.obs;
  final RxSet<String> missingProductIds = <String>{}.obs;
  final RxSet<String> inFlightProductIds = <String>{}.obs;
  final Rx<IapCompletedPurchase?> lastCompletedPurchase =
      Rx<IapCompletedPurchase?>(null);

  bool get isMobileStore => Platform.isIOS || Platform.isAndroid;
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
    ...examIapProductIds.values,
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
    final productId = code == null ? null : examIapProductIds[code];
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
        : examIapProductIds[resolvedCode];
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

  Future<bool> buyProfessionalSubscription({String? selectedExamId}) async {
    if (!isMobileStore) return false;
    return presentProfessionalPaywall(selectedExamId: selectedExamId);
  }

  Future<void> restorePurchases() async {
    if (!isMobileStore) return;
    if (isRestoring.value) return;
    isRestoring.value = true;
    errorMessage.value = '';
    debugPrint('IAP: restore started.');
    try {
      if (!_revenueCatConfigured) {
        errorMessage.value = 'Purchases are not configured for this app build.';
        return;
      }
      await identifyCurrentUser();
      final customerInfo = await rc.Purchases.restorePurchases();
      await _applyRevenueCatAccess(customerInfo);
      errorMessage.value = 'Purchases restored successfully.';
    } catch (e, stackTrace) {
      debugPrint('IAP: restore failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value = 'Restore failed. Please try again.';
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
      final alreadyConfigured = await rc.Purchases.isConfigured;
      if (!alreadyConfigured) {
        final userId = (await _storageService.getUserId())?.trim();
        final configuration = rc.PurchasesConfiguration(apiKey)
          ..appUserID = userId == null || userId.isEmpty ? null : userId
          ..diagnosticsEnabled = kDebugMode;
        await rc.Purchases.configure(configuration);
      }
      _revenueCatConfigured = true;
      rc.Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
      await identifyCurrentUser();
      await refreshCustomerInfo();
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
    errorMessage.value = '';
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
        subscriptionProducts = await rc.Purchases.getProducts(const <String>[
          professionalSubscriptionProductId,
        ], productCategory: rc.ProductCategory.subscription);
      }
      final examProducts = await rc.Purchases.getProducts(
        examIapProductIds.values.toList(growable: false),
        productCategory: rc.ProductCategory.nonSubscription,
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
    errorMessage.value = '';
    try {
      await identifyCurrentUser();
      final package = _revenueCatPackages[productId];
      final purchaseParams = package == null
          ? rc.PurchaseParams.storeProduct(product)
          : rc.PurchaseParams.package(package);
      final result = await rc.Purchases.purchase(purchaseParams);
      await _deliverRevenueCatPurchase(intent, product, result);
      return true;
    } on PlatformException catch (e) {
      final code = rc.PurchasesErrorHelper.getErrorCode(e);
      switch (code) {
        case rc.PurchasesErrorCode.purchaseCancelledError:
          errorMessage.value = 'Purchase cancelled.';
          break;
        case rc.PurchasesErrorCode.paymentPendingError:
          errorMessage.value = 'Purchase is pending.';
          break;
        case rc.PurchasesErrorCode.productAlreadyPurchasedError:
          final customerInfo = await rc.Purchases.restorePurchases();
          await _applyRevenueCatAccess(customerInfo);
          errorMessage.value = 'Purchase already owned and restored.';
          break;
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

  Future<void> _deliverRevenueCatPurchase(
    _PendingIapIntent intent,
    rc.StoreProduct product,
    rc.PurchaseResult result,
  ) async {
    _latestCustomerInfo = result.customerInfo;
    final userController = Get.isRegistered<UserController>()
        ? Get.find<UserController>()
        : null;
    if (userController != null) {
      if (intent.kind == IapPurchaseKind.professional) {
        await userController.applyProfessionalUpgrade(examId: intent.examId);
      } else if (intent.examId != null && intent.examId!.isNotEmpty) {
        await userController.addUnlockedExamId(intent.examId!);
      }
    }

    final transactionId = result.storeTransaction.transactionIdentifier;
    final payload = <String, dynamic>{
      'provider': 'revenuecat',
      'store': Platform.isIOS ? 'app_store' : 'google_play',
      'productId': product.identifier,
      'transactionId': transactionId,
      'appUserId': result.customerInfo.originalAppUserId,
      'activeEntitlements': result.customerInfo.entitlements.active.keys.toList(
        growable: false,
      ),
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
        paymentMethodLabel: Platform.isIOS
            ? 'Apple In-App Purchase'
            : 'Google Play In-App Purchase',
        receiptNumber: transactionId,
        transactionReference: transactionId,
        paidAt: DateTime.tryParse(result.storeTransaction.purchaseDate),
        provider: Platform.isIOS ? 'apple' : 'google',
        status: 'successful',
      ),
    );
  }

  void _handleRevenueCatCustomerInfo(rc.CustomerInfo customerInfo) {
    _latestCustomerInfo = customerInfo;
    unawaited(_applyRevenueCatAccess(customerInfo));
  }

  Future<void> _applyRevenueCatAccess(rc.CustomerInfo customerInfo) async {
    _latestCustomerInfo = customerInfo;
    if (!Get.isRegistered<UserController>()) return;
    final userController = Get.find<UserController>();
    if (customerInfo.activeSubscriptions.contains(
          professionalSubscriptionProductId,
        ) ||
        customerInfo.entitlements.active.containsKey(
          professionalEntitlementId,
        )) {
      await userController.applyProfessionalUpgrade();
    }

    for (final entry in examIapProductIds.entries) {
      final productOwned = customerInfo.allPurchasedProductIdentifiers.contains(
        entry.value,
      );
      final entitlementOwned = customerInfo.entitlements.active.containsKey(
        'exam_${entry.key.toLowerCase().replaceFirst('api_', '')}',
      );
      if (!productOwned && !entitlementOwned) continue;
      final examId = await _resolveExamIdForCode(entry.key);
      if (examId != null) {
        await userController.addUnlockedExamId(examId);
      }
    }
  }

  Future<void> identifyCurrentUser() async {
    if (!_revenueCatConfigured) return;
    final userId = (await _storageService.getUserId())?.trim() ?? '';
    if (userId.isEmpty) return;
    try {
      if (await rc.Purchases.appUserID != userId) {
        final result = await rc.Purchases.logIn(userId);
        _latestCustomerInfo = result.customerInfo;
        await _applyRevenueCatAccess(result.customerInfo);
      }
    } catch (e) {
      debugPrint('RevenueCat: failed to identify user: $e');
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
      await _applyRevenueCatAccess(customerInfo);
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

  Future<bool> presentProfessionalPaywall({String? selectedExamId}) async {
    if (!_revenueCatConfigured) {
      errorMessage.value = 'Purchases are not configured for this app build.';
      return false;
    }

    errorMessage.value = '';
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
          if (Get.isRegistered<UserController>()) {
            await Get.find<UserController>().applyProfessionalUpgrade(
              examId: selectedExamId,
            );
          }
          lastCompletedPurchase.value = IapCompletedPurchase(
            kind: IapPurchaseKind.professional,
            productId: professionalSubscriptionProductId,
            examId: selectedExamId,
            payload: <String, dynamic>{
              'provider': 'revenuecat',
              'appUserId': customerInfo?.originalAppUserId,
              'activeEntitlements': customerInfo?.entitlements.active.keys
                  .toList(growable: false),
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

    errorMessage.value = '';
    try {
      await identifyCurrentUser();
      await rc_ui.RevenueCatUI.presentCustomerCenter(
        onRestoreCompleted: (customerInfo) {
          unawaited(_applyRevenueCatAccess(customerInfo));
        },
        onRestoreFailed: (error) {
          debugPrint('RevenueCat: Customer Center restore failed: $error');
          errorMessage.value = 'Restore failed. Please try again.';
        },
      );
      await refreshCustomerInfo();
      return true;
    } on PlatformException catch (e) {
      debugPrint('RevenueCat: Customer Center failed: ${e.message}');
      errorMessage.value =
          'Unable to open subscription management. Please try again.';
      return false;
    } catch (e, stackTrace) {
      debugPrint('RevenueCat: Customer Center failed: $e');
      debugPrint('$stackTrace');
      errorMessage.value =
          'Unable to open subscription management. Please try again.';
      return false;
    }
  }

  Future<String?> _resolveExamIdForCode(String? examCode) async {
    if (examCode == null || examCode.isEmpty) return null;
    final response = await _examService.getActiveExams();
    if (!response.success) {
      debugPrint('IAP: unable to load exams for restore: ${response.message}');
      return null;
    }
    for (final exam in response.data ?? const []) {
      final resolved = resolveExamCode(code: exam.code, name: exam.name);
      if (resolved == examCode) return exam.id;
    }
    debugPrint('IAP: no exam found for restored product code $examCode');
    return null;
  }
}
