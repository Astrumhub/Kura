import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:media_kit/media_kit.dart';

/// 播放统计浮层（自用）。
///
/// 三组信息：视频源 / 处理链路 / 运行状态。配色取自 Theme。
///
/// 说明：mpv 不暴露渲染器层的耗时（MPC VR 的 Copy/Paint/Present 是它自己的
/// Direct3D 计时），这里显示的是 Flutter 侧的 UI 帧耗时，标签写作「耗时(UI)」。
class PlayerStatsOverlay extends StatefulWidget {
  const PlayerStatsOverlay({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerStatsOverlay> createState() => _PlayerStatsOverlayState();
}

class _PlayerStatsOverlayState extends State<PlayerStatsOverlay> {
  static const List<String> _pollKeys = <String>[
    'container-fps',
    'estimated-vf-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'width',
    'height',
    'dwidth',
    'dheight',
    'video-codec',
    'track-list/0/codec',
    'video-params/pixelformat',
    'video-out-params/pixelformat',
    'video-params/colormatrix',
    'video-params/colorlevels',
    'hwdec-current',
    'current-vo',
    'video-bitrate',
    'audio-codec',
    'audio-params/samplerate',
    'audio-params/channel-count',
  ];

  final Map<String, String> _values = <String, String>{};
  Timer? _timer;
  double? _frameMs;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _timer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return;
    }
    var total = 0;
    for (final t in timings) {
      total += t.totalSpan.inMicroseconds;
    }
    final avg = total / timings.length / 1000.0;
    if (mounted && (_frameMs == null || (avg - _frameMs!).abs() > 0.05)) {
      setState(() => _frameMs = avg);
    }
  }

  Future<void> _refresh() async {
    final player = widget.controller.playback.mediaPlayer;
    if (player == null) {
      return;
    }
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    final next = <String, String>{};
    for (final key in _pollKeys) {
      try {
        next[key] = await platform.getProperty(key);
      } catch (_) {
        next[key] = '';
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _values
        ..clear()
        ..addAll(next);
    });
  }

  String _raw(String key) => (_values[key] ?? '').trim();

  String _value(String key, {String fallback = '—'}) {
    final value = _raw(key);
    return value.isEmpty ? fallback : value;
  }

  String _fps(String key) {
    final parsed = double.tryParse(_raw(key));
    return parsed == null ? '—' : parsed.toStringAsFixed(3);
  }

  String _resolution(String widthKey, String heightKey) {
    final w = _raw(widthKey);
    final h = _raw(heightKey);
    if (w.isEmpty || h.isEmpty) {
      return '—';
    }
    return '$w×$h';
  }

  String get _pixelFormat {
    final out = _raw('video-out-params/pixelformat');
    if (out.isNotEmpty && out != 'd3d11') {
      return out;
    }
    final src = _raw('video-params/pixelformat');
    return src.isEmpty ? '' : src;
  }

  String get _codecLine {
    final codec = _raw('video-codec').isNotEmpty
        ? _raw('video-codec')
        : _raw('track-list/0/codec');
    final fmt = _pixelFormat.toUpperCase();
    final parts = <String>[
      if (codec.isNotEmpty) codec.toUpperCase(),
      if (fmt.isNotEmpty) fmt,
    ];
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  String get _colorLine {
    final matrix = _raw('video-params/colormatrix');
    final levels = _raw('video-params/colorlevels');
    final range = switch (levels) {
      'limited' => '16-235',
      'full' => '0-255',
      _ => levels,
    };
    final parts = <String>[
      if (matrix.isNotEmpty) matrix.toUpperCase(),
      if (range.isNotEmpty) range,
    ];
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  String get _bitrateLine {
    final parsed = int.tryParse(_raw('video-bitrate'));
    if (parsed == null || parsed <= 0) {
      return '—';
    }
    return '${(parsed / 1000000).toStringAsFixed(2)} Mbps';
  }

  String get _audioLine {
    final codec = _raw('audio-codec');
    final channels = int.tryParse(_raw('audio-params/channel-count'));
    final sr = int.tryParse(_raw('audio-params/samplerate'));
    final channelText = switch (channels) {
      1 => '1.0ch',
      2 => '2.0ch',
      6 => '5.1ch',
      8 => '7.1ch',
      _ => null,
    };
    final parts = <String>[
      if (codec.isNotEmpty) codec.toUpperCase(),
      if (channelText != null) channelText,
      if (sr != null && sr > 0) '${(sr / 1000).toStringAsFixed(0)}kHz',
    ];
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  /// 超分算法名，由档位自带。
  String get _scaleAlgorithm =>
      widget.controller.playback.superResolutionMode.algorithm;

  /// 渲染尺寸：直接取 mpv 实测的 dwidth/dheight，不做任何倍率推算。
  String get _renderSize {
    final out = _resolution('dwidth', 'dheight');
    return out == '—' ? _resolution('width', 'height') : out;
  }

  String get _scaleLine =>
      '${_resolution('width', 'height')} -> $_renderSize · $_scaleAlgorithm';

  /// 帧率：源帧率与输出帧率都是 mpv 实时上报值。
  String get _fpsLine {
    final src = _fps('container-fps');
    final out = _fps('estimated-vf-fps');
    final on = widget.controller.playback.frameGenEnabled;
    return '$src -> $out · AMF ${on ? '开' : '关'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = fg.withValues(alpha: 0.62);
    final divider = scheme.outlineVariant.withValues(alpha: 0.5);
    final uiMs = _frameMs;

    return Container(
      width: 380,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 12, height: 1.55, color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '播放统计',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: fg,
              ),
            ),
            _section('视频源', divider, muted, [
              _row('编码', _codecLine, muted),
              _row('色彩', _colorLine, muted),
              _row('码率', _bitrateLine, muted),
              _row('音频', _audioLine, muted),
            ]),
            _section('处理链路', divider, muted, [
              _row('分辨率', _scaleLine, muted),
              _row('帧率', _fpsLine, muted, highlight: scheme.primary),
            ]),
            _section('运行状态', divider, muted, [
              _row('解码', _value('hwdec-current').toUpperCase(), muted),
              _row('渲染器', _value('current-vo'), muted),
              _row(
                '耗时(UI)',
                uiMs == null ? '—' : '${uiMs.toStringAsFixed(1)} ms',
                muted,
              ),
              _row(
                '丢帧',
                '渲染 ${_raw('frame-drop-count').isEmpty ? '0' : _raw('frame-drop-count')}'
                    '  |  解码 ${_raw('decoder-frame-drop-count').isEmpty ? '0' : _raw('decoder-frame-drop-count')}',
                muted,
              ),
            ], last: true),
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    Color divider,
    Color muted,
    List<Widget> rows, {
    bool last = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 9),
        Divider(height: 1, thickness: 0.5, color: divider),
        const SizedBox(height: 7),
        Text(
          title,
          style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: muted),
        ),
        const SizedBox(height: 4),
        ...rows,
        if (last) const SizedBox(height: 2),
      ],
    );
  }

  Widget _row(
    String label,
    String value,
    Color muted, {
    Color? highlight,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: TextStyle(fontSize: 12, color: muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: highlight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}