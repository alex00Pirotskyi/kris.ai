import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p1_authority_service_contract_v1.dart';
import 'package:kristin_local_agent/product/p1_authority_service_product_runtime_v1.dart';

final class _BlockedConnector implements P1AuthorityServiceConnectorV1 {
  @override
  Future<P1AuthorityServiceClientV1> connect() =>
      throw StateError('not_provisioned');
}

void main() {
  test(
    'ProductRuntime fails closed when isolated P1A service is unavailable',
    () async {
      await expectLater(
        P1AuthorityServiceProductRuntimeV1.open(connector: _BlockedConnector()),
        throwsStateError,
      );
    },
  );
}
