import 'package:flutter/material.dart';

import 'package:emote/src/rust/api/simple.dart';

import '../theme/app_theme.dart';

/// 静态占位首页：居中显示“设备发现中…”，下方展示第1.3段 Rust `greet` 的返回。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(spacingX3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 发现中指示器
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(spacingX3),
                  child: Icon(
                    Icons.radar,
                    size: 56,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              SizedBox(height: spacingX3),
              Text('设备发现中…', style: textTheme.headlineMedium),
              SizedBox(height: spacingX1),
              Text(
                '正在扫描局域网内的可用设备，请稍候。',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacingX4),

              // Rust greet 返回字符串
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(spacingX3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GreetText(),
                      SizedBox(height: spacingX2),
                      FilledButton.icon(
                        onPressed: () {
                          // 占位：触发重新扫描设备。
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新扫描'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 以 Future 方式读取 Rust `greet` 并渲染其返回字符串。
class _GreetText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: greet(name: 'Emote'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Rust 桥接错误：${snapshot.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return Text(
          snapshot.data!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        );
      },
    );
  }
}