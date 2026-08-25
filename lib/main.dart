import 'package:flutter/material.dart';

import 'product/product_runtime.dart';
import 'product/runtime_provisioning_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await ProductRuntime.initialize();
  runApp(ProvisioningKristinApp(runtime: runtime));
}
