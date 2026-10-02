import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 用 [RawImage] 直接渲染 RGBA8 帧画面（不依赖图片解码，桌面 / Android 通用）。
///
/// 第 3.10 段渲染层：把远控会话产出的 `VideoFrame`（RGBA8）经
/// [ui.decodeImageFromPixels] 解码为 [ui.Image] 后送入 [RawImage] 显示。
/// 数据无效时返回 `SizedBox.shrink()`，不抛异常。
class RemoteView extends StatefulWidget {
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
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant RemoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _decode();
    }
  }

  void _decode() {
    final w = widget.width;
    final h = widget.height;
    final bytes = widget.bytes;
    if (w <= 0 || h <= 0 || bytes.length < w * h * 4) {
      if (_image != null) {
        _image = null;
      }
      return;
    }
    // RGBA8888 原始像素 → ui.Image；回调可能在当前或后续帧触发，需判 mounted。
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, (img) {
      if (!mounted) {
        return;
      }
      setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: img.width / img.height,
      child: RawImage(image: img, fit: BoxFit.contain),
    );
  }
}
