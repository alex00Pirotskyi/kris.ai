import 'dart:io';

import 'p1_authority_service_contract_v1.dart';
import 'p1_authority_service_native_connector_v2.dart';

final class P1AuthorityServiceInstalledLocationV2 {
  const P1AuthorityServiceInstalledLocationV2._();

  static String applicationSupportDirectory() {
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'];
      if (root == null || root.isEmpty) {
        throw StateError('p1a_local_app_data_missing');
      }
      return '$root${Platform.pathSeparator}Kristin';
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('p1a_home_missing');
    }
    if (Platform.isMacOS) {
      return '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Kristin';
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final root = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share';
    return '$root${Platform.pathSeparator}kristin';
  }
}

final class P1AuthorityServiceProductRuntimeV1 {
  P1AuthorityServiceProductRuntimeV1._(this.handle);
  final P1AuthorityServiceHandleV1 handle;

  static Future<P1AuthorityServiceProductRuntimeV1> open({
    required P1AuthorityServiceConnectorV1 connector,
  }) async {
    final client = await connector.connect();
    final handle = P1AuthorityServiceHandleV1(client);
    handle.validateForP2();
    return P1AuthorityServiceProductRuntimeV1._(handle);
  }

  static Future<P1AuthorityServiceProductRuntimeV1?> openInstalled({
    String? applicationSupportDirectory,
  }) async {
    final root = Directory(
      applicationSupportDirectory ??
          P1AuthorityServiceInstalledLocationV2.applicationSupportDirectory(),
    );
    if (!root.isAbsolute) {
      throw StateError('p1a_application_support_root_absolute_required');
    }
    final config = File(
      '${root.path}${Platform.pathSeparator}authority-service${Platform.pathSeparator}connector-v2.json',
    );
    if (!config.existsSync()) {
      return null;
    }
    return open(
      connector: P1AuthorityNativeConnectorV2(configurationPath: config.path),
    );
  }

  Future<void> close() => handle.service.close();
}

/// Unit tests can install a connector before sealing. Production startup calls
/// [P1AuthorityServiceProductRuntimeV1.openInstalled] and never accepts a P2-
/// supplied authority connector.
final class P1AuthorityServiceConnectorRegistryV1 {
  P1AuthorityServiceConnectorRegistryV1._();
  static P1AuthorityServiceConnectorV1? _testConnector;
  static bool _sealed = false;

  static void installForTest({
    required P1AuthorityServiceConnectorV1 connector,
    required bool testProcessVerified,
  }) {
    if (_sealed || !testProcessVerified) {
      throw StateError('p1a_connector_installation_rejected');
    }
    _testConnector = connector;
    _sealed = true;
  }

  static Future<P1AuthorityServiceProductRuntimeV1?>
      openInstalledOrTest() async {
    final connector = _testConnector;
    if (connector != null) {
      return P1AuthorityServiceProductRuntimeV1.open(connector: connector);
    }
    return P1AuthorityServiceProductRuntimeV1.openInstalled();
  }
}
