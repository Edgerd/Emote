// 性能基线快照测试：在真实 Linux 设备上测量「启动到首帧」与「greet FFI 1000 次耗时」。
// 由 scripts/perf_snapshot.sh 通过 `flutter test integration_test/perf_bench_test.dart -d linux`
// 在 xvfb 虚拟显示器下驱动，并解析其输出的 PERF_* 指标。
// ignore_for_file: avoid_print  // 基准测试需向 stdout 输出机器可解析的指标
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:emote/main.dart' as app;
import 'package:emote/src/rust/api/simple.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('perf baseline: launch-to-first-frame + greet FFI x1000', (tester) async {
    // 从应用真正启动前开始计时，度量到首帧完成
    final sw = Stopwatch()..start();
    await app.main();

    final firstFrame = binding.firstFrameRasterized;
    // ignore: await_only_futures // 在某些版本解析为 bool；运行时语义正确
    await firstFrame;
    // 首帧已栅格化，记录耗时
    final firstFrameMs = sw.elapsedMicroseconds / 1000.0;
    print('PERF_LAUNCH_TO_FIRST_FRAME_MS=${firstFrameMs.toStringAsFixed(1)}');

    // 等待 UI 进入空闲后再做 FFI 基准，避免与首帧渲染竞争
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const n = 1000;
    final times = <int>[];
    for (var i = 0; i < n; i++) {
      final t = Stopwatch()..start();
      await greet(name: 'emote');
      times.add(t.elapsedMicroseconds);
    }
    times.sort();
    double p50 = times[(n ~/ 2)].toDouble() / 1000.0;
    double p90 = times[(n * 9 ~/ 10)].toDouble() / 1000.0;
    double p95 = times[(n * 95 ~/ 100)].toDouble() / 1000.0;
    final sum = times.fold<int>(0, (a, b) => a + b);
    final avgMs = sum / n / 1000.0;
    print('PERF_GREET_N=$n');
    print('PERF_GREET_AVG_MS=${avgMs.toStringAsFixed(3)}');
    print('PERF_GREET_P50_MS=${p50.toStringAsFixed(3)}');
    print('PERF_GREET_P90_MS=${p90.toStringAsFixed(3)}');
    print('PERF_GREET_P95_MS=${p95.toStringAsFixed(3)}');
  });
}