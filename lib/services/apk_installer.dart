import 'dart:io';

import 'package:flutter/services.dart';

import '../app_info.dart';

/// Thin bridge to the Android package installer.
///
/// Disabled on Google Play builds ([AppInfo.enableSelfUpdate] is false by
/// default) because Play rejects `REQUEST_INSTALL_PACKAGES`. Direct GitHub
/// sideload builds can opt in via `--dart-define=ENABLE_SELF_UPDATE=true`.
class ApkInstaller {
  ApkInstaller._();

  static const _channel = MethodChannel('photospot/updates');

  static bool get isSupported =>
      AppInfo.enableSelfUpdate && Platform.isAndroid;

  /// Whether the user has allowed PhotoSpot to install apps. Returns true on
  /// platforms without that restriction so callers need no special casing.
  static Future<bool> canInstall() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system toggle for "install unknown apps" and returns whether the
  /// permission is already granted, so the caller can retry straight away.
  static Future<bool> requestInstallPermission() async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
    return canInstall();
  }

  /// Starts the system installer for [apkPath]. Returns false when the intent
  /// could not be launched, for example when the permission is still missing.
  static Future<bool> install(String apkPath) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'installApk',
        {'path': apkPath},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
