// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/driver_resolution.dart';
import '../dart/resolution/with_null_safety_mixin.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NonConstantCaseExpressionTest);
    defineReflectiveTests(NonConstantCaseExpressionWithNullSafetyTest);
  });
}

@reflectiveTest
class NonConstantCaseExpressionTest extends DriverResolutionTest {
  test_constField() async {
    await assertNoErrorsInCode(r'''
void f(C e) {
  switch (e) {
    case C.zero:
      break;
    default:
      break;
  }
}

class C {
  static const zero = C(0);

  final int a;
  const C(this.a);
}
''');
  }

  test_parameter() async {
    await assertErrorsInCode(r'''
void f(var e, int a) {
  switch (e) {
    case 3 + a:
      break;
  }
}
''', [
      error(CompileTimeErrorCode.NON_CONSTANT_CASE_EXPRESSION, 51, 1),
    ]);
  }

  test_typeLiteral() async {
    await assertNoErrorsInCode(r'''
void f(var e) {
  switch (e) {
    case bool:
    case int:
      break;
    default:
      break;
  }
}
''');
  }
}

@reflectiveTest
class NonConstantCaseExpressionWithNullSafetyTest
    extends NonConstantCaseExpressionTest with WithNullSafetyMixin {}
