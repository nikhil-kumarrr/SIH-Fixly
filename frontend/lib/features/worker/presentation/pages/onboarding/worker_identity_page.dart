import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../../app/router/route_names.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/theme_x.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/network/api_exception.dart';
import '../../../../../core/utils/input_formatters.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/core_widgets.dart';
import '../../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../cubit/worker_onboarding_cubit.dart';
import 'worker_identity_photo_widgets.dart';
import 'worker_onboarding_layout.dart';
import '../../../../../core/utils/toast_utils.dart';
import '../../../../../core/widgets/location_typeahead_field.dart';
import '../../../../../core/constants/india_locations.dart';

class WorkerIdentityPage extends StatefulWidget {
  const WorkerIdentityPage({super.key});

  @override
  State<WorkerIdentityPage> createState() => _WorkerIdentityPageState();
}

class _WorkerIdentityPageState extends State<WorkerIdentityPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _dobController;
  late final TextEditingController _stateController;
  late final TextEditingController _districtController;
  late final TextEditingController _aadhaarController;
  late final TextEditingController _panController;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<WorkerOnboardingCubit>();
    final session = context.read<AppSessionCubit>().state;
    final user = context.read<AppSessionCubit>().currentUser;

    cubit.seedFromSession(
      name: (user?.name.isNotEmpty ?? false)
          ? user!.name
          : ((session.pendingSignupName?.isNotEmpty ?? false)
              ? session.pendingSignupName
              : null),
      phone: (session.phone?.isNotEmpty ?? false)
          ? session.phone
          : user?.phone,
      email: (session.email?.isNotEmpty ?? false)
          ? session.email
          : user?.email,
    );

    final data = cubit.state.formData;
    _nameController = TextEditingController(text: data.fullName);
    _phoneController = TextEditingController(text: data.phone);
    _emailController = TextEditingController(text: data.email);
    _dobController = TextEditingController(
      text: data.dateOfBirth == null
          ? ''
          : DateFormat('dd MMM yyyy').format(data.dateOfBirth!),
    );
    _stateController = TextEditingController(text: data.state);
    _districtController = TextEditingController(text: data.district);
    _aadhaarController = TextEditingController(text: data.aadhaar);
    _panController = TextEditingController(text: data.pan);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _stateController.dispose();
    _districtController.dispose();
    _aadhaarController.dispose();
    _panController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final cubit = context.read<WorkerOnboardingCubit>();
    final now = DateTime.now();
    final initial = cubit.state.formData.dateOfBirth ??
        DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select date of birth',
    );
    if (picked == null || !mounted) return;
    cubit.updateDateOfBirth(picked);
    _dobController.text = DateFormat('dd MMM yyyy').format(picked);
  }

  Future<void> _captureSelfie(WorkerOnboardingCubit cubit) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    cubit.captureSelfie(imageUrl: file.path);
  }

  Future<void> _continue() async {
    final cubit = context.read<WorkerOnboardingCubit>();
    cubit
      ..updateFullName(_nameController.text)
      ..updatePhone(_phoneController.text)
      ..updateState(_stateController.text)
      ..updateDistrict(_districtController.text)
      ..updateAadhaar(_aadhaarController.text)
      ..updatePan(_panController.text);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final error = cubit.validateStep(1);
    if (error != null) {
      ToastUtils.showError(context: context, message: ApiException.userFacingMessage(error));
      return;
    }

    final success = await cubit.submitIdentity();
    if (!success) return;

    HapticFeedback.lightImpact();
    cubit.setStep(1);
    if (mounted) context.push(RouteNames.workerOnboardingWork);
  }

  Widget _stagger(Widget child, int index) {
    return child
        .animate()
        .fadeIn(
          delay: (60 * index).ms,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.05,
          delay: (60 * index).ms,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorkerOnboardingCubit>();

    return BlocBuilder<WorkerOnboardingCubit, WorkerOnboardingState>(
      builder: (context, state) {
        final data = state.formData;
        final captured = data.selfieVerified;
        final imageUrl = data.selfieImageUrl;

        return WorkerOnboardingLayout(
          step: 1,
          title: context.l10n.identityKyc,
          onContinue: _continue,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stagger(
                  Text(
                    'Confirm your details and upload ID photos for verification.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  0,
                ),
                if (state.errorMessage == 'DUPLICATE_DOCUMENT')
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This Aadhaar or PAN is already linked to another account.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                _stagger(
                  OnboardingSection(
                    title: context.l10n.personalDetails,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          controller: _nameController,
                          label: 'Full name',
                          hint: 'Rajesh Kumar',
                          textCapitalization: TextCapitalization.words,
                          validator: (v) =>
                              Validators.requiredField(v, label: 'Full name'),
                          onChanged: cubit.updateFullName,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _dobController,
                          label: 'Date of birth',
                          hint: 'Select date',
                          readOnly: true,
                          onTap: _pickDob,
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                          validator: (_) => data.dateOfBirth == null
                              ? 'Date of birth is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gender',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        GenderSelector(
                          value: data.gender,
                          onChanged: cubit.updateGender,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _phoneController,
                          label: 'Phone number',
                          hint: '10-digit mobile',
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          validator: Validators.phone,
                          onChanged: cubit.updatePhone,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          readOnly: true,
                          enabled: false,
                          suffixIcon: Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Signed-up email cannot be changed here.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.muted,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        LocationTypeAheadField(
                          controller: _stateController,
                          label: 'State',
                          hint: 'Type to search state',
                          validator: (v) =>
                              Validators.requiredField(v, label: 'State'),
                          suggestionsFor: (query) async =>
                              IndiaLocations.filterStates(query),
                          onChanged: cubit.updateState,
                          onSelected: (state) {
                            cubit.updateState(state);
                            final districts =
                                IndiaLocations.districtsFor(state);
                            final current = _districtController.text.trim();
                            final stillValid = districts.any(
                              (d) =>
                                  d.toLowerCase() == current.toLowerCase(),
                            );
                            if (!stillValid) {
                              _districtController.clear();
                              cubit.updateDistrict('');
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        LocationTypeAheadField(
                          controller: _districtController,
                          label: 'District',
                          hint: 'Type to search district',
                          validator: (v) =>
                              Validators.requiredField(v, label: 'District'),
                          suggestionsFor: (query) async {
                            final state = _stateController.text.trim();
                            if (state.isEmpty) return const <String>[];
                            return IndiaLocations.filterDistricts(
                              state,
                              query,
                            );
                          },
                          onChanged: cubit.updateDistrict,
                          onSelected: cubit.updateDistrict,
                        ),
                      ],
                    ),
                  ),
                  1,
                ),
                _stagger(
                  OnboardingSection(
                    title: context.l10n.aadhaarVerification,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          controller: _aadhaarController,
                          label: 'Aadhaar number',
                          hint: '1234 5678 9012',
                          keyboardType: TextInputType.number,
                          maxLength: 14,
                          validator: Validators.aadhaar,
                          onChanged: cubit.updateAadhaar,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aadhaar photos',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        DocumentPhotoPair(
                          frontPath: data.aadhaarFrontPath,
                          backPath: data.aadhaarBackPath,
                          onFrontPicked: cubit.updateAadhaarFrontPath,
                          onBackPicked: cubit.updateAadhaarBackPath,
                        ),
                        const SizedBox(height: 12),
                        const AppCard(
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Data encrypted. Used only for verification.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  2,
                ),
                _stagger(
                  OnboardingSection(
                    title: context.l10n.panVerification,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          controller: _panController,
                          label: 'PAN number',
                          hint: 'ABCDE1234F',
                          maxLength: 10,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: const [
                            UpperCaseTextFormatter(),
                          ],
                          validator: Validators.pan,
                          onChanged: cubit.updatePan,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Format: 5 letters + 4 digits + 1 letter. '
                          '4th letter must be P for individuals.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.muted,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'PAN photos',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        DocumentPhotoPair(
                          frontPath: data.panFrontPath,
                          backPath: data.panBackPath,
                          onFrontPicked: cubit.updatePanFrontPath,
                          onBackPicked: cubit.updatePanBackPath,
                        ),
                      ],
                    ),
                  ),
                  3,
                ),
                _stagger(
                  const PhotoGuidelinesCard(),
                  4,
                ),
                const SizedBox(height: 24),
                _stagger(
                  OnboardingSection(
                    title: context.l10n.selfieVerification,
                    child: Column(
                      children: [
                        Text(
                          'Clear selfie for face match with PAN and Aadhaar.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: context.scheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: captured
                                  ? AppColors.success
                                  : context.hairline,
                              width: 3,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: captured &&
                                  imageUrl != null &&
                                  imageUrl.isNotEmpty
                              ? (imageUrl.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      errorWidget: (_, _, _) => Icon(
                                        Icons.face_retouching_natural,
                                        size: 56,
                                        color: AppColors.textMuted,
                                      ),
                                    )
                                  : Image.file(
                                      File(imageUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        Icons.face_retouching_natural,
                                        size: 56,
                                        color: AppColors.textMuted,
                                      ),
                                    ))
                              : Icon(
                                  Icons.face_retouching_natural,
                                  size: 56,
                                  color: AppColors.textMuted,
                                ),
                        ),
                        const SizedBox(height: 16),
                        SecondaryButton(
                          label: captured ? 'Retake selfie' : 'Capture selfie',
                          onPressed: captured
                              ? cubit.clearSelfie
                              : () => _captureSelfie(cubit),
                        ),
                      ],
                    ),
                  ),
                  5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
