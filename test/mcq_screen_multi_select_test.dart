import 'package:ej_flutter/controllers/quiz_voice_controller.dart';
import 'package:ej_flutter/controllers/user_controller.dart';
import 'package:ej_flutter/views/screens/mcq_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TestUserController extends UserController {
  // Avoid production storage/network startup in this widget test.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {}
}

class _TestQuizVoiceController extends QuizVoiceController {
  // Avoid production settings loading and watchdog timers in this widget test.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void onClose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
          if (call.method == 'getVoices') return <dynamic>[];
          return 1;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, (call) async {
          if (call.method == 'has_permission') return false;
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, null);
  });

  setUp(() {
    Get.testMode = true;
    Get.put<UserController>(_TestUserController());
    Get.put<QuizVoiceController>(_TestQuizVoiceController());
  });

  tearDown(() async {
    Get.reset();
  });

  Future<void> pumpQuiz(WidgetTester tester, {List<dynamic>? questions}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: McqScreen(
          courseTitle: 'Test course',
          questions: questions ?? _questions,
          timedMode: false,
        ),
      ),
    );
    await tester.pump();
  }

  Color optionColor(WidgetTester tester, int index) {
    final container = tester.widget<Container>(
      find.byKey(ValueKey('answer-option-$index')),
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets(
    'multi-select uses checkboxes and requires exact selection submission',
    (tester) async {
      await pumpQuiz(tester);

      expect(find.byType(Checkbox), findsNWidgets(4));
      expect(find.text('Submit Answer'), findsNothing);
      expect(find.text('Answer Submitted'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-0')));
      await tester.pump();
      expect(optionColor(tester, 0), const Color(0xFFD8F5D8));
      expect(optionColor(tester, 2), const Color(0xFFF3F4F6));
      expect(find.text('0/2 Question Answered'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-0')));
      await tester.pump();
      expect(optionColor(tester, 0), const Color(0xFFF3F4F6));

      await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-0')));
      await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-2')));
      await tester.pump();
      expect(optionColor(tester, 0), const Color(0xFFD8F5D8));
      expect(optionColor(tester, 2), const Color(0xFFD8F5D8));
      expect(find.text('0/2 Question Answered'), findsOneWidget);

      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('1/2 Question Answered'), findsOneWidget);
      expect(find.text('Single-answer question'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Submit Answer'), findsNothing);
    },
  );

  testWidgets('wrong tap reveals answers and Next submits the result', (
    tester,
  ) async {
    await pumpQuiz(tester);

    await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-1')));
    await tester.pump();

    expect(optionColor(tester, 0), const Color(0xFFD8F5D8));
    expect(optionColor(tester, 1), const Color(0xFFFFD6D6));
    expect(optionColor(tester, 2), const Color(0xFFD8F5D8));
    expect(optionColor(tester, 3), const Color(0xFFF3F4F6));
    expect(find.text('0/2 Question Answered'), findsOneWidget);
    for (final checkbox in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(checkbox.onChanged, isNull);
    }

    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Single-answer question'), findsOneWidget);
    expect(find.text('1/2 Question Answered'), findsOneWidget);
    expect(find.text('Submit Answer'), findsNothing);
  });

  testWidgets('submitting a partial selection reveals missing answers', (
    tester,
  ) async {
    await pumpQuiz(tester);

    await tester.tap(find.byKey(const ValueKey('multi-select-checkbox-0')));
    await tester.pump();
    expect(optionColor(tester, 2), const Color(0xFFF3F4F6));

    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Single-answer question'), findsOneWidget);
    expect(find.text('1/2 Question Answered'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('question-number-0')));
    await tester.pump();
    expect(optionColor(tester, 0), const Color(0xFFD8F5D8));
    expect(optionColor(tester, 2), const Color(0xFFD8F5D8));
    for (final checkbox in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(checkbox.onChanged, isNull);
    }
  });
}

const List<dynamic> _questions = [
  {
    'question': 'Multi-select question',
    'questionType': 'multiSelect',
    'options': ['Correct A', 'Wrong B', 'Correct C', 'Wrong D'],
    'correctAnswers': ['A', 'C'],
    'explanation': 'Test explanation',
  },
  {
    'question': 'Single-answer question',
    'questionType': 'single',
    'options': ['Correct A', 'Wrong B', 'Wrong C', 'Wrong D'],
    'correctAnswer': 'A',
  },
];
