import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../payments/data/payments_api_repository.dart';
import '../../../shared/presentation/cubit/profile_cubit.dart';
import '../cubit/wallet_cubit.dart';

/// Modal bottom sheet allowing workers to configure and update
/// their UPI ID and Bank Account details for withdrawals.
class WorkerPayoutAccountSheet extends StatefulWidget {
  const WorkerPayoutAccountSheet({
    super.key,
    this.initialMethod,
    this.initialUpi,
    this.initialAccountName,
    this.initialAccountNumber,
    this.initialIfsc,
    this.initialBankName,
    this.onSaved,
  });

  final String? initialMethod;
  final String? initialUpi;
  final String? initialAccountName;
  final String? initialAccountNumber;
  final String? initialIfsc;
  final String? initialBankName;
  final VoidCallback? onSaved;

  static Future<bool?> show(
    BuildContext context, {
    String? initialMethod,
    String? initialUpi,
    String? initialAccountName,
    String? initialAccountNumber,
    String? initialIfsc,
    String? initialBankName,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MultiBlocProvider(
        providers: [
          tryProvideWalletCubit(context),
          tryProvideProfileCubit(context),
        ],
        child: WorkerPayoutAccountSheet(
          initialMethod: initialMethod,
          initialUpi: initialUpi,
          initialAccountName: initialAccountName,
          initialAccountNumber: initialAccountNumber,
          initialIfsc: initialIfsc,
          initialBankName: initialBankName,
          onSaved: onSaved,
        ),
      ),
    );
  }

  static BlocProvider<WalletCubit> tryProvideWalletCubit(BuildContext context) {
    try {
      final cubit = context.read<WalletCubit>();
      return BlocProvider<WalletCubit>.value(value: cubit);
    } catch (_) {
      return BlocProvider<WalletCubit>(create: (_) => WalletCubit());
    }
  }

  static BlocProvider<ProfileCubit> tryProvideProfileCubit(BuildContext context) {
    try {
      final cubit = context.read<ProfileCubit>();
      return BlocProvider<ProfileCubit>.value(value: cubit);
    } catch (_) {
      return BlocProvider<ProfileCubit>(create: (_) => ProfileCubit());
    }
  }

  @override
  State<WorkerPayoutAccountSheet> createState() => _WorkerPayoutAccountSheetState();
}

class _WorkerPayoutAccountSheetState extends State<WorkerPayoutAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _payoutMethod; // 'upi' or 'bank'

  late final TextEditingController _upiController;
  late final TextEditingController _accountHolderController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _confirmAccountController;
  late final TextEditingController _ifscController;
  late final TextEditingController _bankNameController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final method = widget.initialMethod?.toLowerCase();
    _payoutMethod = (method == 'bank') ? 'bank' : 'upi';

    _upiController = TextEditingController(text: widget.initialUpi ?? '');
    _accountHolderController =
        TextEditingController(text: widget.initialAccountName ?? '');
    _accountNumberController =
        TextEditingController(text: widget.initialAccountNumber ?? '');
    _confirmAccountController =
        TextEditingController(text: widget.initialAccountNumber ?? '');
    _ifscController = TextEditingController(text: widget.initialIfsc ?? '');
    _bankNameController = TextEditingController(text: widget.initialBankName ?? '');
  }

  @override
  void dispose() {
    _upiController.dispose();
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _confirmAccountController.dispose();
    _ifscController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final payments = PaymentsApiRepository();
      if (_payoutMethod == 'upi') {
        await payments.updatePayoutDetails(
          payoutMethod: 'upi',
          upiId: _upiController.text.trim(),
        );
      } else {
        await payments.updatePayoutDetails(
          payoutMethod: 'bank',
          accountHolderName: _accountHolderController.text.trim(),
          accountNumber: _accountNumberController.text.trim(),
          ifscCode: _ifscController.text.trim().toUpperCase(),
          bankName: _bankNameController.text.trim(),
        );
      }

      if (!mounted) return;

      try {
        context.read<WalletCubit>().load();
      } catch (_) {}
      try {
        context.read<ProfileCubit>().load();
      } catch (_) {}

      widget.onSaved?.call();
      ToastUtils.showToast(
        context: context,
        message: 'Payout details saved successfully',
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        ToastUtils.showError(context: context, message: e.message);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(
          context: context,
          message: ApiException.fromError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = context.scheme;
    final primaryColor = scheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.account_balance_rounded,
                          color: primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payout & Withdrawal Account',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Earnings are credited directly to this account',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Method Selector Tabs
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MethodTab(
                            title: 'UPI ID (Instant)',
                            icon: Icons.bolt_rounded,
                            isSelected: _payoutMethod == 'upi',
                            primaryColor: primaryColor,
                            onTap: () => setState(() => _payoutMethod = 'upi'),
                          ),
                        ),
                        Expanded(
                          child: _MethodTab(
                            title: 'Bank Account',
                            icon: Icons.account_balance_outlined,
                            isSelected: _payoutMethod == 'bank',
                            primaryColor: primaryColor,
                            onTap: () => setState(() => _payoutMethod = 'bank'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Content for selected method
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _payoutMethod == 'upi'
                      ? _buildUpiSection(context, isDark, primaryColor)
                      : _buildBankSection(context, isDark, primaryColor),
                ),

                const SizedBox(height: 20),

                // Trust Notice Banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your payout details are securely verified with RBI-regulated banking gateways. No processing fees on withdrawals.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Save button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Payout Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpiSection(BuildContext context, bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          'UPI ID / VPA',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _upiController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'e.g. 9876543210@paytm or worker@okhdfcbank',
            prefixIcon: Icon(Icons.alternate_email_rounded, color: primaryColor),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Please enter your UPI ID';
            if (!v.contains('@') || v.length < 5) {
              return 'Enter a valid UPI ID (e.g. mobile@upi)';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Withdrawals are transferred instantly (within 10 seconds) into your UPI-linked bank account.',
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildBankSection(BuildContext context, bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        // Account Holder Name
        Text(
          'Account Holder Name',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _accountHolderController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'As per passbook or bank records',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter account holder name';
            }
            return null;
          },
        ),

        const SizedBox(height: 12),

        // Account Number
        Text(
          'Bank Account Number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _accountNumberController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Enter 9 to 18 digits account number',
            prefixIcon: const Icon(Icons.numbers_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Please enter account number';
            if (v.length < 8) return 'Account number is too short';
            return null;
          },
        ),

        const SizedBox(height: 12),

        // Confirm Account Number
        Text(
          'Re-enter Account Number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _confirmAccountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Re-enter same account number',
            prefixIcon: const Icon(Icons.check_circle_outline_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          validator: (value) {
            if (value?.trim() != _accountNumberController.text.trim()) {
              return 'Account numbers do not match';
            }
            return null;
          },
        ),

        const SizedBox(height: 12),

        // IFSC Code
        Text(
          'IFSC Code',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _ifscController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'e.g. SBIN0001234, HDFC0000456',
            prefixIcon: const Icon(Icons.business_rounded),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          validator: (value) {
            final v = value?.trim().toUpperCase() ?? '';
            if (v.isEmpty) return 'Please enter IFSC code';
            if (v.length != 11) return 'IFSC code must be exactly 11 characters';
            return null;
          },
        ),

        const SizedBox(height: 12),

        // Bank Name (Optional)
        Text(
          'Bank Name (Optional)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _bankNameController,
          decoration: InputDecoration(
            hintText: 'e.g. State Bank of India, HDFC Bank',
            prefixIcon: const Icon(Icons.account_balance_outlined),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
