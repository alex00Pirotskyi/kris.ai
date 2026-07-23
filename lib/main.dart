import 'package:flutter/material.dart';

import 'product/product_runtime.dart';
import 'product/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await ProductRuntime.initialize();
  runApp(KristinApp(runtime: runtime));
}
