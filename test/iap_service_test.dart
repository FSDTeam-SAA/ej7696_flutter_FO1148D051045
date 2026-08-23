import 'package:ej_flutter/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ownedExamCodes', () {
    test('builds the configured store product IDs', () {
      expect(
        examSubscriptionProductId('API_1184', isAndroid: true),
        'com.inspectorspath.exam.api1184.sixmonth:api1184sixmonth',
      );
      expect(
        examSubscriptionProductId('API_SIRE', isAndroid: true),
        'com.inspectorspath.exam.sire.sixmonth:siresixmonth',
      );
      expect(
        examSubscriptionProductId('API_1184', isAndroid: false),
        'com.inspectorspath.exam.api1184.sixmonth',
      );
    });

    test('maps Android prepaid products to exam codes', () {
      final result = ownedExamCodes(
        purchasedProductIds: const <String>{
          'com.inspectorspath.exam.api1184.sixmonth:api1184sixmonth',
          'com.inspectorspath.exam.sire.sixmonth:siresixmonth',
        },
        activeEntitlementIds: const <String>{},
      );

      expect(result, equals(<String>{'API_1184', 'API_SIRE'}));
    });

    test('maps purchased non-subscription products to exam codes', () {
      final result = ownedExamCodes(
        purchasedProductIds: const <String>{
          'com.inspectorspath.exam.api570.unlock',
          'com.inspectorspath.exam.api653.unlock',
          'com.inspectorspath.exam.sife.unlock',
          'com.inspectorspath.exam.api1169.unlock',
          'unrelated.product',
        },
        activeEntitlementIds: const <String>{},
      );

      expect(
        result,
        equals(<String>{'API_570', 'API_653', 'API_SIFE', 'API_1169'}),
      );
    });

    test('also accepts per-exam RevenueCat entitlements', () {
      final result = ownedExamCodes(
        purchasedProductIds: const <String>{},
        activeEntitlementIds: const <String>{'exam_570', 'exam_sire'},
      );

      expect(result, equals(<String>{'API_570', 'API_SIRE'}));
    });

    test('ignores the professional subscription entitlement', () {
      final result = ownedExamCodes(
        purchasedProductIds: const <String>{
          'six_month_subscriptions:six-month',
        },
        activeEntitlementIds: const <String>{'professional_access'},
      );

      expect(result, isEmpty);
    });
  });

  group('refundRequestWasSubmitted', () {
    test('accepts only RevenueCat success status', () {
      expect(refundRequestWasSubmitted('success'), isTrue);
      expect(refundRequestWasSubmitted(' SUCCESS '), isTrue);
      expect(refundRequestWasSubmitted('userCancelled'), isFalse);
      expect(refundRequestWasSubmitted('error'), isFalse);
    });
  });

  group('mobileCheckoutRequirements', () {
    test('first purchase requires one subscription approval only', () {
      final result = mobileCheckoutRequirements(
        isProfessionalActive: false,
        examOwned: false,
      );

      expect(result.subscriptionRequired, isTrue);
      expect(result.examPurchaseRequired, isFalse);
    });

    test(
      'initial purchase includes the selected exam even if it was owned',
      () {
        final result = mobileCheckoutRequirements(
          isProfessionalActive: false,
          examOwned: true,
        );

        expect(result.subscriptionRequired, isTrue);
        expect(result.examPurchaseRequired, isFalse);
      },
    );

    test('active subscribers only purchase a new exam', () {
      final result = mobileCheckoutRequirements(
        isProfessionalActive: true,
        examOwned: false,
      );

      expect(result.subscriptionRequired, isFalse);
      expect(result.examPurchaseRequired, isTrue);
    });
  });

  group('revenueCatSyncConfirmsProduct', () {
    test('does not accept a successful HTTP response with Starter access', () {
      final confirmed = revenueCatSyncConfirmsProduct(
        productId: androidProfessionalSubscriptionProductId,
        examId: null,
        data: const <String, dynamic>{
          'subscriptionTier': 'starter',
          'hasProfessionalAccess': false,
          'subscriptionCount': 0,
        },
      );

      expect(confirmed, isFalse);
    });

    test('accepts a backend-confirmed initial subscription and exam', () {
      final confirmed = revenueCatSyncConfirmsProduct(
        productId: appleProfessionalSubscriptionProductId,
        examId: 'exam-1184',
        data: const <String, dynamic>{
          'subscriptionTier': 'professional',
          'hasProfessionalAccess': true,
          'subscriptionCount': 1,
          'selectedExam': <String, dynamic>{
            'examId': 'exam-1184',
            'unlocked': true,
          },
        },
      );

      expect(confirmed, isTrue);
    });

    test('requires the purchased product to unlock the selected exam', () {
      final confirmed = revenueCatSyncConfirmsProduct(
        productId: examIapProductIds['API_1184'],
        examId: 'exam-1184',
        data: const <String, dynamic>{
          'selectedExam': <String, dynamic>{
            'examId': 'exam-1184',
            'unlocked': true,
          },
          'syncedExamIds': <String>['exam-1184'],
        },
      );

      expect(confirmed, isTrue);
      expect(
        revenueCatSyncConfirmsProduct(
          productId: examIapProductIds['API_1184'],
          examId: 'different-exam',
          data: const <String, dynamic>{
            'selectedExam': <String, dynamic>{
              'examId': 'exam-1184',
              'unlocked': true,
            },
            'syncedExamIds': <String>['exam-1184'],
          },
        ),
        isFalse,
      );
    });

    test('accepts an Android exam product with its real base-plan ID', () {
      final confirmed = revenueCatSyncConfirmsProduct(
        productId: 'com.inspectorspath.exam.api510.sixmonth:api510sixmonth',
        examId: 'exam-510',
        data: const <String, dynamic>{
          'selectedExam': <String, dynamic>{
            'examId': 'exam-510',
            'unlocked': true,
          },
        },
      );

      expect(confirmed, isTrue);
    });

    test('rejects unknown store products', () {
      expect(
        revenueCatSyncConfirmsProduct(
          productId: 'unknown.product',
          examId: null,
          data: const <String, dynamic>{},
        ),
        isFalse,
      );
    });
  });

  group('revenueCatCustomerHasActiveProduct', () {
    test('accepts an active subscription product', () {
      expect(
        revenueCatCustomerHasActiveProduct(
          productId: appleProfessionalSubscriptionProductId,
          activeSubscriptionIds: const <String>{
            appleProfessionalSubscriptionProductId,
          },
          activeEntitlementProductIds: const <String>{},
        ),
        isTrue,
      );
    });

    test('accepts a product attached to an active entitlement', () {
      expect(
        revenueCatCustomerHasActiveProduct(
          productId: examIapProductIds['API_1184']!,
          activeSubscriptionIds: const <String>{},
          activeEntitlementProductIds: <String>{examIapProductIds['API_1184']!},
        ),
        isTrue,
      );
    });

    test('rejects inactive or unrelated products', () {
      expect(
        revenueCatCustomerHasActiveProduct(
          productId: appleProfessionalSubscriptionProductId,
          activeSubscriptionIds: const <String>{},
          activeEntitlementProductIds: const <String>{'unrelated.product'},
        ),
        isFalse,
      );
    });
  });
}
