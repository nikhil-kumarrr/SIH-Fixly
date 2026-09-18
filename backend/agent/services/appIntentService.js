/**
 * Lightweight keyword intent resolver for in-app actions.
 * Keeps Gemini Live fast — Flash/booking brain only when needed.
 */

/**
 * @param {string} text
 * @param {{ language?: string }} [opts]
 * @returns {{ actions: Array<Record<string, string>>, replyHint: string|null, isAppOnly: boolean }}
 */
export function resolveAppIntents(text = '', opts = {}) {
  const raw = String(text || '').trim();
  const isHi = String(opts.language || '').toLowerCase().startsWith('hi');
  /** @type {Array<Record<string, string>>} */
  const actions = [];

  const navTo = (dest) =>
    new RegExp(
      `(?:^|\\s)(take\\s*me\\s*to|go\\s*(to)?|open|show|navigate\\s*(to)?|switch\\s*to|bring\\s*me\\s*to|kholo|dikhao|le\\s*chalo|chalo|जाओ|खोलो|दिखाओ|चलो)\\s+.*${dest}` +
        `|${dest}\\s*(screen|page|tab|section|me|mein|par|pe|kholo|dikhao|jao|chalo|स्क्रीन|पेज|टैब|में|पर|खोलो|दिखाओ|जाओ|चलो)` +
        `|^\\s*${dest}\\s*$`,
      'i',
    );

  // Theme
  if (/(dark\s*mode|theme\s*(to\s*)?dark|अंधेरा|डार्क)/i.test(raw)) {
    actions.push({ type: 'SET_THEME', theme: 'dark', label: isHi ? 'डार्क मोड' : 'Dark mode' });
  } else if (/(light\s*mode|theme\s*(to\s*)?light|लाइट\s*मोड|उजाला)/i.test(raw)) {
    actions.push({ type: 'SET_THEME', theme: 'light', label: isHi ? 'लाइट मोड' : 'Light mode' });
  } else if (/(system\s*theme|theme\s*system|डिफ़ॉल्ट\s*थीम)/i.test(raw)) {
    actions.push({ type: 'SET_THEME', theme: 'system', label: isHi ? 'सिस्टम थीम' : 'System theme' });
  } else if (/(change\s*theme|toggle\s*theme|थीम\s*बदल)/i.test(raw)) {
    actions.push({ type: 'SET_THEME', theme: 'toggle', label: isHi ? 'थीम बदलें' : 'Toggle theme' });
  }

  const isConfirmation = /(confirm|कन्फर्म|proceed|स्वीकार|yes|haan|हाँ|book\s*now|book\s*this|confirm\s*booking|हाँ,?\s*बुकिंग\s*कन्फर्म)/i.test(raw);
  const isCancellation = /(cancel|कैनसल|रद्द|quit|exit|band\s*karo|nahi\s*chahiye|रद्द\s*करो|abort)/i.test(raw);
  const navAction = /(jao|kholo|dikhao|open|show|screen|me|mein|par|pe|chalo|जाओ|खोलो|दिखाओ|स्क्रीन|पेज|टैब|में|पर|चलो)/i;

  // Tabs / screens — include "take me to …" / "… screen"
  if (navTo('(home|होम)').test(raw) || ((/(home|होम)/i.test(raw)) && navAction.test(raw)) || /(go\s*(to\s*)?home|open\s*home|होम\s*(खोल|जाओ)|घर\s*पेज)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'home', label: isHi ? 'होम' : 'Home' });
  }
  if (
    !isConfirmation &&
    !isCancellation &&
    (navTo('(bookings?|orders?|बुकिंग्स?|ऑर्डर्स?)').test(raw) ||
      ((/(bookings?|orders?|बुकिंग्स?|ऑर्डर्स?)/i.test(raw)) && navAction.test(raw)) ||
      /(my\s*bookings?|go\s*(to\s*)?bookings?|show\s*(my\s*)?bookings?|open\s*bookings?|मेरी\s*बुकिंग्स?|बुकिंग्स?\s*खोलो|बुकिंग्स?\s*दिखाओ)/i.test(raw)) &&
    !/(status|track|ट्रैक|स्थिति|कन्फर्म|confirm|cancel|रद्द)/i.test(raw)
  ) {
    actions.push({ type: 'NAVIGATE', route: 'bookings', label: isHi ? 'बुकिंग्स' : 'Bookings' });
  }
  if (navTo('(search|खोज|सर्च)').test(raw) || ((/(search|खोज|सर्च)/i.test(raw)) && navAction.test(raw)) || /(open\s*search|search\s*services?|खोज|सर्च)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'search', label: isHi ? 'खोज' : 'Search' });
  }
  if (
    navTo('(profile|account|प्रोफ़ाइल|प्रोफाइल)').test(raw) ||
    ((/(profile|account|प्रोफ़ाइल|प्रोफाइल)/i.test(raw)) && navAction.test(raw)) ||
    /(my\s*profile|open\s*profile|प्रोफ़ाइल|प्रोफाइल)/i.test(raw)
  ) {
    actions.push({ type: 'NAVIGATE', route: 'profile', label: isHi ? 'प्रोफ़ाइल' : 'Profile' });
  }
  if (
    navTo('(ai|ai\\s*helper|assistant|एआई|categor(y|ies)|कैटेगरी|केटेगरी|श्रेणी)').test(raw) ||
    ((/(ai|ai\\s*helper|assistant|एआई|categor(y|ies)|कैटेगरी|केटेगरी|श्रेणी)/i.test(raw)) && navAction.test(raw)) ||
    /(open\s*ai|ai\s*screen|एआई\s*हेल्पर|एआई\s*स्क्रीन|go\s*to\s*categor|open\s*categor|कैटेगरी\s*(दिखाओ|खोलो|जाओ))/i.test(raw) ||
    /^(categories|category|कैटेगरी|केटेगरी)$/i.test(raw) ||
    /(plumb|electric|clean|carpent|paint|mechanic|appliance|ac\s*repair|salon|pest).*(categor|service|काम|सर्विस)/i.test(raw) ||
    /(categor|सर्विस).*(plumb|electric|clean|carpent|paint|mechanic|appliance|ac\s*repair|salon|pest)/i.test(raw)
  ) {
    actions.push({ type: 'NAVIGATE', route: 'ai', label: isHi ? 'AI हेल्पर' : 'AI Helper' });
  }
  if (navTo('(settings?|सेटिंग)').test(raw) || ((/(settings?|सेटिंग)/i.test(raw)) && navAction.test(raw))) {
    actions.push({ type: 'NAVIGATE', route: 'settings', label: isHi ? 'सेटिंग्स' : 'Settings' });
  }
  if (/(notifications?|सूचना)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'notifications', label: isHi ? 'सूचनाएं' : 'Notifications' });
  }
  if (/(support|help\s*desk|मदद\s*चैट|सपोर्ट)/i.test(raw) && !/(plumber|electrician|plumbing|electrical)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'support', label: isHi ? 'सपोर्ट' : 'Support' });
  }
  if (/\bsos\b|emergency\s*help|आपातकाल/i.test(raw) && !/(book|booking|electrician|plumber)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'sos', label: 'SOS' });
  }
  if (/(discover|ai\s*discovery|सेवाएं\s*देख)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'discovery', label: isHi ? 'डिस्कवर' : 'Discover' });
  }
  if (/(payments?(\s*history)?|payment\s*page|भुगतान(\s*पेज)?|पेमेंट)/i.test(raw) &&
      !/(pay\s*now|make\s*payment|pending\s*payment|बाकी|बकाया)/i.test(raw)) {
    actions.push({ type: 'NAVIGATE', route: 'payments', label: isHi ? 'भुगतान' : 'Payments' });
  }

  // Pay / track / call / invoice / rate — need booking context on client when possible
  if (/(pay\s*now|make\s*payment|pending\s*payment|payment\s*left|amount\s*due|बाकी\s*पेमेंट|भुगतान\s*कर)/i.test(raw)) {
    actions.push({ type: 'PAY_LATEST', label: isHi ? 'अभी भुगतान करें' : 'Pay now' });
  }
  if (/(track\s*(live|worker|booking)|live\s*track|लाइव\s*ट्रैक|ट्रैक\s*कर)/i.test(raw)) {
    actions.push({ type: 'TRACK_LATEST', label: isHi ? 'लाइव ट्रैक' : 'Track live' });
  }
  if (/(call\s*(the\s*)?worker|video\s*call|कॉल\s*कर|वर्कर\s*को\s*कॉल)/i.test(raw)) {
    actions.push({ type: 'CALL_WORKER', label: isHi ? 'ऐप से कॉल' : 'Call via Fixly' });
  }
  if (/(open\s*invoice|show\s*invoice|इनवॉइस)/i.test(raw)) {
    actions.push({ type: 'OPEN_INVOICE', label: isHi ? 'इनवॉइस' : 'Invoice' });
  }
  if (/(rate\s*(the\s*)?(worker|booking|service)|review\s*booking|रेटिंग|रिव्यू)/i.test(raw)) {
    actions.push({ type: 'OPEN_RATING', label: isHi ? 'रेटिंग दें' : 'Rate service' });
  }
  if (/(latest\s*booking|booking\s*status|order\s*status|बुकिंग\s*स्थिति|स्टेटस)/i.test(raw)) {
    actions.push({ type: 'SHOW_BOOKING_STATUS', label: isHi ? 'बुकिंग स्थिति' : 'Booking status' });
  }

  // Language
  if (/(speak\s*(in\s*)?hindi|हिंदी\s*में|switch\s*to\s*hindi)/i.test(raw)) {
    actions.push({ type: 'SET_LANGUAGE', language: 'hi', label: 'हिंदी' });
  } else if (/(speak\s*(in\s*)?english|अंग्रेज़ी|switch\s*to\s*english)/i.test(raw)) {
    actions.push({ type: 'SET_LANGUAGE', language: 'en', label: 'English' });
  }

  // Deduplicate by type+route+theme
  const seen = new Set();
  const unique = [];
  for (const a of actions) {
    const key = `${a.type}|${a.route || ''}|${a.theme || ''}|${a.language || ''}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(a);
  }

  const bookingy =
    isConfirmation ||
    isCancellation ||
    /(plumb|electric|clean|carpent|book\s*a|need\s*a\s*(plumber|electrician)|नल|बिजली|सफाई|बुक|confirm|कन्फर्म|emergency|sos|urgent|cancel|रद्द)/i.test(
      raw,
    );
  const isAppOnly = unique.length > 0 && !bookingy;

  let replyHint = null;
  if (unique.length > 0) {
    const labels = unique.map((a) => a.label).filter(Boolean).join(', ');
    replyHint = isHi
      ? `ठीक है — ${labels} खोल रहा हूँ।`
      : `Okay — opening ${labels} now.`;
  }

  return { actions: unique, replyHint, isAppOnly };
}

export default { resolveAppIntents };
