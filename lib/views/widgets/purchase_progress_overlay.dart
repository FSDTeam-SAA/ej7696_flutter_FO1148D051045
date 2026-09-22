import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/error/error_handler.dart';
import '../../services/iap_service.dart';

/// Blocks the whole app with a spinner while a store purchase is running, and
/// reports how it ended once it finishes.
///
/// Mounted once above every route (see `MaterialApp.builder`), so every screen
/// that starts a purchase gets the same behaviour without wiring it itself.
class PurchaseProgressOverlay extends StatefulWidget {
  const PurchaseProgressOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<PurchaseProgressOverlay> createState() =>
      _PurchaseProgressOverlayState();
}

class _PurchaseProgressOverlayState extends State<PurchaseProgressOverlay> {
  final List<Worker> _workers = <Worker>[];
  IapService? _iapService;
  bool _wasBusy = false;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<IapService>()) return;
    final iapService = Get.find<IapService>();
    _iapService = iapService;
    _workers
      ..add(ever<Set<String>>(iapService.inFlightProductIds, (_) => _onChange()))
      ..add(ever<int>(iapService.finishingPurchaseCount, (_) => _onChange()));
  }

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.dispose();
  }

  void _onChange() {
    final iapService = _iapService;
    if (iapService == null) return;
    final busy = iapService.isPurchaseBusy;
    if (_wasBusy && !busy) _reportOutcome(iapService);
    _wasBusy = busy;
  }

  /// A normal success already lands on the success screen and a user cancel
  /// is not worth a message, so only failures and recovered purchases are
  /// announced here.
  void _reportOutcome(IapService iapService) {
    final error = iapService.errorMessage.value;
    final success = iapService.successMessage.value;
    if (error.isEmpty && success.isEmpty) return;
    ErrorHandler.showSnackBar(
      error.isNotEmpty ? error : success,
      isError: error.isNotEmpty,
      context: context,
    );
    // The snackbar is the report; clearing stops screens with an inline
    // status line from repeating the same text underneath it.
    iapService.clearStatusMessages();
  }

  @override
  Widget build(BuildContext context) {
    final iapService = _iapService;
    if (iapService == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Obx(() {
            if (!iapService.isPurchaseBusy) {
              return const IgnorePointer(child: SizedBox.shrink());
            }
            final stage = iapService.isFinishingPurchase
                ? 'Finishing up...'
                : iapService.purchaseStage.value;
            return _ProgressBarrier(stage: stage);
          }),
        ),
      ],
    );
  }
}

class _ProgressBarrier extends StatelessWidget {
  const _ProgressBarrier({required this.stage});

  final String stage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF184A99),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                stage.isEmpty ? 'Processing your purchase...' : stage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please keep the app open.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
