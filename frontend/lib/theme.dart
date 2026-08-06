import 'package:flutter/material.dart';

/// アプリのイメージカラー。
///
/// 配色は ColorScheme.fromSeed でこの色から自動生成されるため、
/// ここを変えるとアプリ全体の色が切り替わる。直書きせず必ずこの定数を参照すること。
const megaPayBrandColor = Color(0xFFE60000);

/// 画面の背景色。カードを白で置いたときに境界が分かるよう、わずかに濃いグレー。
const megaPayBackgroundColor = Color(0xFFF5F5F7);

/// ブランドカラーの上に重ねる文字・アイコンの色。
const megaPayOnBrandColor = Colors.white;

/// カード・ボタン・入力欄など、角丸の基準値。画面ごとに直書きせず参照する。
const double megaPayCardRadius = 16;
const double megaPayControlRadius = 14;

/// タップ領域の最小の高さ。ボタンはこれ以上にして押しやすさを担保する。
const double megaPayMinTapTarget = 52;

/// 画面本文の最大幅。Web で横に間延びしないための基準値。
///
/// 既存の画面は同じ 480 を各自で直書きしているため、ここへの置き換えは
/// 差分が広範囲に及ぶ。新しく画面を作るときはこの値を参照すること。
const double megaPayContentMaxWidth = 480;

/// 意味を持つ色（成功・注意・情報や、増減する金額の色）をまとめたテーマ拡張。
///
/// これまで各画面が `Colors.green` などを直書きしていたが、色の濃さがばらつき、
/// ダークテーマにも追従できなかった。ここに集約し `MegaPaySemantics.of(context)`
/// で参照する。
@immutable
class MegaPaySemantics extends ThemeExtension<MegaPaySemantics> {
  const MegaPaySemantics({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.positiveAmount,
    required this.negativeAmount,
  });

  /// 成功・完了・入金など「良い」状態を表す色。
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// 未払い・保留など「注意」を促す状態の色。
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// 補足・案内を表す色。
  final Color info;

  /// 履歴などで金額の増減を色で示すときに使う。
  final Color positiveAmount;
  final Color negativeAmount;

  static MegaPaySemantics of(BuildContext context) =>
      Theme.of(context).extension<MegaPaySemantics>() ?? _light;

  static const _light = MegaPaySemantics(
    success: Color(0xFF1E8E3E),
    onSuccess: Colors.white,
    successContainer: Color(0xFFE3F4E7),
    onSuccessContainer: Color(0xFF0B5121),
    warning: Color(0xFFB26A00),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFF1DD),
    onWarningContainer: Color(0xFF663C00),
    info: Color(0xFF1A5FB4),
    positiveAmount: Color(0xFF1E8E3E),
    negativeAmount: Color(0xFF1F2933),
  );

  static const _dark = MegaPaySemantics(
    success: Color(0xFF6DD58C),
    onSuccess: Color(0xFF00391A),
    successContainer: Color(0xFF184F2C),
    onSuccessContainer: Color(0xFFB6F0C5),
    warning: Color(0xFFF3B85C),
    onWarning: Color(0xFF422C00),
    warningContainer: Color(0xFF5E4100),
    onWarningContainer: Color(0xFFFFE0B2),
    info: Color(0xFF9CC4FF),
    positiveAmount: Color(0xFF6DD58C),
    negativeAmount: Color(0xFFE6E9EE),
  );

  @override
  MegaPaySemantics copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? positiveAmount,
    Color? negativeAmount,
  }) {
    return MegaPaySemantics(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      positiveAmount: positiveAmount ?? this.positiveAmount,
      negativeAmount: negativeAmount ?? this.negativeAmount,
    );
  }

  @override
  MegaPaySemantics lerp(ThemeExtension<MegaPaySemantics>? other, double t) {
    if (other is! MegaPaySemantics) return this;
    return MegaPaySemantics(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      positiveAmount: Color.lerp(positiveAmount, other.positiveAmount, t)!,
      negativeAmount: Color.lerp(negativeAmount, other.negativeAmount, t)!,
    );
  }
}

/// アプリ全体のライトテーマ。main.dart から参照する。
///
/// ダークテーマは _buildTheme が既に組み立てられる状態にしてあるが、まだ
/// 有効にしていない。各画面に Colors.green などの固定色が残っており、
/// 今の状態でダークにするとその部分だけ浮いてしまうため。固定色を
/// MegaPaySemantics へ寄せ切ってから darkTheme を渡すこと。
ThemeData buildMegaPayTheme() => _buildTheme(Brightness.light);

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: megaPayBrandColor,
    brightness: brightness,
  );

  final scaffoldBackground =
      isLight ? megaPayBackgroundColor : const Color(0xFF141218);
  final cardColor = isLight ? Colors.white : colorScheme.surfaceContainerHigh;
  final hairline = colorScheme.outlineVariant.withValues(alpha: 0.5);
  final semantics = isLight ? MegaPaySemantics._light : MegaPaySemantics._dark;

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(megaPayControlRadius),
  );

  final base = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    // 同梱の日本語フォントを既定にする（pubspec.yaml の fonts 参照）。
    // 指定しないと CanvasKit が gstatic からの遅延取得に頼り、
    // 取得が終わるまで日本語が豆腐（□）になる。
    fontFamily: 'NotoSansJP',
    scaffoldBackgroundColor: scaffoldBackground,
    extensions: [semantics],
  );

  return base.copyWith(
    // ヘッダーはイメージカラー。上に載る文字とアイコンは白で統一する。
    // スクロールで内容が潜り込んでも色が変わらないよう固定する。
    appBarTheme: const AppBarTheme(
      backgroundColor: megaPayBrandColor,
      foregroundColor: megaPayOnBrandColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: megaPayOnBrandColor,
        fontFamily: 'NotoSansJP',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    // カードは白のまま、影ではなく細い枠と角丸で面を分ける。
    // 影を薄くすることで画面がすっきりし、境界がグレー背景でも分かる。
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(megaPayCardRadius),
        side: BorderSide(color: hairline),
      ),
    ),
    // ボタンは高さを確保して押しやすく、角丸と太字で存在感を出す。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, megaPayMinTapTarget),
        shape: controlShape,
        textStyle: const TextStyle(
          fontFamily: 'NotoSansJP',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, megaPayMinTapTarget),
        shape: controlShape,
        side: BorderSide(color: colorScheme.outline),
        textStyle: const TextStyle(
          fontFamily: 'NotoSansJP',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: controlShape,
        textStyle: const TextStyle(
          fontFamily: 'NotoSansJP',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    // 入力欄は塗り＋角丸にして、フォーカス時にブランドカラーで縁取る。
    // 個別の画面で border を直書きしている欄はそちらが優先される。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(megaPayControlRadius),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(megaPayControlRadius),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(megaPayControlRadius),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      // 入力例（hintText）は既定色だと入力済みの文字と紛らわしいため薄くする。
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
      ),
    ),
    // タブは赤地に白だと選択中と未選択の区別が付きにくい。
    // カードと同じ明るい面に載せ、文字色で選択状態を示す。
    tabBarTheme: TabBarThemeData(
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      indicatorColor: colorScheme.primary,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(
        fontFamily: 'NotoSansJP',
        fontWeight: FontWeight.w700,
      ),
    ),
    // 通知は下から浮かせて角丸にし、他のカードと形をそろえる。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(megaPayControlRadius),
      ),
    ),
    // ダイアログも角丸をカードと合わせる。
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(megaPayCardRadius + 4),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
  );
}
