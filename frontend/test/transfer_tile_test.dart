import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/models/models.dart';
import 'package:megapay_app/theme.dart';
import 'package:megapay_app/widgets/transfer_tile.dart';

/// TransferTile のレイアウト検証。
///
/// ListTile は trailing（右側）の高さを 56px までに制限する。そこへ金額と
/// 保存ボタンを縦に積んでいるため、ボタンを大きくすると簡単にはみ出す。
/// リリースビルドでは、はみ出しても黄黒の縞模様が描かれずスクリーンショットで
/// 気付けないので、ここで検出できるようにしておく。
void main() {
  TransferRecord record({
    String direction = 'sent',
    String? memo = '飲み会テスト（平社員）',
    String amount = '1500',
  }) {
    return TransferRecord(
      id: 'tx-1',
      direction: direction,
      counterpartUserId: 'MP-21772680',
      counterpartName: '花子',
      currency: 'JPY',
      amount: amount,
      memo: memo,
      createdAt: DateTime(2026, 8, 6, 16, 32),
    );
  }

  Future<void> pumpTile(
    WidgetTester tester, {
    required TransferRecord data,
    double width = 360,
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMegaPayTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: TransferTile(record: data, onSave: () {}),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('TransferTile', () {
    testWidgets('標準の文字サイズではみ出さない', (tester) async {
      await pumpTile(tester, data: record(), width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('受取・メモなしでもはみ出さない', (tester) async {
      await pumpTile(
        tester,
        data: record(direction: 'received', memo: null),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('金額が大きくてもはみ出さない', (tester) async {
      await pumpTile(tester, data: record(amount: '1234567'), width: 320);
      expect(tester.takeException(), isNull);
    });

    // 端末やブラウザの文字サイズ設定で拡大されても壊れないこと。
    // 実際にここで 2px はみ出す不具合が出ていた。
    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('文字サイズ $scale 倍でもはみ出さない', (tester) async {
        await pumpTile(tester, data: record(), width: 320, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('保存ボタンは押せる大きさを保つ', (tester) async {
      await pumpTile(tester, data: record());

      final size = tester.getSize(
        find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
      );

      // 以前は高さ 24px しかなく指で押しづらかった。
      expect(size.height, greaterThanOrEqualTo(40));
      expect(size.width, greaterThanOrEqualTo(40));
    });

    testWidgets('保存ボタンを押すと onSave が呼ばれる', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMegaPayTheme(),
          home: Scaffold(
            body: TransferTile(record: record(), onSave: () => tapped++),
          ),
        ),
      );

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
      );

      expect(tapped, 1);
    });
  });
}
