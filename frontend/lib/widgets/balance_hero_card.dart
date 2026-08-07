import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme.dart';
import '../utils/money.dart';

/// ホーム画面の主役になる残高カード。
///
/// これまで残高は小さな ListTile で、その上に大きなプロフィールカードが
/// 載っていた。アプリを開く一番の理由は「今いくらあるか」なのに、視覚的な
/// 重みが逆転していたため、画面が機能一覧のように見えていた。
/// ここでは残高を最大の要素として扱い、受け取りに必要なユーザーIDだけを
/// 同じカードに添える。
///
/// 金額を伏せる挙動（残高安全）は既存の実装を踏襲し、既定では隠す。
class BalanceHeroCard extends StatefulWidget {
  const BalanceHeroCard({
    super.key,
    required this.balance,
    required this.userId,
  });

  /// 表示する残高。null のときは残高がまだ無い扱いにする。
  final Balance? balance;

  /// 受け取りに使う自分のユーザーID。
  final String userId;

  @override
  State<BalanceHeroCard> createState() => _BalanceHeroCardState();
}

class _BalanceHeroCardState extends State<BalanceHeroCard> {
  /// 人に見られないよう既定では伏せ、目のボタンで表示を切り替える。
  bool _visible = false;

  Future<void> _copyUserId() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.userId));
    messenger.showSnackBar(
      const SnackBar(content: Text('ユーザーIDをコピーしました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.balance;
    final amountText = balance == null
        ? '0 円'
        : _visible
            ? formatMoney(balance.currency, balance.amount)
            : '•••••• 円';

    // 白文字を載せるので、濃さの違う 2 色でブランドカラーの面を作る。
    // 単色より奥行きが出て、カードが「主役」であることが伝わる。
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(megaPayCardRadius + 4),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE60000), Color(0xFFA30014)],
        ),
        boxShadow: [
          BoxShadow(
            color: megaPayBrandColor.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '残高',
                  style: TextStyle(
                    color: megaPayOnBrandColor.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              IconButton(
                tooltip: _visible ? '残高を隠す' : '残高を表示',
                color: megaPayOnBrandColor,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ],
          ),
          // 金額はこの画面で一番大きい文字にする。桁が動いても幅が
          // ぶれないよう等幅の数字（tabular figures）を指定する。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amountText,
              maxLines: 1,
              style: const TextStyle(
                color: megaPayOnBrandColor,
                fontSize: 38,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: megaPayOnBrandColor.withValues(alpha: 0.22),
          ),
          const SizedBox(height: 4),
          // 受け取りに必要なのはユーザーIDだけなので、ここに置いて
          // 「相手に伝える → 受け取れる」導線を残高のすぐ下にまとめる。
          Row(
            children: [
              Text(
                'ID',
                style: TextStyle(
                  color: megaPayOnBrandColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.userId,
                  style: TextStyle(
                    color: megaPayOnBrandColor.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    // monospace は日本語グリフを持たないため、同梱フォントを
                    // フォールバック先に指定する
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['NotoSansJP'],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ユーザーIDをコピー',
                color: megaPayOnBrandColor,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: _copyUserId,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
