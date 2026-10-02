import 'dart:typed_data';
import 'dart:ui' show ByteOrder, RawImage;

import 'package:flutter/material.dart';

/// 用 [RawImage] 直接渲染 RGBA8 帧画面（不依赖图片解码，桌面 / Android 通用）。
///
/// 第 3.10 段渲染层：把远控会话产出的 `VideoFrame`（RGBA8）送入 [RemoteView] 显示。
/// 数据无效时返回 `SizedBox.shrink()`，不抛异常。
class RemoteView extends StatelessWidget {
  const RemoteView({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// RGBA8 数据，长度应为 `width * height * 4`。
  final Uint8List bytes;
  final int width;
  final int height;

  @override
  Widget build(BuildContext context) {
    if (width <= 0 || height <= 0 || bytes.isEmpty) {
      return const SizedBox.shrink();
    }
    // `RawImage` 默认按 RGBA、row-major（首像素在最前）解释，`byteOrder` 用本机序。
    final image = RawImage(
      bytes: bytes,
      width: width,
      height: height,
      byteOrder: ByteOrder.native,
    );
    return AspectRatio(
      aspectRatio: width / height,
      child: Image(image: image, fit: BoxFit.contain),
    );
  }
}
