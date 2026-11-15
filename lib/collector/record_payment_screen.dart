import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/gradient_button.dart';
import '../common/money.dart';
import 'collector_models.dart';

/// What the collector entered, passed on to the confirm screen.
@immutable
class PaymentDraft {
  const PaymentDraft({
    required this.member,
    required this.account,
    required this.amount,
    this.note,
  });

  final CollectorMember member;
  final MemberAccount account;
  final Cedis amount;
  final String? note;

  PaymentType get type => account.type;
}

/// Step 2 of recording a payment (design P1): the type, amount and an
/// optional note for the chosen member.
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.member,
    required this.onContinue,
  });

  final CollectorMember member;
  final void Function(BuildContext context, PaymentDraft draft) onContinue;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late PaymentType? _type = widget.member.paymentTypes.firstOrNull;

  // The backend stores notes up to 500 characters.
  static const _maxNote = 500;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _continue() {
    final type = _type;
    if (type == null || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final note = _note.text.trim();
    widget.onContinue(
      context,
      PaymentDraft(
        member: widget.member,
        account: widget.member.accountFor(type)!,
        amount: Cedis.tryParse(_amount.text)!,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  static String? _validateAmount(String? text) {
    if (text == null || text.trim().isEmpty) return 'Enter the amount';
    final amount = Cedis.tryParse(text);
    if (amount == null) return 'Enter an amount like 50 or 50.50';
    if (!amount.isPositive) return 'The amount must be more than GH₵ 0.00';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final types = widget.member.paymentTypes;
    final type = _type;

    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  widget.member.name,
                  key: const Key('record.memberName'),
                  style: textTheme.titleMedium,
                ),
                subtitle: const Text('Member'),
              ),
            ),
            const SizedBox(height: 16),
            if (types.isEmpty)
              Text(
                "This member has no savings or shares account you can pay "
                'into. Ask the office.',
                style: textTheme.bodyMedium?.copyWith(color: scheme.error),
              )
            else ...[
              SegmentedButton<PaymentType>(
                key: const Key('record.type'),
                showSelectedIcon: false,
                segments: [
                  for (final t in types)
                    ButtonSegment(
                      value: t,
                      label: Text(t.label),
                      icon: Icon(
                        t == PaymentType.savings
                            ? Icons.savings_outlined
                            : Icons.pie_chart_outline,
                      ),
                    ),
                ],
                selected: {?type},
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.single),
              ),
              const SizedBox(height: 8),
              if (type != null)
                Text(
                  '${type.description} · account '
                  '${widget.member.accountFor(type)!.accountNumber}',
                  key: const Key('record.account'),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('record.amount'),
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Cedis and pesewas only: up to 9 digits, a point, 2 more.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                  ),
                ],
                style: textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'GH₵ ',
                  hintText: '0.00',
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('record.note'),
                controller: _note,
                maxLength: _maxNote,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                key: const Key('record.continue'),
                onPressed: _continue,
                child: const Text('Continue'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
