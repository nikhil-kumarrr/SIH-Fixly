import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/widgets/fixly_map_view.dart';
import '../../../../shared/models/models.dart';
import '../../../home/data/home_api_repository.dart';
import '../../../shared/presentation/widgets/service_scope_widgets.dart';
import '../../../workers/data/workers_api_repository.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerBookingPage extends StatefulWidget {
  const CustomerBookingPage({
    super.key,
    this.workerId,
    this.serviceId,
    this.categoryId,
  });

  final String? workerId;
  final String? serviceId;
  final String? categoryId;

  @override
  State<CustomerBookingPage> createState() => _CustomerBookingPageState();
}

class _CustomerBookingPageState extends State<CustomerBookingPage> {
  static const _maxMedia = 5;

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _picker = ImagePicker();

  final List<XFile> _photos = [];
  final List<XFile> _videos = [];

  bool _pickingMedia = false;
  bool _resolvingService = false;
  bool _isGeocoding = false;
  bool _isLocating = false;

  bool _isScheduled = false;
  bool _isEmergency = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  List<String> _availableCategories = [];
  String? _selectedCategory;
  List<ServiceItem> _allServices = [];
  List<ServiceItem> _services = [];

  WorkerProfile? _worker;
  MapCoordinate? _selectedCoord;

