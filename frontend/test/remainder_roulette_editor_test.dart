import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/theme.dart';
import 'package:megapay_app/utils/remainder_roulette_calculator.dart';
import 'package:megapay_app/widgets/remainder_roulette_editor.dart';

Widget _app({
  required int totalAmount,
  required RemainderWinnerSelector selector,
  required ValueChanged<RemainderRouletteSubmission> onCreate,
}) {
  var active = false;
  return MaterialApp(
    theme: buildMegaPayTheme(),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RemainderRouletteEditor(
            currency: 'JPY',
            totalAmount: totalAmount,
            participantCount: 4,
            rouletteActive: active,
            isCreating: false,
            winnerSelector: selector,
            animationDuration: const Duration(milliseconds: 300),
            onRouletteActiveChanged: (value) => setState(() => active = value),
            onCreate: (submission) async => onCreate(submission),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('余りがある場合だけ有効化し、抽選、再抽選、作成できる', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final winners = [2, 1];
    var draw = 0;
    RemainderRouletteSubmission? created;
    await tester.pumpWidget(
      _app(
        totalAmount: 12700,
        selector: RemainderWinnerSelector(nextInt: (_) => winners[draw++]),
        onCreate: (value) => created = value,
      ),
    );

    expect(find.text('3,000 円 / 人'), findsOneWidget);
    expect(find.text('700 円'), findsOneWidget);
    expect(find.byKey(const Key('roulette-spin-button')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('roulette-enable-button')));
    await tester.tap(find.byKey(const Key('roulette-enable-button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('roulette-sound-toggle')));
    await tester.tap(find.byKey(const Key('roulette-sound-toggle')));
    await tester.ensureVisible(find.byKey(const Key('roulette-spin-button')));
    await tester.tap(find.byKey(const Key('roulette-spin-button')));
    await tester.pump();
    final spinningButton = tester.widget<FilledButton>(
      find.byKey(const Key('roulette-spin-button')),
    );
    expect(spinningButton.onPressed, isNull);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('+700 円を担当！'), findsOneWidget);
    expect(find.text('3,700 円'), findsOneWidget);
    expect(find.text('12,700 円'), findsOneWidget);
    expect(find.text('もう一度回す'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('roulette-spin-button')));
    await tester.tap(find.byKey(const Key('roulette-spin-button')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('roulette-winner-name'))).data,
      '参加者2',
    );

    await tester.ensureVisible(
      find.byKey(const Key('roulette-create-result-button')),
    );
    await tester.tap(find.byKey(const Key('roulette-create-result-button')));
    await tester.pump();
    expect(created!.result.payments, [3000, 3700, 3000, 3000]);
    expect(created!.result.paymentTotal, 12700);
  });

  testWidgets('単位を変更でき、320pxでも例外がない', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 760));
    await tester.pumpWidget(
      _app(
        totalAmount: 10123,
        selector: RemainderWinnerSelector(nextInt: (_) => 0),
        onCreate: (_) {},
      ),
    );

    await tester.tap(find.byKey(const Key('roulette-unit-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1000円単位').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('余り0ならrouletteを表示しない', (tester) async {
    await tester.pumpWidget(
      _app(
        totalAmount: 12000,
        selector: RemainderWinnerSelector(nextInt: (_) => 0),
        onCreate: (_) {},
      ),
    );

    expect(find.textContaining('ぴったり割れました'), findsOneWidget);
    expect(find.byKey(const Key('roulette-enable-button')), findsNothing);
    expect(find.byKey(const Key('roulette-spin-button')), findsNothing);
  });
}
