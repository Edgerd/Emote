import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';

/// M3E 动效：封装 spring 弹簧参数与标准曲线。
class M3EMotion {
  M3EMotion._();

  // ---- spring 弹簧参数（具体数值，锁定实现）----
  static const double springStiffness = 200;
  static const double springDamping = 20;
  static const double springMass = 1;

  // ---- 时长（ms）----
  static const Duration durationShort = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);

  /// M3 标准 ease 曲线（用于非 spring 的淡入/位移）。
  static const Curve standardCurve = Curves.easeInOutCubicEmphasized;

  /// 由锁定参数构造解剖 spring。
  static SpringDescription spring({
    double stiffness = springStiffness,
    double damping = springDamping,
    double mass = springMass,
  }) =>
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping);

  /// 弹簧位移动画（overshoot），用于卡片/按钮出现。
  static Animatable<double> springScale({
    double from = 0.9,
    double to = 1.0,
  }) {
    const curve = Curves.easeOutBack;
    final tween = Tween<double>(begin: from, end: to);
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: tween.chain(CurveTween(curve: curve)),
        weight: 60,
      ),
      TweenSequenceItem(tween: ConstantTween(to), weight: 40),
    ]);
  }
}