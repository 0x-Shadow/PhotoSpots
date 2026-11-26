import 'dart:io';

import 'package:flutter/services.dart';

/// Thin bridge to the Android package installer.
///
/// Android is the only platform where an app may install its own update, so on
/// everything else [isSupported] is false and callers fall back to the release
/// page.
class ApkInstaller {
  ApkInstaller._();

  static const _channel = MethodChannel('photospot/updates');

  static bool get isSupported => Platform.isAndroid;

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
