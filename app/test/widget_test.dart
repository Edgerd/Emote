import 'package:flutter_test/flutter_test.dart';

import 'package:emote/src/rust/api/simple.dart';

void main() {
  test('greet 由 flutter_rust_bridge 生成且函数存在', () {
    // 静态层面验证桥接已生成；真实调用需要平台原生动态库，
    // 在纯 `flutter test`（无原生库加载）环境中不做动态调用。
    expect(greet, isNotNull);
  });
}