import 'package:ej_flutter/models/api_response.dart';
import 'package:ej_flutter/services/api_service.dart';
import 'package:ej_flutter/services/user_service.dart';
import 'package:ej_flutter/utils/api_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiService extends ApiService {
  String? deletedEndpoint;

  @override
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic)? fromJson,
    bool allowRefresh = true,
  }) async {
    deletedEndpoint = endpoint;
    return ApiResponse<T>(success: true, message: 'Deleted');
  }
}

void main() {
  test(
    'deleteAccount calls the authenticated profile deletion endpoint',
    () async {
      final apiService = _FakeApiService();
      final userService = UserService(apiService: apiService);

      final response = await userService.deleteAccount();

      expect(response.success, isTrue);
      expect(apiService.deletedEndpoint, ApiEndpoints.deleteAccount);
    },
  );
}
