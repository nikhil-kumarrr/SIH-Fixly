import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

abstract final class AppConstants {
  static const appName = 'Fixly';
  /// Client API version sent to `GET /api/version` (must match backend `apiVersion`).
  static const apiVersion = 'V1';
  static const homeCategoryPreviewCount = 4;
  static const mockOtp = '123456';
  static const mockDelayMs = 200;
  static const onboardingTotalSteps = 3;
  static const transitionDurationMs = 250;

  /// Flip true to show Live Talk / mic / Hey Fixly voice entry points again.
  static const voiceAiEnabled = true;
}

abstract final class AppImages {
  static const demoSelfie =
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&h=400&fit=crop&q=80';
}

abstract final class ServiceCategories {
  static const all = [
    ServiceCategory(
      id: 'electrician',
      nameEn: 'Electrician',
      nameHi: 'इलेक्ट्रीशियन',
      translations: {
        'en': 'Electrician',
        'hi': 'इलेक्ट्रीशियन',
        'mr': 'इलेक्ट्रिशियन',
        'ta': 'மின்சார நிபுணர்',
        'te': 'ఎలక్ట్రీషియన్',
        'kn': 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
        'bn': 'ইলেকট্রিশিয়ান',
        'gu': 'ઇલેક્ટ્રિશિયન',
        'pa': 'ਇਲੈਕਟ੍ਰੀਸ਼ੀਅਨ',
      },
      gradient: AppColors.primaryGradient,
      icon: Icons.bolt_rounded,
    ),
    ServiceCategory(
      id: 'plumber',
      nameEn: 'Plumber',
      nameHi: 'प्लंबर',
      translations: {
        'en': 'Plumber',
        'hi': 'प्लंबर',
        'mr': 'प्लंबर',
        'ta': 'குழாய் பழுதுபார்ப்பவர்',
        'te': 'ప్లంబర్',
        'kn': 'ಪ್ಲಂಬರ್',
        'bn': 'প্লাম্বার',
        'gu': 'પ્લમ્બર',
        'pa': 'ਪਲੰਬਰ',
      },
      gradient: [AppColors.primaryDark, AppColors.primary],
      icon: Icons.plumbing_rounded,
    ),
    ServiceCategory(
      id: 'carpenter',
      nameEn: 'Carpenter',
      nameHi: 'बढ़ई',
      translations: {
        'en': 'Carpenter',
        'hi': 'बढ़ई',
        'mr': 'सुतार',
        'ta': 'தச்சர்',
        'te': 'వడ్రంగి',
        'kn': 'ಬಡಗಿ',
        'bn': 'ছুতার',
        'gu': 'સુથਾਰ',
        'pa': 'ਤਰਖਾਣ',
      },
      gradient: [AppColors.primary600, AppColors.primary300],
      icon: Icons.carpenter_rounded,
    ),
    ServiceCategory(
      id: 'painter',
      nameEn: 'Painter',
      nameHi: 'पेंटर',
      translations: {
        'en': 'Painter',
        'hi': 'पेंटर',
        'mr': 'रंगारी',
        'ta': 'வண்ணப்பூசுபவர்',
        'te': 'పెయింటర్',
        'kn': 'ಬಣ್ಣಗಾರ',
        'bn': 'রংমিস্ত্রি',
        'gu': 'કલર કામ',
        'pa': 'ਪੇਂਟਰ',
      },
      gradient: [AppColors.primary, AppColors.primary200],
      icon: Icons.format_paint_rounded,
    ),
    ServiceCategory(
      id: 'gardener',
      nameEn: 'Gardener',
      nameHi: 'माली',
      translations: {
        'en': 'Gardener',
        'hi': 'माली',
        'mr': 'माळी',
        'ta': 'தோட்டக்காரர்',
        'te': 'తోటమాలి',
        'kn': 'ತೋಟಗಾರ',
        'bn': 'মালী',
        'gu': 'માળી',
        'pa': 'ਮਾਲੀ',
      },
      gradient: [AppColors.primaryDark, AppColors.primary400],
      icon: Icons.yard_rounded,
    ),
    ServiceCategory(
      id: 'domestic_helper',
      nameEn: 'Domestic Helper',
      nameHi: 'घरेलू सहायक',
      translations: {
        'en': 'Domestic Helper',
        'hi': 'घरेलू सहायक',
        'mr': 'घरकाम मदतनीस',
        'ta': 'வீட்டு உதவியாளர்',
        'te': 'గృహ సహాయకుడు',
        'kn': 'ಮನೆ ಕೆಲಸದ ಸಹಾಯಕ',
        'bn': 'গৃহকর্মী',
        'gu': 'ઘરેલું સહાયક',
        'pa': 'ਘਰੇਲੂ ਸਹਾਇਕ',
      },
      gradient: [AppColors.primary800, AppColors.primary],
      icon: Icons.home_work_rounded,
    ),
    ServiceCategory(
      id: 'caregiving',
      nameEn: 'Caregiving',
      nameHi: 'देखभाल',
      translations: {
        'en': 'Caregiving',
        'hi': 'देखभाल',
        'mr': 'देखभाल',
        'ta': 'பராமரிப்பு',
        'te': 'సంరక్షణ',
        'kn': 'ಆರೈಕೆ',
        'bn': 'পরিচর্যা',
        'gu': 'સંભાળ',
        'pa': 'ਦੇਖਭਾਲ',
      },
      gradient: [AppColors.primary600, AppColors.primary300],
      icon: Icons.favorite_rounded,
    ),
    ServiceCategory(
      id: 'driver',
      nameEn: 'Driver',
      nameHi: 'ड्राइवर',
      translations: {
        'en': 'Driver',
        'hi': 'ड्राइवर',
        'mr': 'चालक',
        'ta': 'ஓட்டுநர்',
        'te': 'డ్రైవర్',
        'kn': 'ಚಾಲಕ',
        'bn': 'চালক',
        'gu': 'ડ્રાઇવਰ',
        'pa': 'ਡਰਾਈਵਰ',
      },
      gradient: [AppColors.primaryDark, AppColors.primary300],
      icon: Icons.directions_car_rounded,
    ),
    ServiceCategory(
      id: 'technician',
      nameEn: 'Technician',
      nameHi: 'तकनीशियन',
      translations: {
        'en': 'Technician',
        'hi': 'तकनीशियन',
        'mr': 'तंत्रज्ञ',
        'ta': 'தொழில்நுட்ப வல்லுநர்',
        'te': 'టెక్నీషియన్',
        'kn': 'ತಂತ್ರಜ್ಞ',
        'bn': 'প্রযুক্তিবিদ',
        'gu': 'ટેકનિશિયન',
        'pa': 'ਤਕਨੀਸ਼ੀਅਨ',
      },
      gradient: [AppColors.primary800, AppColors.primary400],
      icon: Icons.build_circle_rounded,
    ),
    ServiceCategory(
      id: 'cleaning',
      nameEn: 'Cleaning',
      nameHi: 'सफाई',
      translations: {
        'en': 'Cleaning',
        'hi': 'सफाई',
        'mr': 'स्वच्छता',
        'ta': 'துப்புரவு',
        'te': 'శుభ్రపరచడం',
        'kn': 'ಸ್ವಚ್ಛತೆ',
        'bn': 'পরিষ্কারকরণ',
        'gu': 'સફાઈ',
        'pa': 'ਸਫ਼ਾਈ',
      },
      gradient: [AppColors.primary, AppColors.primary100],
      icon: Icons.cleaning_services_rounded,
    ),
  ];
}

class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.nameEn,
    required this.nameHi,
    this.translations,
    required this.gradient,
    required this.icon,
    this.imageUrl,
  });

  final String id;
  final String nameEn;
  final String nameHi;
  final Map<String, String>? translations;
  final List<Color> gradient;
  final IconData icon;
  final String? imageUrl;

  String nameFor(String locale) {
    if (translations != null &&
        translations![locale] != null &&
        translations![locale]!.isNotEmpty) {
      return translations![locale]!;
    }
    if (locale == 'hi') return nameHi;
    return nameEn;
  }
}
