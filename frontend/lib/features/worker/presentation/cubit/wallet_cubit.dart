import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../shared/models/models.dart';
import '../../../payments/data/payments_api_repository.dart';

part 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  WalletCubit({PaymentsApiRepository? paymentsRepository})
      : _payments = paymentsRepository ?? PaymentsApiRepository(),
        super(const WalletState());

  final PaymentsApiRepository _payments;

  Future<void> load() async {
    emit(state.copyWith(status: WalletStatus.loading, clearError: true));
    try {
      final snap = await _payments.workerWallet();
      final txs = snap.history.map((e) {
        final amount = (e['amount'] as num?)?.toDouble() ?? 0;
        final transactionId = (e['transactionId'] ?? e['paymentId'] ?? '')
            .toString();
        final type = (e['type'] ?? 'CREDIT').toString();
        final rawDescription = (e['description'] ?? '').toString();
        final description = rawDescription.isNotEmpty
            ? rawDescription
            : transactionId.isNotEmpty
                ? '$type • $transactionId'
                : '$type • Payment';
        return WalletTransaction(
          id: (e['_id'] ?? e['id'] ?? e['orderId'] ?? transactionId)
              .toString(),
          label: description,
          amount: amount.abs(),
          isCredit: type.toUpperCase() != 'DEBIT',
          date: DateTime.tryParse(e['createdAt']?.toString() ?? '') ??
              DateTime.now(),
          transactionId:
              transactionId.isNotEmpty ? transactionId : null,
          status: e['status']?.toString(),
          type: type,
        );
      }).toList();
      emit(
        WalletState(
          status: WalletStatus.loaded,
          balance: snap.balance,
          totalEarnings: snap.totalEarnings,
          pendingBalance: snap.pendingBalance,
          transactions: txs,
          payoutMethod: snap.payoutMethod,
          upiId: snap.upiId,
          accountHolderName: snap.accountHolderName,
          bankAccount: snap.bankAccount,
          ifscCode: snap.ifscCode,
          bankName: snap.bankName,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: WalletStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: WalletStatus.failure, error: ApiException.fromError(e)));
    }
  }

  Future<bool> withdraw(double amount) async {
    emit(state.copyWith(isWithdrawing: true, clearError: true, clearSuccess: true));
    try {
      await _payments.withdraw(amount);
      await load();
      emit(state.copyWith(
        isWithdrawing: false,
        actionSuccessMessage:
            'Withdrawal request for ₹${amount.toStringAsFixed(0)} submitted successfully',
      ));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(isWithdrawing: false, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(isWithdrawing: false, error: ApiException.fromError(e)));
      return false;
    }
  }

  Future<bool> updatePayoutDetails({
    required String payoutMethod,
    String? upiId,
    String? accountHolderName,
    String? accountNumber,
    String? ifscCode,
    String? bankName,
  }) async {
    emit(state.copyWith(isUpdatingPayout: true, clearError: true, clearSuccess: true));
    try {
      await _payments.updatePayoutDetails(
        payoutMethod: payoutMethod,
        upiId: upiId,
        accountHolderName: accountHolderName,
        accountNumber: accountNumber,
        ifscCode: ifscCode,
        bankName: bankName,
      );
      await load();
      emit(state.copyWith(
        isUpdatingPayout: false,
        actionSuccessMessage: 'Payout destination updated successfully',
      ));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdatingPayout: false, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(isUpdatingPayout: false, error: ApiException.fromError(e)));
      return false;
    }
  }
}
