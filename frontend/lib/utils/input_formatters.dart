import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // String.characters を使うため

/// 入力欄で使う共通のフォーマッタ。
///
/// ユーザーIDや請求コードは半角英数字しか受け付けないが、日本語入力が
/// 有効なままだと全角文字や絵文字がそのまま入ってしまう。かといって
/// 「不正な文字を弾く」実装にすると、IME の変換途中の文字列と実際の
/// 入力欄の内容がずれ、文字を消せなくなることがある。
///
/// そのためここでは弾くのではなく **変換する** 方針をとる。
/// 全角は半角に直し、残った対象外の文字だけを取り除く。

/// 1文字ずつ変換をかけるフォーマッタの共通処理。
abstract class _CharMapFormatter extends TextInputFormatter {
  const _CharMapFormatter();

  /// 1文字を変換する。null を返すとその文字は取り除かれる。
  String? mapChar(String char);

  String _convert(String input) {
    final buffer = StringBuffer();
    for (final char in input.characters) {
      final mapped = mapChar(char);
      if (mapped != null) buffer.write(mapped);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 日本語入力で変換中（未確定）の文字列には手を触れない。
    //
    // 変換中に文字を取り除くと、IME が持っている変換候補と入力欄の中身が
    // ずれる。ずれたまま確定すると、予測変換の文字がそのまま残ったうえに
    // バックスペースでも消せない状態になる。
    // 変換が確定すると composing は空になり、そこで初めて変換をかける。
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    final text = _convert(newValue.text);

    // カーソル位置は「カーソルより前の部分を変換した長さ」に合わせる。
    // 単純に末尾へ送ると、途中を編集したときにカーソルが飛んでしまう。
    final rawOffset = newValue.selection.baseOffset;
    final safeOffset = rawOffset < 0 ? newValue.text.length : rawOffset;
    final head = _convert(
      newValue.text.substring(0, safeOffset.clamp(0, newValue.text.length)),
    );

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: head.length),
      composing: TextRange.empty,
    );
  }
}

/// 全角の記号・英数字を半角に直す。対象外なら元の文字をそのまま返す。
String _toHalfWidth(String char) {
  final code = char.codeUnitAt(0);
  // 全角の ！ 〜 ～ は、半角の同じ並びから 0xFEE0 ずれた位置にある
  if (code >= 0xFF01 && code <= 0xFF5E) {
    return String.fromCharCode(code - 0xFEE0);
  }
  if (code == 0x3000) return ' '; // 全角スペース
  return char;
}

/// ユーザーID・請求コード用。半角英数字とハイフンだけを残し、大文字に統一する。
/// 例: `ｍｐ－１２３４` -> `MP-1234`
class IdCodeInputFormatter extends _CharMapFormatter {
  const IdCodeInputFormatter();

  @override
  String? mapChar(String char) {
    if (char.length > 1) return null; // 絵文字などのサロゲートペアは除去
    final half = _toHalfWidth(char).toUpperCase();
    return RegExp(r'^[A-Z0-9-]$').hasMatch(half) ? half : null;
  }
}

/// 金額用。全角数字を半角に直し、数字だけを残す。
class DigitsInputFormatter extends _CharMapFormatter {
  const DigitsInputFormatter();

  @override
  String? mapChar(String char) {
    if (char.length > 1) return null;
    final half = _toHalfWidth(char);
    return RegExp(r'^[0-9]$').hasMatch(half) ? half : null;
  }
}

/// 小数を扱う通貨の金額用。数字と小数点だけを残す。
class DecimalInputFormatter extends _CharMapFormatter {
  const DecimalInputFormatter();

  @override
  String? mapChar(String char) {
    if (char.length > 1) return null;
    final half = _toHalfWidth(char);
    return RegExp(r'^[0-9.]$').hasMatch(half) ? half : null;
  }
}

/// メールアドレス用。全角を半角に直し、空白を取り除く。
class EmailInputFormatter extends _CharMapFormatter {
  const EmailInputFormatter();

  @override
  String? mapChar(String char) {
    if (char.length > 1) return null;
    final half = _toHalfWidth(char);
    if (half == ' ') return null;
    // 半角に直しても ASCII にならない文字（ひらがな等）は受け付けない
    return half.codeUnitAt(0) < 0x80 ? half : null;
  }
}

/// ユーザーID欄で使う一式。`MP-` + 8桁を想定し、余裕をみて上限を設ける。
final userIdInputFormatters = <TextInputFormatter>[
  const IdCodeInputFormatter(),
  LengthLimitingTextInputFormatter(20),
];

/// 請求コード・割り勘コード欄で使う一式。`RQ-` / `SP-` + 8桁を想定。
final codeInputFormatters = <TextInputFormatter>[
  const IdCodeInputFormatter(),
  LengthLimitingTextInputFormatter(20),
];

/// 整数のみの金額欄で使う一式。
final integerAmountInputFormatters = <TextInputFormatter>[
  const DigitsInputFormatter(),
  LengthLimitingTextInputFormatter(12),
];

/// 小数を許す金額欄で使う一式。
final decimalAmountInputFormatters = <TextInputFormatter>[
  const DecimalInputFormatter(),
  LengthLimitingTextInputFormatter(16),
];

/// メールアドレス欄で使う一式。
final emailInputFormatters = <TextInputFormatter>[
  const EmailInputFormatter(),
  LengthLimitingTextInputFormatter(254),
];
