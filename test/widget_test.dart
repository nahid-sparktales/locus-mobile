import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_mobile/src/screens.dart';

void main() {
  testWidgets('connection status is visible and accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ConnectionPill(online: false))),
    );

    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ConnectionPill)).label,
      contains('Mac offline'),
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    semantics.dispose();
  });
}
