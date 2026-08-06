import 'package:flutter/material.dart';

/// アプリのイメージカラー。
///
/// 配色は ColorScheme.fromSeed でこの色から自動生成されるため、
/// ここを変えるとアプリ全体の色が切り替わる。直書きせず必ずこの定数を参照すること。
const megaPayBrandColor = Color(0xFFE60000);

/// 画面の背景色。カードを白で置いたときに境界が分かるよう、わずかに濃いグレー。
const megaPayBackgroundColor = Color(0xFFF2F2F2);

/// ブランドカラーの上に重ねる文字・アイコンの色。
const megaPayOnBrandColor = Colors.white;
