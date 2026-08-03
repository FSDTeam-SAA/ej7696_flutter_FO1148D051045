import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/error/error_handler.dart';

Future<void> openLegalLink(
  BuildContext context,
  String url, {
  String? fallbackRoute,
}) async {
  final uri = Uri.parse(url);
  final openedInApp = await _tryLaunch(uri, LaunchMode.inAppBrowserView);
  if (openedInApp) return;

  final openedExternally = await _tryLaunch(
    uri,
    LaunchMode.externalApplication,
  );
  if (openedExternally) return;

  final openedDefault = await _tryLaunch(uri, LaunchMode.platformDefault);
  if (openedDefault) return;

  if (!context.mounted) return;
  if (fallbackRoute != null) {
    context.push(fallbackRoute);
    return;
  }

  ErrorHandler.showSnackBar(
    'Unable to open link. Please try again.',
    isError: true,
    context: context,
  );
}

Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
  try {
    return await launchUrl(uri, mode: mode);
  } catch (_) {
    return false;
  }
}
