import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/input_formatters.dart';

TextEditingValue _v(String text, [int? offset]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset ?? text.length),
    );

String _apply(List<TextInputFormatter> fs, String before, String after) {
  var value = _v(after);
  for (final f in fs) {
    value = f.formatEditUpdate(_v(before), value);
  }
  return value.text;
}

void main() {
  group('ユーザーID欄', () {
    test('全角英数字は半角の大文字になる', () {
      expect(_apply(userIdInputFormatters, '', 'ｍｐ－１２３４５６７８'), 'MP-12345678');
    });

    test('絵文字は取り除かれる', () {
      expect(_apply(userIdInputFormatters, '', 'MP-1234🎉😀'), 'MP-1234');
    });

    test('ひらがな・漢字は取り除かれる', () {
      expect(_apply(userIdInputFormatters, '', 'MPあ-12田34'), 'MP-1234');
    });

    test('小文字は大文字に統一される', () {
      expect(_apply(userIdInputFormatters, '', 'mp-abcd1234'), 'MP-ABCD1234');
    });

    // 「文字が消せない」不具合の再発防止。
    // 削除後の文字列がそのまま通らないと、消してもすぐ元に戻ってしまう。
    test('1文字消せる', () {
      expect(_apply(userIdInputFormatters, 'MP-12345678', 'MP-1234567'),
          'MP-1234567');
    });

    test('全部消せる', () {
      expect(_apply(userIdInputFormatters, 'MP-12345678', ''), '');
    });

    test('途中の文字を消せる', () {
      expect(_apply(userIdInputFormatters, 'MP-12345678', 'MP-1245678'),
          'MP-1245678');
    });

    test('カーソルは編集した位置に残る', () {
      final formatter = userIdInputFormatters.first;
      final result = formatter.formatEditUpdate(
        _v('MP-12345678'),
        _v('MP-1２345678', 6), // 途中に全角を入れた直後
      );
      expect(result.text, 'MP-12345678');
      expect(result.selection.baseOffset, 6); // 末尾へ飛ばない
    });
  });

  group('金額欄', () {
    test('全角数字は半角になる', () {
      expect(_apply(integerAmountInputFormatters, '', '１２３４'), '1234');
    });

    test('数字以外は取り除かれる', () {
      expect(_apply(integerAmountInputFormatters, '', '1,234円'), '1234');
    });

    test('消せる', () {
      expect(_apply(integerAmountInputFormatters, '1234', '123'), '123');
    });

    test('小数欄では小数点が残る', () {
      expect(_apply(decimalAmountInputFormatters, '', '１２．５'), '12.5');
    });
  });

  group('メールアドレス欄', () {
    test('全角は半角になり空白は除去される', () {
      expect(_apply(emailInputFormatters, '', 'ａ＠ｂ.ｃｏｍ '), 'a@b.com');
    });

    test('日本語は取り除かれる', () {
      expect(_apply(emailInputFormatters, '', 'たろうtaro@example.com'),
          'taro@example.com');
    });

    test('消せる', () {
      expect(_apply(emailInputFormatters, 'a@b.com', 'a@b.co'), 'a@b.co');
    });
  });
}
