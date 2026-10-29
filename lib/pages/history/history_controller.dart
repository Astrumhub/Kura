import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/media/media_watch_store.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  @observable
  ObservableList<History> histories = ObservableList<History>();

  void init() {
    final temp = _historyRepository.getAllHistories();
    histories.clear();
    histories.addAll(temp);
  }

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    // 影视条目是用 TMDB id 取负数适配出来的：不写进番剧历史，
    // 改为写入独立的影视观看记录，避免污染历史页与跨端同步。
    if (identity.bangumiItem.id < 0) {
      final item = identity.bangumiItem;
      await MediaWatchStore.save(
        MediaWatchRecord(
          tmdbId: -item.id,
          isTv: identity.episodeNumber > 0,
          title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
          posterUrl: item.images['large'] ?? '',
          pluginName: identity.pluginName,
          episode: identity.episodeNumber,
          episodeTitle: identity.episodeTitle,
          progressMs: progress.inMilliseconds,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return;
    }
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    init();
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    if (bangumiItem.id < 0) {
      return null;
    }
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
  }
}
