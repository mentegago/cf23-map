import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'analytics_service.dart';

Future<bool> copyForAnalytics(String text, AnalyticsService analytics) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    analytics.failure(Operation.clipboard, FailureCode.unavailable);
    return false;
  }
}

Future<void> launchForAnalytics(
    Uri uri, AnalyticsService analytics, CreatorAction action,
    {int? creatorId}) async {
  bool success;
  try {
    success = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    success = false;
  }
  analytics.creatorAction(action, creatorId: creatorId, success: success);
  if (!success) {
    analytics.failure(Operation.linkLaunch, FailureCode.launchRejected);
  }
}
