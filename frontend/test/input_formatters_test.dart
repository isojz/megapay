import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/input_formatters.dart';

/// 入力フォーマッタの検証。
///
/// 日本語入力では、変換が確定するまで入力欄に未確定の文字列が入る。
/// この最中に文字を取り除くと IME 側の状態とずれ、確定後に消せない文字が
/// 残ってしまう。ここではその「変換中は触らない」挙動を中心に確かめる。
void main() {
  /// 変換が確定した状態（composing なし）の入力を作る。
  TextEditingValue committed(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  /// IME で変換中（未確定）の入力を作る。
  TextEditingValue composing(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: 0, end: text.length),
      );

  group('DigitsInputFormatter（金額欄）', () {
    const formatter = DigitsInputFormatter();

    test('半角数字はそのまま通る', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        committed('1500'),
      );

      expect(result.text, '1500');
    });

    test('全角数字は半角に直る', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        committed('１５００'),
      );

      expect(result.text, '1500');
    });

    test('数字でない文字は取り除かれる', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        committed('1500円'),
      );

      expect(result.text, '1500');
    });

    // ここが今回の不具合。変換中に文字を消していたため、IME の予測変換が
    // そのまま残り、バックスペースでも消せなくなっていた。
    test('変換中の文字列は書き換えない', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        composing('せんごひゃく'),
      );

      expect(result.text, 'せんごひゃく');
      expect(result.composing, const TextRange(start: 0, end: 6));
    });

    test('変換が確定した時点で半角数字に直る', () {
      // 変換中は素通しし…
      final whileComposing = formatter.formatEditUpdate(
        const TextEditingValue(),
        composing('１５００'),
      );
      expect(whileComposing.text, '１５００');

      // …確定した時点で変換をかける
      final afterCommit = formatter.formatEditUpdate(
        whileComposing,
        committed('１５００'),
      );
      expect(afterCommit.text, '1500');
    });

    test('変換を確定せずに消した場合も残らない', () {
      final cleared = formatter.formatEditUpdate(
        composing('せんごひゃく'),
        committed(''),
      );

      expect(cleared.text, '');
    });

    test('途中に文字を足してもカーソルが飛ばない', () {
      // 「1500」の先頭に全角の２を入れて「２1500」にした状況
      final result = formatter.formatEditUpdate(
        committed('1500'),
        const TextEditingValue(
          text: '２1500',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );

      expect(result.text, '21500');
      expect(result.selection.baseOffset, 1);
    });
  });

  group('IdCodeInputFormatter（ユーザーID・請求コード欄）', () {
    const formatter = IdCodeInputFormatter();

    test('全角は半角の大文字に直る', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        committed('ｍｐ－１２３４'),
      );

      expect(result.text, 'MP-1234');
    });

    test('変換中の文字列は書き換えない', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        composing('えむぴー'),
      );

      expect(result.text, 'えむぴー');
    });
  });

  group('EmailInputFormatter（メール欄）', () {
    const formatter = EmailInputFormatter();

    test('全角は半角に直り、空白は取り除かれる', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        committed('ｔｅｓｔ＠ｅｘａｍｐｌｅ．ｃｏｍ　'),
      );

      expect(result.text, 'test@example.com');
    });

    test('変換中の文字列は書き換えない', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(),
        composing('てすと'),
      );

      expect(result.text, 'てすと');
    });
  });
}
