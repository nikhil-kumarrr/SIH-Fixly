import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/constants/india_locations.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/widgets/fixly_map_view.dart';
import '../../../../core/widgets/location_typeahead_field.dart';
import '../cubit/profile_cubit.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _emergencyRelationController;

  // Address & Worker controllers
  late final TextEditingController _workAddressController;
  late final TextEditingController _rateController;
  late final TextEditingController _experienceController;
  late final TextEditingController _bioController;
  late final TextEditingController _upiController;
  late final TextEditingController _stateController;
  late final TextEditingController _cityController;
  late final TextEditingController _pincodeController;

  String? _selectedCategory;
  String? _gender;
  late Set<String> _skills;
  bool _initializedFromState = false;

  // Map pinpoint state
  bool _showMap = false;
  bool _isGeocoding = false;
  MapCoordinate? _pinnedCoordinate;
  String? _lastPinpointAddress;

  @override
  void initState() {
    super.initState();
    final state = context.read<ProfileCubit>().state;
    _nameController = TextEditingController(text: state.name);
    _phoneController = TextEditingController(text: state.phone);
    _emergencyNameController =
        TextEditingController(text: state.emergencyContactName);
    _emergencyPhoneController =
        TextEditingController(text: state.emergencyContactPhone);
    _emergencyRelationController =
        TextEditingController(text: state.emergencyContactRelation);

    _workAddressController = TextEditingController(text: state.workAddress);
    _rateController = TextEditingController(
      text: state.hourlyRate > 0 ? state.hourlyRate.toStringAsFixed(0) : '',
    );
    _experienceController = TextEditingController(
      text: state.experienceYears > 0 ? state.experienceYears.toString() : '',
    );
    _bioController = TextEditingController(text: state.bio);
    _upiController = TextEditingController(text: state.upiId);
    _stateController = TextEditingController(text: state.homeState);
    _cityController = TextEditingController(text: state.homeCity);
    _pincodeController = TextEditingController(text: state.homePincode);
    _selectedCategory = state.category.isNotEmpty ? state.category : null;
    _gender = state.gender.isNotEmpty ? state.gender : null;
    _skills = {
      ...state.skills,
      if (state.category.isNotEmpty) state.category,
    };

    if (AppLocation.instance.hasFix) {
      _pinnedCoordinate = AppLocation.instance.asCoordinate;
    }

    if (state.name.isEmpty) {
      context.read<ProfileCubit>().load();
    } else {
      _initializedFromState = true;
    }
  }

  void _syncFromState(ProfileState state) {
    if (_initializedFromState || state.status == ProfileStatus.loading) return;
    _nameController.text = state.name;
    _phoneController.text = state.phone;
    _emergencyNameController.text = state.emergencyContactName;
    _emergencyPhoneController.text = state.emergencyContactPhone;
    _emergencyRelationController.text = state.emergencyContactRelation;
    _workAddressController.text = state.workAddress;
    _rateController.text =
        state.hourlyRate > 0 ? state.hourlyRate.toStringAsFixed(0) : '';
    _experienceController.text =
        state.experienceYears > 0 ? state.experienceYears.toString() : '';
    _bioController.text = state.bio;
    _upiController.text = state.upiId;
    _stateController.text = state.homeState;
    _cityController.text = state.homeCity;
    _pincodeController.text = state.homePincode;
    if (_selectedCategory == null && state.category.isNotEmpty) {
      _selectedCategory = state.category;
    }
    if (_gender == null && state.gender.isNotEmpty) {
      _gender = state.gender;
    }
    if (_skills.isEmpty && state.skills.isNotEmpty) {
      _skills = state.skills.toSet();
    }
    _initializedFromState = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationController.dispose();
    _workAddressController.dispose();
    _rateController.dispose();
    _experienceController.dispose();
    _bioController.dispose();
    _upiController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _onMapPinpoint(MapCoordinate coord) async {
    setState(() {
      _pinnedCoordinate = coord;
      _isGeocoding = true;
    });

    try {
      final placemarks =
          await Geocoding().placemarkFromCoordinates(coord.lat, coord.lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        final streetParts = [p.name, p.street, p.subLocality]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != p.locality && s != p.postalCode)
            .toSet()
            .toList();
        final street = streetParts.join(', ');

        final city = (p.locality ?? p.subAdministrativeArea ?? '').trim();
        final pincode = (p.postalCode ?? '').trim();
        final fullAddress = [
          if (street.isNotEmpty) street,
          if (city.isNotEmpty) city,
          if (p.administrativeArea != null &&
              p.administrativeArea!.trim().isNotEmpty)
            p.administrativeArea!.trim(),
          if (pincode.isNotEmpty) pincode,
        ].join(', ');

        if (!mounted) return;
        setState(() {
          _isGeocoding = false;
          _lastPinpointAddress = fullAddress.isNotEmpty ? fullAddress : street;
          if (fullAddress.isNotEmpty) {
            _workAddressController.text = fullAddress;
          } else if (street.isNotEmpty) {
            _workAddressController.text = street;
          }
          if (city.isNotEmpty) {
            _cityController.text = city;
          }
          if (pincode.isNotEmpty) {
            _pincodeController.text = pincode;
          }
        });
        ToastUtils.showToast(
          context: context,
          message: 'Address updated from map pinpoint',
        );
        return;
      }
    } catch (_) {}

    // Fallback to LocationService reverse geocoding
    try {
      final fallback =
          await LocationService.instance.reverseGeocode(coord.lat, coord.lng);
      if (!mounted) return;
      setState(() {
        _isGeocoding = false;
        if (fallback != null && fallback.isNotEmpty) {
          _lastPinpointAddress = fallback;
          _workAddressController.text = fallback;
        }
      });
      if (fallback != null && fallback.isNotEmpty) {
        ToastUtils.showToast(
          context: context,
          message: 'Address updated from map pinpoint',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _useCurrentGps() async {
    setState(() => _isGeocoding = true);
    final ok = await LocationService.instance.refreshCurrentPosition();
    if (!ok || !AppLocation.instance.hasFix) {
      if (mounted) {
        setState(() => _isGeocoding = false);
        ToastUtils.showToast(
          context: context,
          message: 'Could not fetch current GPS coordinates',
        );
      }
      return;
    }
    final lat = AppLocation.instance.lat!;
    final lng = AppLocation.instance.lng!;
    final coord = MapCoordinate(lat: lat, lng: lng, label: 'My Location');
    await _onMapPinpoint(coord);
    if (mounted) {
      setState(() {
        _pinnedCoordinate = coord;
        _showMap = true;
      });
    }
  }

  Future<void> _save(ProfileState state) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final rateVal = double.tryParse(_rateController.text.trim());
    final expVal = int.tryParse(_experienceController.text.trim());

    try {
      await context.read<ProfileCubit>().updateProfile(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            emergencyContactName: _emergencyNameController.text.trim(),
            emergencyContactPhone: _emergencyPhoneController.text.trim(),
            emergencyContactRelation:
                _emergencyRelationController.text.trim(),
            category: _selectedCategory,
            categories: _selectedCategory == null
                ? null
                : [_selectedCategory!, ..._skills],
            skills: _skills.toList(),
            workAddress: _workAddressController.text.trim(),
            hourlyRate: rateVal,
            experienceYears: expVal,
            bio: _bioController.text.trim(),
            upiId: _upiController.text.trim(),
            gender: _gender,
            homeState: _stateController.text.trim(),
            homeCity: _cityController.text.trim(),
            homePincode: _pincodeController.text.trim(),
          );
      if (mounted) {
        ToastUtils.showToast(
          context: context,
          message: context.l10n.profileSaved,
        );
        context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      final message = context.read<ProfileCubit>().state.errorMessage;
      ToastUtils.showError(
        context: context,
        message: message ?? 'Could not save profile',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocConsumer<ProfileCubit, ProfileState>(
      listener: (context, state) {
        _syncFromState(state);
      },
      builder: (context, state) {
        final isWorker = state.isWorker;

        return AppScaffold(
          title: context.l10n.editProfile,
          showBack: true,
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                // Header: Profile Avatar & Identity Card
                _ProfileAvatarHeader(
                  name: _nameController.text.isNotEmpty
                      ? _nameController.text
                      : state.name,
                  email: state.email,
                  isWorker: isWorker,
                ),
                const SizedBox(height: AppSpacing.xl),

                // Section 1: Personal Details
                const _SectionHeader(
                  icon: Icons.person_outline_rounded,
                  title: 'Personal Information',
                  subtitle: 'Your name, contact phone, and identity',
                ),
                const SizedBox(height: AppSpacing.sm),
                _FormCard(
                  children: [
                    AppTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      hint: 'Enter your full name',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      validator: (v) =>
                          Validators.requiredField(v, label: 'Name'),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: '+91 9876543210',
                      keyboardType: TextInputType.phone,
                      prefixIcon: const Icon(Icons.phone_outlined),
                      validator: Validators.phone,
                    ),
                    if (state.email.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _VerifiedEmailRow(email: state.email),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Gender',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _GenderSelector(
                      selectedGender: _gender,
                      onChanged: (val) => setState(() => _gender = val),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Section 2: Address with Pinpoint on Map Option
                _SectionHeader(
                  icon: Icons.location_on_outlined,
                  title: isWorker
                      ? 'Work Location & Base Area'
                      : 'Default Service Address',
                  subtitle: isWorker
                      ? 'Base area where you accept customer job requests'
                      : 'Where service professionals will arrive for home jobs',
                ),
                const SizedBox(height: AppSpacing.sm),
                _FormCard(
                  children: [
                    // Address Line with Map Action Toggle
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            isWorker ? 'Operating Base Address' : 'Address Line',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _showMap = !_showMap),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _showMap
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                color: _showMap
                                    ? scheme.primary.withValues(alpha: 0.35)
                                    : scheme.outline.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showMap
                                      ? Icons.map_rounded
                                      : Icons.pin_drop_outlined,
                                  size: 15,
                                  color: _showMap
                                      ? scheme.primary
                                      : context.muted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _showMap ? 'Hide Map' : 'Choose on Map',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: _showMap
                                            ? scheme.primary
                                            : context.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _workAddressController,
                      label: '',
                      hint: isWorker
                          ? 'e.g. Connaught Place, New Delhi'
                          : 'Flat / House No, Building, Street, Landmark',
                      prefixIcon: const Icon(Icons.pin_drop_outlined),
                      validator: (v) => Validators.requiredField(
                        v,
                        label: 'Address',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick Map Toolbar
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _useCurrentGps,
                          icon: const Icon(Icons.my_location_rounded, size: 16),
                          label: const Text(
                            'Use Current GPS',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const Spacer(),
                        if (!_showMap)
                          TextButton.icon(
                            onPressed: () => setState(() => _showMap = true),
                            icon: const Icon(Icons.map_outlined, size: 16),
                            label: const Text(
                              'Pinpoint on Map',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),

                    // Interactive Map Drawer (opens below address field)
                    if (_showMap) ...[
                      const SizedBox(height: 8),
                      _MapPinpointCard(
                        pinnedCoordinate: _pinnedCoordinate,
                        isGeocoding: _isGeocoding,
                        lastAddress: _lastPinpointAddress,
                        onMapTap: _onMapPinpoint,
                        onClose: () => setState(() => _showMap = false),
                        onUseGps: _useCurrentGps,
                      ),
                    ],

                    const SizedBox(height: 16),
                    if (isWorker) ...[
                      LocationTypeAheadField(
                        controller: _stateController,
                        label: 'State',
                        hint: 'Type to search state',
                        suggestionsFor: (query) async =>
                            IndiaLocations.filterStates(query),
                        onSelected: (stateName) {
                          final districts =
                              IndiaLocations.districtsFor(stateName);
                          final current = _cityController.text.trim();
                          final stillValid = districts.any(
                            (d) => d.toLowerCase() == current.toLowerCase(),
                          );
                          if (!stillValid) {
                            _cityController.clear();
                          }
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      LocationTypeAheadField(
                        controller: _cityController,
                        label: 'District',
                        hint: 'Type to search district',
                        suggestionsFor: (query) async {
                          final state = _stateController.text.trim();
                          if (state.isEmpty) return const <String>[];
                          return IndiaLocations.filterDistricts(state, query);
                        },
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: AppTextField(
                              controller: _cityController,
                              label: 'City',
                              hint: 'e.g. Noida',
                              prefixIcon:
                                  const Icon(Icons.location_city_outlined),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: AppTextField(
                              controller: _pincodeController,
                              label: 'Pincode',
                              hint: '201301',
                              keyboardType: TextInputType.number,
                              prefixIcon: const Icon(Icons.pin_outlined),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Section 3: Worker Specific Trade & Rates
                if (isWorker) ...[
                  const _SectionHeader(
                    icon: Icons.handyman_outlined,
                    title: 'Trade & Service Details',
                    subtitle: 'Your primary service category, skills, and rates',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _FormCard(
                    children: [
                      Text(
                        'Primary Trade Category',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: ServiceCategories.all
                                .any((c) => c.id == _selectedCategory)
                            ? _selectedCategory
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.category_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        hint: const Text('Select your trade category'),
                        items: [
                          for (final cat in ServiceCategories.all)
                            DropdownMenuItem(
                              value: cat.id,
                              child: Row(
                                children: [
                                  Icon(
                                    cat.icon,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      '${cat.nameEn} (${cat.nameHi})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedCategory = val;
                            if (val != null) _skills.add(val);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Skills & Specialties',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final cat in ServiceCategories.all)
                            FilterChip(
                              label: Text(cat.nameEn),
                              selected: _skills.contains(cat.id),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _skills.add(cat.id);
                                  } else {
                                    _skills.remove(cat.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _rateController,
                              label: 'Base Price (₹)',
                              hint: 'e.g. 250',
                              keyboardType: TextInputType.number,
                              prefixIcon:
                                  const Icon(Icons.currency_rupee_rounded),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _experienceController,
                              label: 'Experience (Years)',
                              hint: 'e.g. 5',
                              keyboardType: TextInputType.number,
                              prefixIcon:
                                  const Icon(Icons.work_history_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _bioController,
                        label: 'Professional Bio / About',
                        hint:
                            'Brief description of your expertise, tools, and background',
                        maxLines: 3,
                        prefixIcon: const Icon(Icons.description_outlined),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _upiController,
                        label: 'UPI ID for Instant Payouts',
                        hint: 'e.g. name@okhdfcbank',
                        prefixIcon:
                            const Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Section 4: Emergency Contact
                const _SectionHeader(
                  icon: Icons.emergency_outlined,
                  title: 'Emergency Contact',
                  subtitle: 'Contact reached in case of safety alerts or SOS',
                ),
                const SizedBox(height: AppSpacing.sm),
                _FormCard(
                  children: [
                    AppTextField(
                      controller: _emergencyNameController,
                      label: 'Contact Person Name',
                      hint: 'e.g. Ramesh Sharma',
                      prefixIcon: const Icon(Icons.contact_phone_outlined),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _emergencyPhoneController,
                      label: 'Emergency Phone Number',
                      hint: '+91 9876543210',
                      keyboardType: TextInputType.phone,
                      prefixIcon: const Icon(Icons.phone_in_talk_outlined),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _emergencyRelationController,
                      label: 'Relationship',
                      hint: 'e.g. Spouse, Parent, Sibling, Friend',
                      prefixIcon: const Icon(Icons.people_outline_rounded),
                    ),
                    const SizedBox(height: 10),
                    // Quick relationship chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: ['Parent', 'Spouse', 'Sibling', 'Friend']
                          .map(
                            (rel) => ActionChip(
                              label: Text(
                                rel,
                                style: const TextStyle(fontSize: 12),
                              ),
                              avatar: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 14,
                              ),
                              onPressed: () {
                                setState(() {
                                  _emergencyRelationController.text = rel;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Save Action Button
                PrimaryButton(
                  label: 'Save Profile Changes',
                  loading: state.status == ProfileStatus.loading,
                  onPressed: () => _save(state),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Interactive map pinpoint card that expands directly beneath the address field
class _MapPinpointCard extends StatelessWidget {
  const _MapPinpointCard({
    required this.pinnedCoordinate,
    required this.isGeocoding,
    required this.lastAddress,
    required this.onMapTap,
    required this.onClose,
    required this.onUseGps,
  });

  final MapCoordinate? pinnedCoordinate;
  final bool isGeocoding;
  final String? lastAddress;
  final ValueChanged<MapCoordinate> onMapTap;
  final VoidCallback onClose;
  final VoidCallback onUseGps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final initialCenter = pinnedCoordinate ??
        MapConstants.current ??
        const MapCoordinate(lat: 28.6139, lng: 77.2090, label: 'New Delhi');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap anywhere on map to pinpoint address',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.muted,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Close map',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Map View Area
          SizedBox(
            height: 230,
            child: Stack(
              children: [
                FixlyMapView(
                  height: 230,
                  center: initialCenter,
                  zoom: 14.5,
                  routeEnd: pinnedCoordinate,
                  showDestinationPin: pinnedCoordinate != null,
                  claimGestures: true,
                  showZoomControls: true,
                  show3DControl: false,
                  showRecenterButton: true,
                  onMapTap: onMapTap,
                ),

                // Loading geocoding indicator
                if (isGeocoding)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Fetching address from coordinates...',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Map Footer Status / Details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                top: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  pinnedCoordinate != null
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: pinnedCoordinate != null
                      ? AppColors.success
                      : context.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pinnedCoordinate != null
                        ? (lastAddress != null && lastAddress!.isNotEmpty
                            ? lastAddress!
                            : 'Pin set at: ${pinnedCoordinate!.lat.toStringAsFixed(4)}, ${pinnedCoordinate!.lng.toStringAsFixed(4)}')
                        : 'Tap map to mark location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: pinnedCoordinate != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: pinnedCoordinate != null
                              ? Theme.of(context).textTheme.bodySmall?.color
                              : context.muted,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: onClose,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatarHeader extends StatelessWidget {
  const _ProfileAvatarHeader({
    required this.name,
    required this.email,
    required this.isWorker,
  });

  final String name;
  final String email;
  final bool isWorker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : 'Fixly User',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              isWorker ? 'Fixly Worker Partner' : 'Fixly Customer',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedEmailRow extends StatelessWidget {
  const _VerifiedEmailRow({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                size: 20,
                color: context.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.muted,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 13,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({
    required this.selectedGender,
    required this.onChanged,
  });

  final String? selectedGender;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      ('male', 'Male', Icons.male_rounded),
      ('female', 'Female', Icons.female_rounded),
      ('other', 'Other', Icons.transgender_rounded),
      ('unspecified', 'Prefer not to say', Icons.person_outline_rounded),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selectedGender == opt.$1;
        return ChoiceChip(
          label: Text(opt.$2),
          avatar: Icon(
            opt.$3,
            size: 16,
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
          ),
          selected: isSelected,
          onSelected: (selected) {
            onChanged(selected ? opt.$1 : null);
          },
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.titleSmall?.color,
                    ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.muted,
                      fontSize: 11.5,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: scheme.outline.withValues(alpha: 0.18),
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
