/// 超分方案的实现形态。
enum SuperResolutionKind {
  /// 不做任何超分
  off,

  /// Anime4K 系列 GLSL shader
  anime4k,

  /// 其他 GLSL shader（如 ArtCNN）
  shader,

  /// 只用 mpv 的缩放器（scale=...），不加载 shader
  scaler,
}

/// 超分档位。
///
/// 按内容类型分档：动画、3D/写实向、真人。storageValue 一旦发布不要改，
/// 因为用户设置里存的是这个数字。
enum SuperResolutionMode {
  off(
    storageValue: 1,
    label: '关闭',
    description: '不做超分',
    algorithm: '关闭',
    kind: SuperResolutionKind.off,
    factor: 1,
  ),
  efficiency(
    storageValue: 2,
    label: 'Anime4K Lite',
    description: 'Anime4K 轻量档：动画首选，开销低，线条干净',
    algorithm: 'Anime4K Lite',
    kind: SuperResolutionKind.anime4k,
    factor: 2,
  ),
  quality(
    storageValue: 3,
    label: 'Anime4K HQ',
    description: 'Anime4K 高质量档：动画画质优先，开销约为 Lite 的 3 倍',
    algorithm: 'Anime4K HQ',
    kind: SuperResolutionKind.anime4k,
    factor: 2,
  ),
  cg3d(
    storageValue: 4,
    label: 'ArtCNN C4F16',
    description: '通用卷积超分：适合 3D 国漫等写实向画面，不会把边缘锐成白边',
    algorithm: 'ArtCNN C4F16',
    kind: SuperResolutionKind.shader,
    factor: 2,
  ),
  liveAction(
    storageValue: 5,
    label: 'EWA Lanczos',
    description: '高质量插值：适合真人电影、纪录片，保留皮肤纹理与颗粒',
    algorithm: 'EWA Lanczos',
    kind: SuperResolutionKind.scaler,
    factor: 0,
  );

  const SuperResolutionMode({
    required this.storageValue,
    required this.label,
    required this.description,
    required this.algorithm,
    required this.kind,
    required this.factor,
  });

  final int storageValue;
  final String label;
  final String description;

  /// 浮层里显示的算法名。
  final String algorithm;

  final SuperResolutionKind kind;

  /// 名义放大倍数；0 表示交给缩放器按显示尺寸决定（读 dwidth/dheight）。
  final int factor;

  static SuperResolutionMode fromStorageValue(int value) {
    return SuperResolutionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => SuperResolutionMode.off,
    );
  }
}