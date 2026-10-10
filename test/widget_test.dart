import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/machine_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobileraker/ui/screens/overview/overview_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PrintDeck empty overview offers to add a printer',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allMachinesProvider.overrideWith((ref) async => <Machine>[]),
        ],
        child: const MaterialApp(home: PrintDeckOverviewBody()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.print_disabled_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
