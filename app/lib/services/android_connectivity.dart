import 'dart:io';

import 'package:flutter/services.dart';

/// Android 组播/网络能力助手（第 2.7 段）。
///
/// 封装 Android 原生 `MainActivity` 通过 MethodChannel 暴露的
/// `MulticastLock` 获取/释放与网络状态查询。非 Android 平台一律返回
/// 安全默认值（true / 不操作），无需调用方做平台分支。
class AndroidConnectivity {
  AndroidConnectivity._();

  static const MethodChannel _channel =
      MethodChannel('com.emote/app/connectivity');

  static bool get _isAndroid => Platform.isAndroid;

  /// 获取 Wi-Fi MulticastLock（mDNS 接收组播包所需）。
  /// 返回是否已持有（非 Android 平台直接返回 true）。
  static Future<bool> acquireMulticastLock() async {
    if (!_isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('connectivity#acquireMulticast');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 释放已持有的 MulticastLock（非 Android 平台为 no-op）。
  static Future<void> releaseMulticastLock() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('connectivity#releaseMulticast');
    } catch (_) {
      // 静默：全局锁不参与核心逻辑，失败不影响功能。
    }
  }

  /// 当前是否已连接 Wi-Fi（用于 mDNS 可用性提示）。
  static Future<bool> isWifiConnected() async {
    if (!_isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('connectivity#isWifiConnected');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 屏幕是否处于点亮/互动状态。
  static Future<bool> isInteractive() async {
    if (!_isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('connectivity#isInteractive');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }
}