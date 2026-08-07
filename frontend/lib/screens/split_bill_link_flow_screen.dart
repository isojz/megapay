import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/browser_url.dart';
import '../utils/money.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/app_bar_title.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'split_bill_payment_mock_screen.dart';

class SplitBillLinkFlowScreen extends StatefulWidget {
  const SplitBillLinkFlowScreen({
    super.key,
    required this.billCode,
    this.ranked = false,
  });

  final String billCode;
  final bool ranked;

  @override
  State<SplitBillLinkFlowScreen> createState() =>
      _SplitBillLinkFlowScreenState();
}

class _SplitBillLinkFlowScreenState extends State<SplitBillLinkFlowScreen> {
  late Future<PublicSplitBill> _future;
  PaymentMethod _paymentMethod = PaymentMethod.balance;
  SplitBillRank? _selectedRank;
  bool _rankConfirmed = false;
  bool _isContinuing = false;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.lookupPublicSplitBill(widget.billCode);
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException ? error.message : error.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<bool> _ensureAuthenticated() async {
    if (Supabase.instance.client.auth.currentSession != null) return true;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (loginContext) => LoginScreen(
        onAuthenticated: () => Navigator.of(loginContext).pop(true),
      ),
    ));
    return result == true;
  }

  Future<void> _continueToPayment() async {
    if (widget.ranked && _selectedRank == null) {
      _showError('支払いランクを選択してください');
      return;
    }
    if (!await _ensureAuthenticated() || !mounted) return;
    setState(() => _isContinuing = true);
    try {
      final joined = widget.ranked
          ? await ApiClient.instance
              .joinRankedSplitBill(widget.billCode, _selectedRank!.rankCode)
          : await ApiClient.instance.joinSplitBill(widget.billCode);
      final requestCode = joined.myRequestCode;
      if (requestCode == null || requestCode.isEmpty) {
        throw ApiException(409, '支払い用の請求を取得できませんでした');
      }
      if (!mounted) return;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SplitBillPaymentMockScreen(
          requestCode: requestCode,
          initialPaymentMethod: _paymentMethod,
          openedFromSharedLink: true,
        ),
      ));
      if (paid == true && mounted) {
        removeQueryParameter('split_code');
        removeQueryParameter('ranked_split_code');
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on ApiException catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  Widget _buildRankSelection(PublicSplitBill bill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('支払いランクを選択', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('${bill.title} / 請求者: ${bill.organizerName} さん'),
        const SizedBox(height: 16),
        ...bill.ranks.map((rank) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: _selectedRank == rank
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  onTap: () => setState(() => _selectedRank = rank),
                  leading: Icon(_selectedRank == rank
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  title: Text(rank.label),
                  subtitle: Text('ランクコード: ${rank.rankCode}'),
                  trailing: Text(
                    formatMoney(bill.currency, rank.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _selectedRank == null
              ? null
              : () => setState(() => _rankConfirmed = true),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('請求内容を確認する'),
        ),
      ],
    );
  }

  Widget _buildPaymentSelection(PublicSplitBill bill) {
    final authenticated = Supabase.instance.client.auth.currentSession != null;
    final amount = widget.ranked ? _selectedRank!.amount : bill.shareAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('請求情報', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.groups_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: Text(bill.title),
            subtitle: Text(
              '請求者: ${bill.organizerName} さん\n'
              '${bill.participantCount}人で割り勘'
              '${widget.ranked ? '\n${_selectedRank!.label}' : ''}',
            ),
            isThreeLine: widget.ranked,
            trailing: Text(
              formatMoney(bill.currency, amount),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (widget.ranked)
          TextButton.icon(
            onPressed: () => setState(() => _rankConfirmed = false),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('ランクを選び直す'),
          ),
        const SizedBox(height: 12),
        Text('支払い方法', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        PaymentMethodSelector(
          methods: PaymentMethod.values,
          selected: _paymentMethod,
          onSelected: _isContinuing
              ? null
              : (method) => setState(() => _paymentMethod = method),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _isContinuing ? null : _continueToPayment,
          icon: _isContinuing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(authenticated ? Icons.arrow_forward : Icons.login),
          label: Text(authenticated ? '支払いへ進む' : 'ログインもしくは登録して支払いへ進む'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(
          icon: Icons.payments_outlined,
          title: '割り勘の支払い',
        ),
      ),
      body: FutureBuilder<PublicSplitBill>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final bill = snapshot.data!;
          final needsRank = widget.ranked && !_rankConfirmed;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: needsRank
                    ? _buildRankSelection(bill)
                    : _buildPaymentSelection(bill),
              ),
            ),
          );
        },
      ),
    );
  }
}
