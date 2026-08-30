import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_compile_repair.dart';

void main() {
  test('compile diagnostics get exactly one bounded repair', () async {
    var compileCalls = 0;
    var repairCalls = 0;
    final result = await const BoundedPlanCompileRepair<String, String>().run(
      plan: 'bad-plan',
      compile: (plan) {
        compileCalls += 1;
        if (plan == 'bad-plan') {
          throw ProductException(
            'plan_invalid',
            'executor capability leaked into the compiled plan',
          );
        }
        return 'compiled:$plan';
      },
      repair: (plan, failure) async {
        repairCalls += 1;
        expect(failure.code, 'plan_invalid');
        expect(failure.message, contains('executor capability'));
        return 'repaired-plan';
      },
    );

    expect(result.repaired, isTrue);
    expect(result.compiled, 'compiled:repaired-plan');
    expect(compileCalls, 2);
    expect(repairCalls, 1);
  });

  test('provider failure never enters compile repair', () async {
    var repairCalls = 0;
    expect(
      () => const BoundedPlanCompileRepair<String, String>().run(
        plan: 'plan',
        compile: (plan) => throw ProductException(
          'model_not_selected',
          'No model is selected.',
        ),
        repair: (plan, failure) async {
          repairCalls += 1;
          return plan;
        },
      ),
      throwsA(isA<Exception>()),
    );
    expect(repairCalls, 0);
  });
}