  @override
  void initState() {
    super.initState();

    // 1. Initial location from AppLocation or MapConstants
    if (AppLocation.instance.hasFix) {
      _selectedCoord = MapCoordinate(
        lat: AppLocation.instance.lat!,
        lng: AppLocation.instance.lng!,
        label: "Worker's Destination",
      );
    } else {
      _selectedCoord = (MapConstants.current != null)
          ? MapCoordinate(
              lat: MapConstants.current!.lat,
              lng: MapConstants.current!.lng,
              label: "Worker's Destination",
            )
          : const MapCoordinate(
              lat: 19.0760,
              lng: 72.8777,
              label: "Worker's Destination",
            );
    }

    // 2. Initial address string
    final currentAddress = AppLocation.instance.addressLabel?.trim();
    if (currentAddress != null && currentAddress.isNotEmpty) {
      _addressController.text = currentAddress;
    } else if (_selectedCoord != null) {
      _addressController.text =
          '${_selectedCoord!.lat.toStringAsFixed(4)}, ${_selectedCoord!.lng.toStringAsFixed(4)}';
      _reverseGeocodeInitialLocation();
    }

    // 3. Load services and worker category
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadServices());
  }

  Future<void> _reverseGeocodeInitialLocation() async {
    if (_selectedCoord == null) return;
    try {
      final addr = await LocationService.instance
          .reverseGeocode(_selectedCoord!.lat, _selectedCoord!.lng)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (mounted && addr != null && addr.isNotEmpty) {
        _addressController.text = addr;
        AppLocation.instance.update(
          latitude: _selectedCoord!.lat,
          longitude: _selectedCoord!.lng,
          address: addr,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _titleCase(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  bool _isRecognizedCategory(String s) {
    final lower = s.toLowerCase().trim();
    return lower.contains('elect') ||
        lower.contains('plumb') ||
        lower.contains('tech') ||
        lower.contains('care') ||
        lower.contains('clean') ||
        lower.contains('carpen') ||
        lower.contains('paint') ||
        lower.contains('appliance') ||
        lower.contains('ac');
  }

  bool _matchesCategory(String itemCategory, String targetCategory) {
    final a = itemCategory.toLowerCase().trim();
    final b = targetCategory.toLowerCase().trim();
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;

    final groups = [
      ['plumb'],
      ['elect', 'wire'],
      ['clean', 'maid'],
      ['carpen', 'wood', 'furnit'],
      ['paint'],
      ['appliance', 'ac', 'refrig', 'cool', 'heater', 'geyser', 'tv', 'wash'],
      ['pest'],
      ['care', 'nurse', 'elderly', 'sitter'],
      ['salon', 'beauty', 'spa', 'hair', 'makeup'],
      ['mechanic', 'auto', 'car', 'bike', 'motor'],
      ['tech'],
    ];

    for (final group in groups) {
      final inA = group.any((t) => a.contains(t));
      final inB = group.any((t) => b.contains(t));
      if (inA && inB) return true;
    }
    return false;
  }

  ServiceItem _formatServiceItem(ServiceItem s, String category) {
    final title = s.title.trim().isNotEmpty
        ? _titleCase(s.title.trim())
        : _titleCase(category);

    return ServiceItem(
      id: s.id,
      categoryId: s.categoryId,
      title: title,
      description: s.description.isNotEmpty
          ? s.description
          : 'Professional service for ${_titleCase(category)}',
      priceFrom: s.priceFrom > 0 ? s.priceFrom : 199,
      rating: s.rating,
      titleHi: s.titleHi,
      descriptionHi: s.descriptionHi,
      imageUrl: s.imageUrl,
      estimatedTime: s.estimatedTime ?? '1 Hour',
      whatsIncluded: s.whatsIncluded,
      isActive: s.isActive,
    );
  }

  List<ServiceItem> _getServicesForCategory(
    String category,
    List<ServiceItem> allServices,
  ) {
    final matching = allServices
        .where((s) => _matchesCategory(s.categoryId, category))
        .toList();
    if (matching.isNotEmpty) {
      return matching.map((s) => _formatServiceItem(s, category)).toList();
    }

    final partial = allServices
        .where(
          (s) =>
              s.categoryId.toLowerCase().contains(category.toLowerCase()) ||
              category.toLowerCase().contains(s.categoryId.toLowerCase()),
        )
        .toList();
    if (partial.isNotEmpty) {
      return partial.map((s) => _formatServiceItem(s, category)).toList();
    }

    return allServices.map((s) => _formatServiceItem(s, category)).toList();
  }

  Future<void> _loadServices() async {
    final cubit = context.read<BookingFlowCubit>();
    final incomingCategoryId = widget.categoryId?.trim();
    final requestedServiceId = widget.serviceId?.trim();

    setState(() => _resolvingService = true);

    try {
      // 1. Fetch worker profile if workerId is present
      WorkerProfile? worker;
      if (widget.workerId != null && widget.workerId!.isNotEmpty) {
        try {
          worker = await WorkersApiRepository().fetchWorker(widget.workerId!);
          if (mounted) setState(() => _worker = worker);
        } catch (_) {}
      }

      // 2. Fetch all services
      final allServices = await HomeApiRepository().fetchAllServices();
      if (!mounted) return;
      _allServices = allServices;

      // 3. Collect available categories
      final catList = <String>[];

      // A. From worker profile (categories array, primary category, skills)
      if (worker != null) {
        for (final c in worker.categories) {
          if (c.trim().isNotEmpty &&
              !catList.any((x) => x.toLowerCase() == c.trim().toLowerCase())) {
            catList.add(_titleCase(c.trim()));
          }
        }
        if (worker.category != null && worker.category!.trim().isNotEmpty) {
          final primary = _titleCase(worker.category!.trim());
          if (!catList.any((x) => x.toLowerCase() == primary.toLowerCase())) {
            catList.insert(0, primary);
          }
        }
        for (final skill in worker.skills) {
          if (_isRecognizedCategory(skill)) {
            final formatted = _titleCase(skill.trim());
            if (!catList.any(
              (x) => x.toLowerCase() == formatted.toLowerCase(),
            )) {
              catList.add(formatted);
            }
          }
        }
      }

      // B. Ensure category from route is in the list
      if (incomingCategoryId != null && incomingCategoryId.isNotEmpty) {
        final incoming = _titleCase(incomingCategoryId);
        if (!catList.any((x) => x.toLowerCase() == incoming.toLowerCase())) {
          catList.insert(0, incoming);
        }
      }

      // C. Fallback: all distinct categories from backend services
      if (catList.isEmpty) {
        for (final s in allServices) {
          final c = _titleCase(s.categoryId.trim());
          if (c.isNotEmpty &&
              !catList.any((x) => x.toLowerCase() == c.toLowerCase())) {
            catList.add(c);
          }
        }
      }

      // 4. Determine initial active category (where user came from)
      String? initialCategory;
      if (incomingCategoryId != null && incomingCategoryId.isNotEmpty) {
        initialCategory = catList.cast<String?>().firstWhere(
          (c) => _matchesCategory(c!, incomingCategoryId),
          orElse: () => null,
        );
      }
      if (initialCategory == null &&
          requestedServiceId != null &&
          requestedServiceId.isNotEmpty) {
        final match = allServices.cast<ServiceItem?>().firstWhere(
          (s) => s?.id == requestedServiceId,
          orElse: () => null,
        );
        if (match != null) {
          initialCategory = catList.cast<String?>().firstWhere(
            (c) => _matchesCategory(c!, match.categoryId),
            orElse: () => null,
          );
        }
      }
      initialCategory ??=
          (worker?.category != null && worker!.category!.isNotEmpty)
          ? catList.cast<String?>().firstWhere(
              (c) => _matchesCategory(c!, worker!.category!),
              orElse: () => null,
            )
          : null;
      initialCategory ??= catList.isNotEmpty ? catList.first : 'Services';

      _availableCategories = catList;
      _selectedCategory = initialCategory;

      // 5. Populate services for this active category
      final categoryServices = _getServicesForCategory(
        initialCategory,
        allServices,
      );
      _services = categoryServices;

      // 6. Resolve selected service
      ServiceItem? targetService;
      if (requestedServiceId != null && requestedServiceId.isNotEmpty) {
        for (final item in categoryServices) {
          if (item.id == requestedServiceId) {
            targetService = item;
            break;
          }
        }
      }
      targetService ??= categoryServices.isNotEmpty
          ? categoryServices.first
          : null;

      if (targetService != null) {
        cubit.selectService(targetService);
      }
    } finally {
      if (mounted) setState(() => _resolvingService = false);
    }
  }

  void _onCategoryChanged(String newCategory) {
    if (_selectedCategory == newCategory) return;
    final cubit = context.read<BookingFlowCubit>();
    final newServices = _getServicesForCategory(newCategory, _allServices);

    setState(() {
      _selectedCategory = newCategory;
      _services = newServices;
    });

    if (newServices.isNotEmpty) {
      cubit.selectService(newServices.first);
    }
  }

  IconData _getCategoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('elect')) return Icons.bolt_rounded;
    if (c.contains('plumb')) return Icons.plumbing_rounded;
    if (c.contains('tech') ||
        c.contains('appliance') ||
        c.contains('geyser') ||
        c.contains('ac')) {
      return Icons.build_rounded;
    }
    if (c.contains('care') || c.contains('nurse'))
      return Icons.favorite_rounded;
    if (c.contains('clean')) return Icons.cleaning_services_rounded;
    if (c.contains('carpen')) return Icons.carpenter_rounded;
    if (c.contains('paint')) return Icons.format_paint_rounded;
    return Icons.handyman_rounded;
  }

  Future<void> _onMapLocationChanged(MapCoordinate coord) async {
    setState(() {
      _selectedCoord = MapCoordinate(
        lat: coord.lat,
        lng: coord.lng,
        label: "Worker's Destination",
      );
      _isGeocoding = true;
      _addressController.text = 'Fetching address…';
    });

    AppLocation.instance.update(
      latitude: coord.lat,
      longitude: coord.lng,
      address: 'Updating location…',
    );

    try {
      final addr = await LocationService.instance
          .reverseGeocode(coord.lat, coord.lng)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      if (mounted) {
        final finalAddr = (addr != null && addr.isNotEmpty)
            ? addr
            : '${coord.lat.toStringAsFixed(4)}, ${coord.lng.toStringAsFixed(4)}';

        _addressController.text = finalAddr;
        AppLocation.instance.update(
          latitude: coord.lat,
          longitude: coord.lng,
          address: finalAddr,
        );
      }
    } catch (_) {
      if (mounted) {
        _addressController.text =
            '${coord.lat.toStringAsFixed(4)}, ${_selectedCoord!.lng.toStringAsFixed(4)}';
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _refreshToCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final ok = await LocationService.instance.ensureOnAppOpen(context);
      if (!mounted) return;
      if (ok && AppLocation.instance.hasFix) {
        final lat = AppLocation.instance.lat!;
        final lng = AppLocation.instance.lng!;
        final coord = MapCoordinate(
          lat: lat,
          lng: lng,
          label: "Worker's Destination",
        );
        setState(() {
          _selectedCoord = coord;
          _addressController.text = AppLocation.instance.addressLabel ?? '';
        });
      } else {
        ToastUtils.showToast(
          context: context,
          message: 'Could not get current location',
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickPhotos({ImageSource source = ImageSource.gallery}) async {
    final remaining = _maxMedia - _photos.length - _videos.length;
    if (remaining <= 0) return;
    setState(() => _pickingMedia = true);
    try {
      final List<XFile> picked;
      if (source == ImageSource.gallery) {
        picked = await _picker.pickMultiImage(imageQuality: 85);
      } else {
        final image = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        picked = image == null ? const [] : [image];
      }
      if (!mounted) return;
      setState(() => _photos.addAll(picked.take(remaining)));
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  Future<void> _pickVideo({ImageSource source = ImageSource.gallery}) async {
    if (_photos.length + _videos.length >= _maxMedia) return;
    setState(() => _pickingMedia = true);
    try {
      final picked = await _picker.pickVideo(source: source);
      if (!mounted || picked == null) return;
      setState(() => _videos.add(picked));
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  Future<void> _chooseMediaType() async {
    if (_photos.length + _videos.length >= _maxMedia) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Upload Problem Media',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text(
                    'Add Photos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Capture or pick photos of the problem'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(context, 'photo'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.videocam_outlined,
                      color: AppColors.secondary,
                    ),
                  ),
                  title: const Text(
                    'Add Video',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Record or upload a short clip showing the issue',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(context, 'video'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || type == null) return;
    final source = await _chooseMediaSource(
      type == 'photo' ? 'Photo' : 'Video',
    );
    if (!mounted || source == null) return;
    if (type == 'photo') await _pickPhotos(source: source);
    if (type == 'video') await _pickVideo(source: source);
  }

  Future<ImageSource?> _chooseMediaSource(String mediaType) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select $mediaType Source',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: AppColors.accent,
                    ),
                  ),
                  title: const Text(
                    'Take with Camera',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));
  void _removeVideo(int index) => setState(() => _videos.removeAt(index));

  void _openImagePreview(BuildContext context, String path, String title) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => _FullScreenImageViewer(imagePath: path, title: title),
    );
  }

  void _openVideoPreview(BuildContext context, String path, String title) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (ctx) => _FullScreenVideoPlayer(videoPath: path, title: title),
    );
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isEmergency && _isScheduled) {
      ToastUtils.showToast(
        context: context,
        message: 'SOS bookings are immediate — turn off schedule or SOS',
      );
      return;
    }

    if (_isScheduled && (_scheduledDate == null || _scheduledTime == null)) {
      ToastUtils.showToast(
        context: context,
        message: 'Please select a valid date and time for scheduling',
      );
      return;
    }

    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'Please provide a valid service address',
      );
      return;
    }

    DateTime? finalScheduledAt;
    if (_isScheduled && _scheduledDate != null && _scheduledTime != null) {
      finalScheduledAt = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
    }

    final bookingCubit = context.read<BookingFlowCubit>();
    await bookingCubit.submitBookingDetails(
      address: address,
      scheduledAt: finalScheduledAt,
      problemDescription: _descriptionController.text.trim(),
      workerId: widget.workerId,
      photoPaths: _photos.map((file) => file.path).toList(),
      videoPaths: _videos.map((file) => file.path).toList(),
      isEmergency: _isEmergency,
    );

    if (!mounted) return;
    if (bookingCubit.state.errorMessage == null) {
      context.push(RouteNames.customerBookingConfirmation);
    } else {
      ToastUtils.showToast(
        context: context,
        message: bookingCubit.state.errorMessage!,
      );
    }
  }

  Widget _buildWorkerBanner(BuildContext context, WorkerProfile worker) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget buildAvatar() {
      final avatarUrl = worker.avatarUrl?.trim();
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        if (avatarUrl.startsWith('data:image') || avatarUrl.length > 200) {
          try {
            final commaIdx = avatarUrl.indexOf(',');
            final raw = commaIdx != -1
                ? avatarUrl.substring(commaIdx + 1)
                : avatarUrl;
            final bytes = base64Decode(raw.replaceAll(RegExp(r'\s+'), ''));
            return Image.memory(bytes, fit: BoxFit.cover);
          } catch (_) {}
        } else if (avatarUrl.startsWith('http://') ||
            avatarUrl.startsWith('https://')) {
          return Image.network(
            avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => const Icon(Icons.person),
          );
        }
      }
      return Container(
        color: scheme.primary.withValues(alpha: 0.12),
        child: Center(
          child: Text(
            worker.name.isNotEmpty ? worker.name[0].toUpperCase() : 'W',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 54, height: 54, child: buildAvatar()),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        worker.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (worker.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.primary,
                        size: 17,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (_selectedCategory != null) ...[
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedCategory!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      worker.rating.toStringAsFixed(1),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (worker.jobsCompleted > 0) ...[
                      Flexible(
                        child: Text(
                          ' • ${worker.jobsCompleted} jobs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (worker.federationName != null &&
                    worker.federationName!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  CooperativeFederationBadge(
                    federationName: worker.federationName!,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getProblemQuickTags() {
    final cat = (_selectedCategory ?? '').toLowerCase();
    if (cat.contains('plumb')) {
      return const [
        'Water leakage',
        'Tap repair',
        'Pipe blocked',
        'Low pressure',
        'Flush issue',
      ];
    }
    if (cat.contains('elect')) {
      return const [
        'Short circuit',
        'Switch faulty',
        'Fan repair',
        'Wiring check',
        'MCB tripping',
      ];
    }
    if (cat.contains('clean')) {
      return const [
        'Deep cleaning',
        'Bathroom stains',
        'Kitchen oil',
        'Sofa wash',
        'Full home',
      ];
    }
    if (cat.contains('carpen')) {
      return const [
        'Door lock stuck',
        'Furniture repair',
        'Hinge broken',
        'Wood polish',
      ];
    }
    if (cat.contains('paint')) {
      return const [
        'Wall crack touchup',
        'Water dampness',
        'Single room paint',
        'Ceiling stain',
      ];
    }
    if (cat.contains('tech') ||
        cat.contains('appliance') ||
        cat.contains('ac')) {
      return const [
        'Not cooling / heating',
        'Water leaking',
        'Strange noise',
        'Power not turning on',
        'Filter check',
      ];
    }
    if (cat.contains('care') || cat.contains('nurse')) {
      return const [
        'Elderly mobility help',
        'Vitals check & dressing',
        'Bedside support',
        'Post-surgery care',
      ];
    }
    return const [
      'Urgent inspection',
      'Replacement needed',
      'Fault diagnosis',
      'Installation',
    ];
  }

  Widget _buildPickerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<BookingFlowCubit>();
    final selectedService = cubit.state.service;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final mediaCount = _photos.length + _videos.length;

    return AppScaffold(
      title: context.l10n.bookService,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 1. Step Progress Header
            if (selectedService != null)
              StepProgressHeader(
                currentStep: 1,
                totalSteps: 5,
                title: selectedService.title,
              ),

            // 2. Selected Worker Banner (if booked from specific worker)
            if (_worker != null) _buildWorkerBanner(context, _worker!),

            // 3. Section: Service Selection (Category Selector + Service Dropdown)
            _SectionCard(
              icon: Icons.home_repair_service_rounded,
              iconColor: scheme.primary,
              title: 'Select Service',
              badge: _selectedCategory != null
                  ? 'Category: $_selectedCategory'
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Dropdown
                  Text(
                    'Category',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('category_dropdown_$_selectedCategory'),
                    initialValue:
                        _availableCategories.contains(_selectedCategory)
                        ? _selectedCategory
                        : (_availableCategories.isNotEmpty
                              ? _availableCategories.first
                              : null),
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.8,
                        ),
                      ),
                    ),
                    items: _availableCategories
                        .map(
                          (cat) => DropdownMenuItem<String>(
                            value: cat,
                            child: Row(
                              children: [
                                Icon(
                                  _getCategoryIcon(cat),
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  cat,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _resolvingService
                        ? null
                        : (val) {
                            if (val != null) _onCategoryChanged(val);
                          },
                    validator: (val) => val == null || val.isEmpty
                        ? 'Please select category'
                        : null,
                  ),

                  // Quick Category Choice Chips (if worker offers multiple categories)
                  if (_availableCategories.length > 1) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _availableCategories.map((cat) {
                        final isSelected =
                            cat.toLowerCase() ==
                            _selectedCategory?.toLowerCase();
                        return ChoiceChip(
                          selected: isSelected,
                          avatar: Icon(
                            _getCategoryIcon(cat),
                            size: 15,
                            color: isSelected ? Colors.white : scheme.primary,
                          ),
                          label: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : scheme.onSurface,
                            ),
                          ),
                          selectedColor: scheme.primary,
                          backgroundColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          side: BorderSide(
                            color: isSelected
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: 0.18),
                          ),
                          onSelected: (selected) {
                            if (selected) _onCategoryChanged(cat);
                          },
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Specific Services Dropdown
                  Text(
                    'Service',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<ServiceItem>(
                    key: ValueKey('service_dropdown_$_selectedCategory'),
                    initialValue: _services.contains(selectedService)
                        ? selectedService
                        : (_services.isNotEmpty ? _services.first : null),
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.8,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.handyman_rounded),
                    ),
                    items: _services
                        .map(
                          (item) => DropdownMenuItem<ServiceItem>(
                            value: item,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '₹${item.priceFrom.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _resolvingService
                        ? null
                        : (item) {
                            if (item != null) {
                              cubit.selectService(item);
                              setState(() {});
                            }
                          },
                    validator: (item) =>
                        item == null ? 'Please select a service' : null,
                  ),

                  if (selectedService != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.currency_rupee_outlined,
                                size: 16,
                                color: scheme.primary,
                              ),
                              Text(
                                'Starting from ₹${selectedService.priceFrom.toStringAsFixed(0)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          if (selectedService.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              selectedService.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                                fontSize: 11.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Section: Describe the Issue
            _SectionCard(
              icon: Icons.description_outlined,
              iconColor: AppColors.secondary,
              title: 'Describe the Issue',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 4,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText:
                          'Describe the problem in detail so the professional can bring the right tools & spare parts...',
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: theme.hintColor.withValues(alpha: 0.7),
                      ),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.8,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please describe the issue'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Quick suggestions for $_selectedCategory:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _getProblemQuickTags().map((tag) {
                      return InkWell(
                        onTap: () {
                          final current = _descriptionController.text.trim();
                          if (current.isEmpty) {
                            _descriptionController.text = tag;
                          } else if (!current.contains(tag)) {
                            _descriptionController.text = '$current, $tag';
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: scheme.outline.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            '+ $tag',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Section: Photos & Videos (Masonry Grid + Modern Uploader)
            _SectionCard(
              icon: Icons.perm_media_outlined,
              iconColor: Colors.teal,
              title: 'Photos & Videos',
              badge: '$mediaCount / $_maxMedia',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern Dropzone / Media Picker
                  if (mediaCount < _maxMedia) ...[
                    InkWell(
                      onTap: _pickingMedia ? null : _chooseMediaType,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_upload_outlined,
                                color: AppColors.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tap to upload photos or short video',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Helps professional bring proper spare parts (Max $_maxMedia items)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPickerActionButton(
                                    icon: Icons.photo_outlined,
                                    label: 'Add Photos',
                                    onTap: _pickingMedia
                                        ? null
                                        : () => _pickPhotos(
                                            source: ImageSource.gallery,
                                          ),
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPickerActionButton(
                                    icon: Icons.videocam_outlined,
                                    label: 'Add Video',
                                    onTap: _pickingMedia
                                        ? null
                                        : () => _pickVideo(
                                            source: ImageSource.gallery,
                                          ),
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (mediaCount > 0) const SizedBox(height: 16),
                  ],

                  // Masonry Grid for Uploaded Photos & Videos
                  if (mediaCount > 0) _buildMasonryMediaGrid(context),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Section: Service Address & Interactive Map
            _SectionCard(
              icon: Icons.location_on_rounded,
              iconColor: AppColors.primary,
              title: 'Service Address',
              trailing: TextButton.icon(
                onPressed: _isLocating ? null : _refreshToCurrentLocation,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: _isLocating
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 15),
                label: const Text(
                  'Locate Me',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Editable Address Input Field
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.place_outlined,
                        color: AppColors.primary,
                      ),
                      suffixIcon: _isGeocoding
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      hintText: 'House / Flat No., Landmark, Street Address...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please enter service address'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Tap or drag the map below to pinpoint exact service spot',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.hintColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Interactive Map Container
                  Container(
                    height: 230,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        FixlyMapView(
                          expand: true,
                          borderRadius: BorderRadius.circular(16),
                          center: _selectedCoord ?? MapConstants.current,
                          zoom: 15.5,
                          showUserLocation: true,
                          claimGestures: true,
                          showZoomControls: true,
                          showRecenterButton: true,
                          show3DControl: true,
                          showCompassButton: true,
                          showMovementControls: false,
                          showDestinationPin: true,
                          onMapTap: _onMapLocationChanged,
                          onMapIdled: _onMapLocationChanged,
                        ),
                        if (_isGeocoding)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Updating address…',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Schedule Section
            _SectionCard(
              icon: Icons.calendar_today_rounded,
              iconColor: AppColors.primary,
              title: 'When do you need the service?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Emergency SOS (priority dispatch)',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _isEmergency,
                        activeTrackColor: Colors.red.withValues(alpha: 0.5),
                        onChanged: (val) {
                          setState(() {
                            _isEmergency = val;
                            if (val) _isScheduled = false;
                          });
                        },
                      ),
                    ],
                  ),
                  if (_isEmergency)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Platform SOS surcharge applies. Price not set by worker.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Schedule for later?',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _isScheduled,
                        onChanged: _isEmergency
                            ? null
                            : (val) {
                                setState(() {
                                  _isScheduled = val;
                                });
                              },
                      ),
                    ],
                  ),
                  if (_isScheduled) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _scheduledDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 7),
                                ),
                              );
                              if (date != null) {
                                setState(() => _scheduledDate = date);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: scheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _scheduledDate != null
                                        ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                                        : 'Select Date',
                                    style: TextStyle(
                                      color: _scheduledDate != null
                                          ? scheme.onSurface
                                          : theme.hintColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _scheduledTime ?? TimeOfDay.now(),
                              );
                              if (time != null) {
                                setState(() => _scheduledTime = time);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: scheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _scheduledTime != null
                                        ? _scheduledTime!.format(context)
                                        : 'Select Time',
                                    style: TextStyle(
                                      color: _scheduledTime != null
                                          ? scheme.onSurface
                                          : theme.hintColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cooperative Federation Affiliation
            if (_worker?.federationName != null &&
                _worker!.federationName!.isNotEmpty)
              CooperativeFederationBadge(
                federationName: _worker!.federationName!,
              )
            else
              const CooperativeFederationBadge(
                federationName:
                    'National Labour Cooperative Federation of India (NLCF)',
              ),

            const SizedBox(height: 16),

            // What is included & What is not included (Image 1)
            WhatIsIncludedCard(
              primaryCategoryId: _selectedCategory ?? _worker?.category,
              includedTasks: _worker?.includedTasks,
              excludedTasks: _worker?.excludedTasks,
            ),

            const SizedBox(height: 16),

            // How it's done (Image 2)
            HowItsDoneCard(
              primaryCategoryId: _selectedCategory ?? _worker?.category,
            ),

            const SizedBox(height: 16),

            // FAQs (Image 2)
            ServiceFaqSection(
              primaryCategoryId: _selectedCategory ?? _worker?.category,
            ),

            const SizedBox(height: 24),

            // 7. Sticky/Bottom Continue Button Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (selectedService != null)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Base Visiting / Diagnosis Fee',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '₹${selectedService.priceFrom.toStringAsFixed(0)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Adjusted in final bill',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  BlocBuilder<BookingFlowCubit, BookingFlowState>(
                    builder: (context, state) => PrimaryButton(
                      label: 'Continue to book',
                      loading: state.isLoading,
                      onPressed: _resolvingService ? null : _continue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Masonry 2-column layout for photos and videos with modern aesthetics
  Widget _buildMasonryMediaGrid(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allItems = <_MediaItem>[];

    for (var i = 0; i < _photos.length; i++) {
      allItems.add(
        _MediaItem(
          path: _photos[i].path,
          name: _photos[i].name,
          isVideo: false,
          index: i,
        ),
      );
    }
    for (var i = 0; i < _videos.length; i++) {
      allItems.add(
        _MediaItem(
          path: _videos[i].path,
          name: _videos[i].name,
          isVideo: true,
          index: i,
        ),
      );
    }

    final leftWidgets = <Widget>[];
    final rightWidgets = <Widget>[];

    // Staggered heights for realistic masonry appearance
    final heights = [190.0, 145.0, 155.0, 185.0, 160.0];

    for (var i = 0; i < allItems.length; i++) {
      final item = allItems[i];
      final cardH = heights[i % heights.length];
      final widget = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildMasonryCard(context, item, cardH),
      );

      if (i % 2 == 0) {
        leftWidgets.add(widget);
      } else {
        rightWidgets.add(widget);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.collections_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Attached Media (${allItems.length}/$_maxMedia)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                'Tap to view / play',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: leftWidgets)),
            const SizedBox(width: 12),
            Expanded(child: Column(children: rightWidgets)),
          ],
        ),
      ],
    );
  }

  Widget _buildMasonryCard(
    BuildContext context,
    _MediaItem item,
    double height,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isVideo = item.isVideo;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.18),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Content: Image or Video Container
          if (!isVideo)
            Image.file(
              File(item.path),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => Container(
                color: scheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded, color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF111827),
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),

          // Tap gesture to open full viewer directly
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (isVideo) {
                  _openVideoPreview(context, item.path, item.name);
                } else {
                  _openImagePreview(context, item.path, item.name);
                }
              },
            ),
          ),

          // Top-Left Tag Badge
          Positioned(
            top: 8,
            left: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.photo_camera_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isVideo ? 'VIDEO' : 'PHOTO',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom gradient overlay with name and Play/View pill
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo
                                ? Icons.play_arrow_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            isVideo ? 'Play' : 'View',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Remove Button Top-Right
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (isVideo) {
                    _removeVideo(item.index);
                  } else {
                    _removePhoto(item.index);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaItem {
  const _MediaItem({
    required this.path,
    required this.name,
    required this.isVideo,
    required this.index,
  });

  final String path;
  final String name;
  final bool isVideo;
  final int index;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.badge,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? badge;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Immersive full-screen image viewer with pinch-to-zoom and pan
class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.imagePath, required this.title});

  final String imagePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stack) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Colors.black87,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pinch_rounded, color: Colors.white60, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Pinch to zoom • Double tap to inspect',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive full-screen video player dialog with playback controls
class _FullScreenVideoPlayer extends StatefulWidget {
  const _FullScreenVideoPlayer({required this.videoPath, required this.title});

  final String videoPath;
  final String title;

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Video file does not exist on device';
          });
        }
        return;
      }

      final controller = VideoPlayerController.file(file);
      _controller = controller;

      await controller.initialize();
      controller.addListener(_onControllerUpdate);
      await controller.setLooping(true);
      await controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _scheduleHideControls();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          if (e.message?.contains('channel-error') == true ||
              e.code == 'channel-error' ||
              e.message?.contains('initialize') == true) {
            _errorMessage =
                'Native video plugin was newly added to the project.\nPlease do a full app rebuild / restart (run "flutter run" in terminal) to compile the native video player plugin into the app.';
          } else {
            _errorMessage = 'Video player error: ${e.message ?? e.toString()}';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Could not load video: $e';
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _scheduleHideControls();
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        controller.play();
        _scheduleHideControls();
      }
    });
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;

    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video Core & Tap to Toggle Controls
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Center(
                child: _hasError
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.videocam_off_rounded,
                                color: Colors.white70,
                                size: 42,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Unable to Play Video',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage ??
                                  'An error occurred while initializing video player.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      )
                    : (_isInitialized && controller != null)
                    ? AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Loading video...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // Big Center Play/Pause Indicator on pause or toggle
            if (_isInitialized &&
                controller != null &&
                (!controller.value.isPlaying || _showControls))
              IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: !controller.value.isPlaying ? 0.95 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),

            // Top Bar: Back/Close, Title, Video Badge
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Bar: Scrubber, Timestamps, Play/Pause & Mute controls
            if (_isInitialized && controller != null)
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Scrubber bar
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          colors: VideoProgressColors(
                            playedColor: AppColors.primary,
                            bufferedColor: Colors.white.withValues(alpha: 0.25),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Controls Row
                        Row(
                          children: [
                            // Play/Pause Button
                            IconButton(
                              icon: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: _togglePlayPause,
                            ),

                            // Timestamp: current / total
                            Text(
                              '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const Spacer(),

                            // Mute/Unmute
                            IconButton(
                              icon: Icon(
                                _isMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: _toggleMute,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
