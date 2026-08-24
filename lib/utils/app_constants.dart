import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // App Info
  static const String appName = "Inspector's Path";
  static const String appVersion = '1.0.0';
  static const String privacyPolicyUrl =
      'https://inspectorspath.com/privacy-policy/';
  static const String termsOfUseUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  // API Constants
//   static const String apiOrigin = 'https://api.inspectorspath.com';

  /// Port the local backend listens on (Back_end-ej7696 `.env` -> PORT).
  static const int localApiPort = 5001;

  /// Overrides everything below. Use for a deployed environment, or when this
  /// Mac's Wi-Fi address differs from [_devHostLanIp]:
  ///   flutter run --dart-define=API_ORIGIN=http://192.168.10.116:5001
  static const String _apiOriginOverride = String.fromEnvironment('API_ORIGIN');

  /// This Mac's Wi-Fi (en1) address, used by real devices on the same network.
  /// Update it when you move to a different Wi-Fi, or pass API_ORIGIN instead.
  static const String _devHostLanIp = '192.168.10.116';

  /// A real phone must reach the dev machine by its LAN address: `localhost`
  /// resolves to the phone itself, and an Android emulator reserves 10.0.2.2
  /// for the host. Only simulators, macOS and web share the host's loopback.
  static String _resolveApiOrigin() {
    if (_apiOriginOverride.isNotEmpty) return _apiOriginOverride;
    if (kIsWeb) return 'http://localhost:$localApiPort';
    if (Platform.isAndroid) {
      return _isAndroidEmulator
          ? 'http://10.0.2.2:$localApiPort'
          : 'http://$_devHostLanIp:$localApiPort';
    }
    if (Platform.isIOS) {
      return _isIosSimulator
          ? 'http://localhost:$localApiPort'
          : 'http://$_devHostLanIp:$localApiPort';
    }
    return 'http://localhost:$localApiPort';
  }

  /// The iOS simulator is the only iOS target that sets these Xcode variables.
  static bool get _isIosSimulator =>
      Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
      Platform.environment.containsKey('SIMULATOR_UDID');

  /// The Android emulator exposes its Goldfish/Ranchu qemu pipe; phones do not.
  static bool get _isAndroidEmulator =>
      Directory('/dev/socket/qemud').existsSync() ||
      File('/dev/qemu_pipe').existsSync();

  static final String apiOrigin = _resolveApiOrigin();
  static final String baseUrl = '$apiOrigin/api/v1';
  static final String publicBaseUrl = apiOrigin;
  static const Duration apiTimeout = Duration(seconds: 30);

  // Feature Flags
  static const bool resourcesEnabled = false;

  // null = no timeout (wait indefinitely).
  static const Duration? examGenerationTimeout = null;
  static const String appLinkScheme = 'ejflutter';
  static const String sharedEbookPath = '/shared-ebook';
  static const String sharedReferralPath = '/shared-referral';

  // Stripe (use env or build config in production)
  static const String stripePublishableKey =
      'pk_test_51S6pMbRZVOYD6qjBukBi2VyPiTtIhzAyYzmfyAo4izzIwemOo7I3fUYELhxmTJeNln7zMiztFA4CKihsybqrJlo800nWzvIXZY';

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String installationIdSecureKey = 'installation_id';
  static const String installationBootstrapKey = 'installation_bootstrapped';
  static const String installationIdHeaderKey = 'X-App-Installation-Id';
  static const String isLoggedInKey = 'is_logged_in';
  static const String userDataKey = 'user_data';
  static const String userRoleKey = 'user_role';
  static const String unlockedExamIdsKey = 'unlocked_exam_ids';
  static const String pendingReferralCodeKey = 'pending_referral_code';
  static const String pendingReferralProductIdKey =
      'pending_referral_product_id';
  static const String voicePracticeDisclaimerAcceptedKey =
      'voice_practice_disclaimer_accepted';
  static const String rememberMeKey = 'remember_me';
  static const String rememberedEmailKey = 'remembered_email';
  static const String rememberedPasswordKey = 'remembered_password';

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Validation
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 50;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 30;

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 400);
  static const Duration longAnimation = Duration(milliseconds: 600);
}
