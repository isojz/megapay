import 'package:flutter/material.dart';

import '../screens/join_split_bill_screen.dart';
import '../models/models.dart';
import '../screens/pay_request_screen.dart';
import '../screens/request_create_screen.dart';
import '../screens/request_list_screen.dart';
import '../screens/split_bill_create_screen.dart';
import '../screens/withdraw_screen.dart';
import '../screens/split_bill_list_screen.dart';

/// ホーム画面の主要機能をカテゴリ別にまとめたメニュー。
class PaymentRequestActions extends StatelessWidget {
  const PaymentRequestActions({
    super.key,
    required this.balances,
    required this.onChanged,
    required this.onTransfer,
    required this.onSavedUsers,
  });

  final List<Balance> balances;

  /// 画面から戻ったときに残高・履歴を再取得するためのコールバック
  final Future<void> Function() onChanged;
  final VoidCallback onTransfer;
  final VoidCallback onSavedUsers;

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = _sectionSpacing(context);
    // 区切り線は置かず、余白だけでセクションを分ける。
    // 見出し→ボタンと同じ値にして、ボタンの上下を均等にする。
    final sectionGap = SizedBox(height: spacing);
    return Card(
      // 既定の左右マージンを外して、使える幅をボタンに回す
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: spacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActionSection(
              title: '割り勘',
              children: [
                _ActionItem(
                  icon: Icons.call_split,
                  label: '割り勘を作成',
                  onTap: () => _open(
                    context,
                    const SplitBillCreateScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.group_add,
                  label: '割り勘に参加',
                  onTap: () => _open(context, const JoinSplitBillScreen()),
                ),
                _ActionItem(
                  icon: Icons.groups,
                  label: '割り勘一覧',
                  onTap: () => _open(context, const SplitBillListScreen()),
                ),
              ],
            ),
            sectionGap,
            _ActionSection(
              title: '送金・出金',
              children: [
                _ActionItem(
                  icon: Icons.send_outlined,
                  label: '送金する',
                  onTap: onTransfer,
                ),
                _ActionItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '出金',
                  onTap: () => _open(
                    context,
                    WithdrawScreen(balances: balances),
                  ),
                ),
              ],
            ),
            sectionGap,
            _ActionSection(
              title: '請求',
              children: [
                _ActionItem(
                  icon: Icons.receipt_long,
                  label: '請求する',
                  onTap: () => _open(
                    context,
                    const RequestCreateScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.password,
                  label: 'コードで支払う',
                  onTap: () => _open(
                    context,
                    const PayRequestScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.fact_check_outlined,
                  label: '請求状況',
                  onTap: () => _open(
                    context,
                    const RequestListScreen(),
                  ),
                ),
              ],
            ),
            sectionGap,
            _ActionSection(
              title: 'ユーザー',
              children: [
                _ActionItem(
                  icon: Icons.people_outline,
                  label: 'ユーザー一覧',
                  onTap: onSavedUsers,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ボタンの並びを端末幅に合わせるための基準値。
const double _itemSpacing = 8;

/// 1 個あたりの最小幅。これを下回らない範囲で列数を決める。
const double _minItemWidth = 88;

/// 広い画面でボタンが間延びしないようにする上限。
const double _maxItemWidth = 132;

/// 1 行に並べる最大数。最も項目が多いセクション（3 個）がちょうど 1 行に
/// 収まるようにし、幅が余ったときは列を増やさずボタンを大きくする。
const int _maxColumns = 3;

/// 端末の高さから縦方向の詰め具合を求める（0 = 最も詰める / 1 = ゆったり）。
///
/// メニューは 4 セクションあり縦に長くなりやすいため、画面が低い端末では
/// 余白とアイコンを縮めて「ユーザー一覧」まで一画面に収まるようにする。
double _verticalDensity(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return ((height - 640) / 260).clamp(0.0, 1.0);
}

double _lerp(double compact, double roomy, double t) =>
    compact + (roomy - compact) * t;

/// 縦の余白はすべてこの値で統一する。
///
/// 見出し→ボタン と ボタン→次のセクション を同じ値にすることで、
/// 区切り線がなくてもボタンの上下が均等に見えるようにしている。
double _sectionSpacing(BuildContext context) =>
    _lerp(6, 12, _verticalDensity(context));

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final density = _verticalDensity(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: _sectionSpacing(context)),
        // 幅を固定するとデバイスごとに余白が変わって行が不揃いになるため、
        // 実際に使える幅から列数を求め、余りが出ないように等分する。
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final columns =
                ((available + _itemSpacing) / (_minItemWidth + _itemSpacing))
                    .floor()
                    .clamp(2, _maxColumns);
            // 下限は列数の計算側で担保済み。ここで下限を効かせると、
            // 極端に狭い画面のときに逆に幅が足りなくなるため上限だけを掛ける。
            final itemWidth =
                ((available - _itemSpacing * (columns - 1)) / columns)
                    .clamp(0.0, _maxItemWidth);
            return Wrap(
              spacing: _itemSpacing,
              runSpacing: _lerp(6, 12, density),
              children: [
                for (final child in children)
                  SizedBox(width: itemWidth, child: child),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 幅は _ActionSection が端末幅から決めて渡す。
    // アイコンは幅に合わせつつ、画面が低い端末ではさらに小さくする。
    final density = _verticalDensity(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = (constraints.maxWidth * 0.21).clamp(16.0, 24.0) *
            _lerp(0.82, 0.95, density);
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: _lerp(1, 6, density),
              horizontal: 4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: radius,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(icon, size: radius),
                ),
                SizedBox(height: _lerp(3, 8, density)),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
