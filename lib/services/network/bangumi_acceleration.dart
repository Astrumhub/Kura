import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

enum BangumiAcceleration implements AccelerationMode {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current {
    final stored = values.asNameMap()[GStorage.getSetting(
          SettingsKeys.bangumiAcceleration,
        )] ??
        (GStorage.getSetting(SettingsKeys.enableBangumiProxy) ? mirror : direct);
    // 自编译版本没有注入镜像凭证（KAZUMI_APPID/KAZUMI_KEY），
    // 走镜像必然 401，因此强制回落到直连。
    if (stored == mirror && bangumiMirrorCredentials['id']!.isEmpty) {
      return direct;
    }
    return stored;
  }

  @override
  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };

  @override
  String get description => switch (this) {
    direct => '访问官方接口',
    ech => '启用加密握手',
    mirror => '镜像接口（默认）',
  };
}
