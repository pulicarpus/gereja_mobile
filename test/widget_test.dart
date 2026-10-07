import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/loading_sultan.dart';

void main() {
  testWidgets('Loading indicator can be removed during navigation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingSultan(size: 80))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoadingSultan), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
