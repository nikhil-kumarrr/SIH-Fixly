import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../cubit/welfare_cubit.dart';

class WorkerWelfarePage extends StatelessWidget {
  const WorkerWelfarePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WelfareCubit()..load(),
      child: const _WorkerWelfareView(),
    );
  }
}

class _WorkerWelfareView extends StatelessWidget {
  const _WorkerWelfareView();

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final url = Uri.parse(urlString);
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.inAppWebView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );
      if (!launched) {
        await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.fromError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Welfare & Fund',
      body: BlocBuilder<WelfareCubit, WelfareState>(
        builder: (context, state) {
          if (state.isLoading && state.resources.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return AppRefreshIndicator(
            onRefresh: () => context.read<WelfareCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Welfare Fund Overview Card (No pricing)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Cooperative Welfare Fund',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Comprehensive social security, accidental insurance, and government welfare scheme linkage for registered cooperative partners.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                
                // e-Shram Card
                Text(
                  'e-Shram / Insurance Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (state.hasUan ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            state.hasUan ? Icons.verified : Icons.info_outline,
                            color: state.hasUan ? AppColors.success : AppColors.warning,
                          ),
                        ),
                        title: Text(state.hasUan ? 'UAN Registered' : 'Registration Pending'),
                        subtitle: Text(
                          state.hasUan 
                            ? 'Your social security linkage is active.' 
                            : 'Register to access official insurance benefits.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          label: state.hasUan ? 'Open e-Shram Portal' : 'Register for e-Shram',
                          onPressed: () {
                            if (state.hasUan) {
                              _launchUrl(context, 'https://eshram.gov.in/');
                            } else {
                              _launchUrl(context, 'https://register.eshram.gov.in/');
                            }
                          },
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Resources
                Text(
                  'Welfare Resources',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...state.resources.map((res) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(res['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(res['description'] ?? ''),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          if (res['url'] != null) {
                            _launchUrl(context, res['url']);
                          }
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
