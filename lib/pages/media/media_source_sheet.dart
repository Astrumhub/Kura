import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 影视播放源选择面板。
///
/// 流程与番剧的 SourceSheet 一致：
///   片名 → 逐个规则 queryBangumi → 选中结果 → queryChapterRoads → 跳 /video/
/// 区别只是不依赖 InfoController（影视条目不在 Bangumi 里）。
class MediaSourceSheet extends StatefulWidget {
  const MediaSourceSheet({
    super.key,
    required this.title,
    required this.bangumiItem,
    required this.onPlay,
    this.searchKeyword,
  });

  final String title;
  final BangumiItem bangumiItem;
  final void Function(OnlineVideoPlaybackArgs args) onPlay;
  final String? searchKeyword;

  @override
  State<MediaSourceSheet> createState() => _MediaSourceSheetState();
}

class _SourceGroup {
  _SourceGroup(this.plugin);

  final Plugin plugin;
  final List<SearchItem> items = [];
  bool loading = true;
  String? error;

  bool get hasResults => items.isNotEmpty;
}

class _MediaSourceSheetState extends State<MediaSourceSheet> {
  late final PluginsController _plugins = inject<PluginsController>();
  final List<_SourceGroup> _groups = [];
  int _pending = 0;
  final TextEditingController _keywordController =
      TextEditingController();
  String? _opening;

  String get _keyword {
    final typed = _keywordController.text.trim();
    if (typed.isNotEmpty) {
      return typed;
    }
    final explicit = widget.searchKeyword?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return widget.bangumiItem.nameCn.isEmpty
        ? widget.bangumiItem.name
        : widget.bangumiItem.nameCn;
  }

  @override
  void initState() {
    super.initState();
    _keywordController.text = _keyword;
    _startSearch();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  void _startSearch() {
    final plugins = _plugins.pluginList;
    if (plugins.isEmpty) {
      return;
    }
    _groups.clear();
    _pending = 0;
    for (final plugin in plugins) {
      final group = _SourceGroup(plugin);
      _groups.add(group);
      _pending++;
      _query(group);
    }
    setState(() {});
  }

  Future<void> _query(_SourceGroup group) async {
    try {
      final response = await group.plugin.queryBangumi(_keyword);
      if (!mounted) {
        return;
      }
      setState(() {
        group.items
          ..clear()
          ..addAll(response.data);
        group.loading = false;
        _pending--;
      });
    } catch (error) {
      KazumiLogger().w('MediaSourceSheet: search failed', error: error);
      if (!mounted) {
        return;
      }
      setState(() {
        group.loading = false;
        group.error = '搜索失败';
        _pending--;
      });
    }
  }

  Future<void> _open(_SourceGroup group, SearchItem item) async {
    if (_opening != null) {
      return;
    }
    setState(() => _opening = item.src);
    try {
      final roads = await group.plugin.queryChapterRoads(item.src);
      if (!mounted) {
        return;
      }
      if (roads.isEmpty) {
        KazumiDialog.showToast(context: context, message: '该条目暂无播放列表');
        setState(() => _opening = null);
        return;
      }
      widget.onPlay(
        OnlineVideoPlaybackArgs(
          bangumiItem: widget.bangumiItem,
          plugin: group.plugin,
          title: item.name,
          src: item.src,
          roads: roads,
        ),
      );
    } catch (error) {
      KazumiLogger().w('MediaSourceSheet: failed to fetch roads', error: error);
      if (mounted) {
        KazumiDialog.showToast(context: context, message: '获取播放列表失败，换个源试试');
        setState(() => _opening = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _groups.where((g) => g.loading || g.hasResults).toList();
    final allDone = _pending == 0;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选择播放源', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '检索词：$_keyword',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (!allDone)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _startSearch(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '换个关键词再搜（原名/别名）',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _startSearch,
                  child: const Text('重搜'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有安装任何规则，请先在「设置 → 规则管理」导入'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (allDone && visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('所有规则都没有搜到结果，换个关键词试试'),
                    ),
                  for (final group in visible) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Row(
                        children: [
                          Text(
                            group.plugin.name,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: scheme.primary),
                          ),
                          const SizedBox(width: 8),
                          if (group.loading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          const Spacer(),
                          if (group.hasResults)
                            Text(
                              '${group.items.length} 个结果',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    for (final item in group.items)
                      ListTile(
                        dense: true,
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _opening == item.src
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.play_circle_outline, size: 20),
                        onTap: () => _open(group, item),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}