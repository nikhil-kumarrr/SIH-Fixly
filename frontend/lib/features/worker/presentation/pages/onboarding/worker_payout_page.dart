import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/route_names.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../app/theme/theme_x.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/network/api_exception.dart';
import '../../../../../core/utils/input_formatters.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/core_widgets.dart';
import '../../../../../shared/models/models.dart';
import '../../../../../shared/widgets/shared_widgets.dart';
import '../../cubit/worker_onboarding_cubit.dart';
import 'worker_onboarding_layout.dart';
import '../../../../../core/utils/toast_utils.dart';

class WorkerPayoutPage extends StatefulWidget {
  const WorkerPayoutPage({super.key});

  @override
  State<WorkerPayoutPage> createState() => _WorkerPayoutPageState();
}

class _WorkerPayoutPageState extends State<WorkerPayoutPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _uanController;
  late final TextEditingController _holderController;
  late final TextEditingController _bankController;
  late final TextEditingController _confirmBankController;
  late final TextEditingController _ifscController;
  late final TextEditingController _upiController;

  @override
  void initState() {
    super.initState();
    final data = context.read<WorkerOnboardingCubit>().state.formData;
    _uanController = TextEditingController(text: data.eshramUan);
    _holderController = TextEditingController(text: data.accountHolderName);
    _bankController = TextEditingController(text: data.bankAccount);
    _confirmBankController = TextEditingController(text: data.bankAccount);
    _ifscController = TextEditingController(text: data.ifscCode);
    _upiController = TextEditingController(text: data.upiId);
  }

  @override
  void dispose() {
    _uanController.dispose();
    _holderController.dispose();
    _bankController.dispose();
    _confirmBankController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  void _syncBankToCubit() {
    final cubit = context.read<WorkerOnboardingCubit>();
    cubit
      ..updateAccountHolderName(_holderController.text)
      ..updateBankAccount(_bankController.text)
      ..updateIfscCode(_ifscController.text);
  }

  Future<void> _verifyBank() async {
    _syncBankToCubit();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cubit = context.read<WorkerOnboardingCubit>();
    final error = await cubit.verifyBankAccount();
    if (!mounted) return;
    // Success: green "verified" label under field — no toast.
    if (error != null) {
      ToastUtils.showError(context: context, message: error);
    }
  }

  Future<void> _verifyUpi() async {
    final cubit = context.read<WorkerOnboardingCubit>();
    cubit.updateUpiId(_upiController.text);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final error = await cubit.verifyUpiId();
    if (!mounted) return;
    // Success: green "UPI ID verified" under field — no toast.
    if (error != null) {
      ToastUtils.showError(context: context, message: error);
    }
  }

  Future<void> _submit() async {
    final cubit = context.read<WorkerOnboardingCubit>();
    cubit.updateEshramUan(_uanController.text);
    if (cubit.state.formData.payoutMethod == PayoutMethod.bank) {
      _syncBankToCubit();
    } else {
      cubit.updateUpiId(_upiController.text);
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final error = cubit.validateStep(3);
    if (error != null) {
      ToastUtils.showError(context: context, message: ApiException.userFacingMessage(error));
      return;
    }

    cubit.setStep(3);
    final ok = await cubit.submitOnboarding();
    if (!mounted) return;
    if (!ok) {
      final msg = cubit.state.errorMessage;
      ToastUtils.showError(context: context, message: ApiException.userFacingMessage(
              msg ?? 'Could not submit worker profile',
            ),);
      return;
    }
    context.go(RouteNames.workerOnboardingStatus);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorkerOnboardingCubit>();

    return BlocBuilder<WorkerOnboardingCubit, WorkerOnboardingState>(
      builder: (context, state) {
        final method = state.formData.payoutMethod;

        return WorkerOnboardingLayout(
          step: 3,
          title: context.l10n.payoutWelfare,
          continueLabel: 'Submit for review',
          loading: state.status == WorkerOnboardingStatus.loading,
          onContinue: _submit,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'e-Shram welfare plus bank or UPI for payouts.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                OnboardingSection(
                  title: context.l10n.welfareInsurance,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const InsuranceBadge(),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'e-Shram registration links you to PMSBY accident cover '
                        '(₹2,00,000) and cooperative welfare benefits.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('I have an e-Shram UAN'),
                        value: state.formData.hasEshram,
                        onChanged: cubit.updateHasEshram,
                      ),
                      if (state.formData.hasEshram) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppTextField(
                          controller: _uanController,
                          label: 'e-Shram UAN',
                          hint: 'ESHRAM1234567890',
                          onChanged: cubit.updateEshramUan,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      const AppCard(
                        child: Text(
                          'No UAN yet? Cooperative will help register after approval.',
                        ),
                      ),
                    ],
                  ),
                ),
                OnboardingSection(
                  title: context.l10n.bankUpi,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose how you want to receive payouts.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<PayoutMethod>(
                          segments: const [
                            ButtonSegment(
                              value: PayoutMethod.bank,
                              label: Text('Bank'),
                              icon: Icon(Icons.account_balance_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: PayoutMethod.upi,
                              label: Text('UPI'),
                              icon: Icon(Icons.qr_code_rounded, size: 18),
                            ),
                          ],
                          selected: {method},
                          showSelectedIcon: false,
                          onSelectionChanged: (selected) {
                            cubit.setPayoutMethod(selected.first);
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.comfortable,
                            animationDuration:
                                const Duration(milliseconds: 280),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: method == PayoutMethod.bank
                              ? _BankPayoutFields(
                                  key: const ValueKey('bank'),
                                  holderController: _holderController,
                                  bankController: _bankController,
                                  confirmBankController:
                                      _confirmBankController,
                                  ifscController: _ifscController,
                                  verified: state.formData.bankVerified,
                                  verifying: state.verifyingPayout,
                                  onHolderChanged: cubit.updateAccountHolderName,
                                  onAccountChanged: cubit.updateBankAccount,
                                  onIfscChanged: cubit.updateIfscCode,
                                  onVerify: _verifyBank,
                                )
                              : _UpiPayoutFields(
                                  key: const ValueKey('upi'),
                                  upiController: _upiController,
                                  verified: state.formData.upiVerified,
                                  verifying: state.verifyingPayout,
                                  onUpiChanged: cubit.updateUpiId,
                                  onVerify: _verifyUpi,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BankPayoutFields extends StatelessWidget {
  const _BankPayoutFields({
    required this.holderController,
    required this.bankController,
    required this.confirmBankController,
    required this.ifscController,
    required this.verified,
    required this.verifying,
    required this.onHolderChanged,
    required this.onAccountChanged,
    required this.onIfscChanged,
    required this.onVerify,
    super.key,
  });

  final TextEditingController holderController;
  final TextEditingController bankController;
  final TextEditingController confirmBankController;
  final TextEditingController ifscController;
  final bool verified;
  final bool verifying;
  final ValueChanged<String> onHolderChanged;
  final ValueChanged<String> onAccountChanged;
  final ValueChanged<String> onIfscChanged;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: holderController,
            label: 'Account Holder Name',
            hint: 'As per bank records',
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                Validators.requiredField(v, label: 'Account holder name'),
            onChanged: onHolderChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: bankController,
            label: 'Account Number',
            hint: 'Enter Account Number',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(18),
            ],
            validator: Validators.bankAccount,
            onChanged: onAccountChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: confirmBankController,
            label: 'Confirm Account Number',
            hint: 'Re-enter Account Number',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(18),
            ],
            validator: (value) {
              final base = Validators.bankAccount(value);
              if (base != null) return base;
              if (value != bankController.text) {
                return 'Account numbers do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: ifscController,
            label: 'IFSC Code',
            hint: 'E.G. HDFC0001234',
            maxLength: 11,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseTextFormatter()],
            validator: Validators.ifsc,
            onChanged: onIfscChanged,
            suffixIcon: verified
                ? const Icon(Icons.verified_rounded, color: AppColors.success)
                : TextButton(
                    onPressed: verifying ? null : onVerify,
                    child: verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Verify',
                            style: TextStyle(
                              color: context.scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
          ),
          if (verified) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bank account verified',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.success,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpiPayoutFields extends StatelessWidget {
  const _UpiPayoutFields({
    required this.upiController,
    required this.verified,
    required this.verifying,
    required this.onUpiChanged,
    required this.onVerify,
    super.key,
  });

  final TextEditingController upiController;
  final bool verified;
  final bool verifying;
  final ValueChanged<String> onUpiChanged;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: upiController,
            label: 'UPI ID',
            hint: 'name@upi',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.upi,
            onChanged: onUpiChanged,
            suffixIcon: verified
                ? const Icon(Icons.verified_rounded, color: AppColors.success)
                : TextButton(
                    onPressed: verifying ? null : onVerify,
                    child: verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Verify',
                            style: TextStyle(
                              color: context.scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
          ),
          if (verified) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'UPI ID verified',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.success,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
