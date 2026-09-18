/**
 * Shared app locales for Fixly AI (must match frontend LocaleScope).
 */
export const APP_AI_LOCALES = ['en', 'hi', 'ta', 'te', 'kn', 'bn', 'mr', 'gu', 'pa'];

/** Normalize client language to a supported app locale. */
export function normalizeAppLanguage(raw) {
  const v = String(raw || 'en').toLowerCase().trim();
  if (v === 'hindi') return 'hi';
  if (v === 'english') return 'en';
  if (APP_AI_LOCALES.includes(v)) return v;
  // BCP47 tags like hi-IN
  const base = v.split(/[-_]/)[0];
  if (APP_AI_LOCALES.includes(base)) return base;
  return 'en';
}

export function sttLocaleId(lang) {
  const map = {
    en: 'en_IN',
    hi: 'hi_IN',
    ta: 'ta_IN',
    te: 'te_IN',
    kn: 'kn_IN',
    bn: 'bn_IN',
    mr: 'mr_IN',
    gu: 'gu_IN',
    pa: 'pa_IN',
  };
  return map[normalizeAppLanguage(lang)] || 'en_IN';
}

export function ttsLocaleId(lang) {
  return sttLocaleId(lang).replace('_', '-');
}
