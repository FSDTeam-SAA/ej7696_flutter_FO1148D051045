import 'package:ej_flutter/views/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('course card stays readable on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const title = 'API 510 - Pressure Vessel Inspector';
    const action = 'Unlock for \$149.99 / 6 months';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: CourseCard(
              course: const CourseItem(
                id: 'api-510',
                title: title,
                subtitle: 'Master your certification exam',
                imageAsset: 'assets/images/onboarding1.png',
              ),
              isUnlocked: false,
              showPriceUnlock: true,
              iapPrice: '\$149.99',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(find.text(action), findsOneWidget);
    expect(tester.getTopLeft(find.text(action)).dy,
        greaterThan(tester.getBottomLeft(find.text(title)).dy));
    expect(tester.takeException(), isNull);
  });
}
