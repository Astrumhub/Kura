import 'package:hive_ce/hive.dart';

/// 影视观看记录。
///
/// 影视条目用 TMDB id 取负数适配成 BangumiItem，这些记录**不写进番剧历史**，
/// 单独存在这里，避免污染历史页与跨端同步。
class MediaWatchRecord {
  const MediaWatchRecord({
    required this.tmdbId,
    required this.isTv,
    required this.title,
    required this.posterUrl,
    required this.pluginName,
    required this.episode,
    required this.episodeTitle,
    required this.progressMs,
    required this.updatedAt,
  });

  final int tmdbId;
  final bool isTv;
  final String title;
  final String posterUrl;
  final String pluginName;
  final int episode;
  final String episodeTitle;
  final int progressMs;
  final int updatedAt;

  String get progressLabel {
    final totalSeconds = progressMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'tmdbId': tmdbId,
        'isTv': isTv,
        'title': title,
        'posterUrl': posterUrl,
        'pluginName': pluginName,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'progressMs': progressMs,
        'updatedAt': updatedAt,
      };

  static MediaWatchRecord fromMap(Map<dynamic, dynamic> map) => MediaWatchRecord(
        tmdbId: (map['tmdbId'] as num?)?.toInt() ?? 0,
        isTv: map['isTv'] == true,
        title: (map['title'] ?? '').toString(),
        posterUrl: (map['posterUrl'] ?? '').toString(),
        pluginName: (map['pluginName'] ?? '').toString(),
        episode: (map['episode'] as num?)?.toInt() ?? 0,
        episodeTitle: (map['episodeTitle'] ?? '').toString(),
        progressMs: (map['progressMs'] as num?)?.toInt() ?? 0,
        updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 影视观看记录的本地存储（独立 Hive box，不参与番剧同步）。
abstract final class MediaWatchStore {
  static const String _boxName = 'mediaWatchHistory';
  static Box<dynamic>? _box;

  static Future<Box<dynamic>> _open() async =>
      _box ??= await Hive.openBox<dynamic>(_boxName);

  static Future<void> save(MediaWatchRecord record) async {
    final box = await _open();
    await box.put('${record.tmdbId}', record.toMap());
  }

  static Future<MediaWatchRecord?> get(int tmdbId) async {
    final box = await _open();
    final raw = box.get('$tmdbId');
    if (raw is Map) {
      return MediaWatchRecord.fromMap(Map<dynamic, dynamic>.from(raw));
    }
    return null;
  }

  /// 最近观看，按时间倒序。
  static Future<List<MediaWatchRecord>> recent({int limit = 20}) async {
    final box = await _open();
    final records = box.values
        .whereType<Map>()
        .map((raw) => MediaWatchRecord.fromMap(Map<dynamic, dynamic>.from(raw)))
        .where((record) => record.tmdbId != 0)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records.take(limit).toList();
  }
}