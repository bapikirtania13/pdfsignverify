import 'dart:async';
import 'package:flutter/material.dart';

/// Centralized SnackBar helper ensuring popups only show for 1-2 seconds
/// and automatically dismiss even when SnackBarAction or accessibility services are active.
class AppSnackBar {
  static void show(
    BuildContext context, {
    String? message,
    Widget? content,
    Duration duration = const Duration(seconds: 2),
    Color? backgroundColor,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // 1. Clear any currently queued or active snackbars immediately
    messenger.clearSnackBars();

    // 2. Display the snackbar
    messenger.showSnackBar(
      SnackBar(
        content: content ?? Text(message ?? ''),
        duration: duration,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: action,
      ),
    );

    // 3. Guaranteed timer to auto-dismiss after the duration.
    // This is vital because Android accessibility services or SnackBarActions
    // can cause Flutter to keep SnackBars visible indefinitely.
    Timer(duration + const Duration(milliseconds: 100), () {
      try {
        messenger.hideCurrentSnackBar();
      } catch (_) {}
    });
  }
}
