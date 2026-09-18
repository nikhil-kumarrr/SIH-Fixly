import 'package:flutter/material.dart';

import '../../../../app/theme/theme_x.dart';
import '../../../../core/navigation/customer_navigation.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../home/data/home_api_repository.dart';

/// Browse-all categories — denser Soft UI cards (not the compact home tiles).
class CustomerCategoriesPage extends StatelessWidget {
  const CustomerCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.l10n.locale;
    final theme = Theme.of(context);

    return AppScaffold(
      title: l10n.allCategories,
      body: FutureBuilder<List<ServiceCategory>>(
        future: HomeApiRepository().fetchCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final categories = snapshot.data ?? const [];

          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.category_outlined, size: 56, color: context.muted),
                    const SizedBox(height: 16),
                    Text(
                      'No categories available',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomScrollView(
            physics: appRefreshScrollPhysics,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Browse services',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${categories.length} categories · tap to find nearby pros',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 10,
                    // Image tile + fixed label band; contain needs a bit more height.
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final cat = categories[index];
                      return _CategoryBrowseCard(
                        category: cat,
                        locale: locale,
                        onTap: () => context.openCategorySearch(cat.id),
                      ).appListEnter(context, index: index, id: cat.id);
                    },
                    childCount: categories.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryBrowseCard extends StatelessWidget {
  const _CategoryBrowseCard({
    required this.category,
    required this.locale,
    required this.onTap,
  });

  final ServiceCategory category;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = category.nameFor(locale);
    final hasImage =
        category.imageUrl != null && category.imageUrl!.trim().isNotEmpty;
    final gradient = category.gradient;

    return Semantics(
      button: true,
      label: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image tile — contain + pad so art not cropped; label below.
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: hasImage
                      ? Image.network(
                          category.imageUrl!.trim(),
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) =>
                              _IconFallback(
                            icon: category.icon,
                            size: 36,
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return _IconFallback(
                              icon: category.icon,
                              size: 32,
                              muted: true,
                            );
                          },
                        )
                      : _IconFallback(icon: category.icon, size: 36),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: context.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconFallback extends StatelessWidget {
  const _IconFallback({
    required this.icon,
    required this.size,
    this.muted = false,
  });

  final IconData icon;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        color: Colors.white.withValues(alpha: muted ? 0.75 : 1),
        size: size,
      ),
    );
  }
}
