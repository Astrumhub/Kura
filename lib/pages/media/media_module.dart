import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/media/media_item.dart';
import 'package:kazumi/pages/media/media_detail_page.dart';
import 'package:kazumi/pages/route_error_page.dart';

/// 影视模块。
///
/// 与番剧的 `/info/` 同构：走 Modular 的根路由推入，转场与原生完全一致。
final mediaModule = createModule(
  path: '/media',
  register: (c) {
    c.route(
      '/detail',
      child: (context, state) {
        final item = state.arguments;
        if (item is! MediaItem) {
          return const RouteErrorPage(message: '影视条目参数无效，请返回后重新打开。');
        }
        return MediaDetailPage(item: item);
      },
    );
  },
);