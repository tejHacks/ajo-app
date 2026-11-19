import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ajo/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app() => const MaterialApp(
      home: OnboardingGate(
        color: Colors.indigo,
        slides: [Slide(Icons.star, 'First', 'One'), Slide(Icons.star, 'Second', 'Two'), Slide(Icons.star, 'Third', 'Three')],
        child: Text('Home'),
      ),
    );

void main() {
  testWidgets('shows on first launch, Next walks through, last button opens the app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('onboarded'), isTrue);
  });

  testWidgets('Skip goes straight in, and it never shows again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
