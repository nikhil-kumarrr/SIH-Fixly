/**
 * Mint Gemini Live ephemeral tokens (REST).
 * Locked to gemini-3.1-flash-live-preview + AUDIO for client WebSocket sessions.
 *
 * NOTE (2026): REST AuthToken uses `bidiGenerateContentSetup`, NOT
 * `liveConnectConstraints` (SDK camelCase field that REST rejects).
 */
export const LIVE_MODEL = process.env.GEMINI_LIVE_MODEL || 'gemini-3.1-flash-live-preview';

export async function createGeminiLiveEphemeralToken({
  language = 'en',
  expireMinutes = 30,
} = {}) {
  const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || '';
  if (!apiKey || apiKey.length < 8) {
    throw new Error('GEMINI_API_KEY not configured');
  }

  const now = Date.now();
  const expireTime = new Date(now + expireMinutes * 60 * 1000).toISOString();
  const newSessionExpireTime = new Date(now + 2 * 60 * 1000).toISOString();
  const systemInstruction = buildLiveSystemInstruction(language);

  const tools = [
    {
      functionDeclarations: [
        {
          name: 'call_fixly_brain',
          description:
            'Fixly booking brain (Flash). Use for home services, booking, price, worker, status.',
          parameters: {
            type: 'OBJECT',
            properties: {
              utterance: {
                type: 'STRING',
                description: 'User request verbatim',
              },
            },
            required: ['utterance'],
          },
        },
        {
          name: 'call_fixly_app',
          description:
            'In-app actions: theme, navigate, pay, track, call worker, invoice, rating, language, settings, SOS, discovery.',
          parameters: {
            type: 'OBJECT',
            properties: {
              utterance: {
                type: 'STRING',
                description: 'User request verbatim',
              },
            },
            required: ['utterance'],
          },
        },
      ],
    },
  ];

  const body = {
    uses: 1,
    expireTime,
    newSessionExpireTime,
    bidiGenerateContentSetup: {
      model: `models/${LIVE_MODEL}`,
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: {
          // Indian English cadence when supported by the Live model.
          languageCode: String(language || 'en').toLowerCase().startsWith('hi')
            ? 'hi-IN'
            : 'en-IN',
          voiceConfig: {
            // Youthful/warm — less robotic than Aoede (half-cascade safe voice).
            prebuiltVoiceConfig: { voiceName: 'Leda' },
          },
        },
      },
      systemInstruction: {
        parts: [{ text: systemInstruction }],
      },
      // Chat UI transcripts (mic stays open; STT is display-only).
      inputAudioTranscription: {},
      outputAudioTranscription: {},
      tools,
    },
  };

  const res = await fetch(
    'https://generativelanguage.googleapis.com/v1beta/auth_tokens',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify(body),
    },
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Live token failed (${res.status}): ${errText.slice(0, 400)}`);
  }

  const data = await res.json();
  const token = data.name || data.token || data.authToken?.name;
  if (!token) {
    throw new Error('Live token response missing name');
  }

  return {
    token,
    model: LIVE_MODEL,
    expireTime,
    websocketUrl:
      `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained?access_token=${encodeURIComponent(token)}`,
  };
}

function buildLiveSystemInstruction(language) {
  const lang = String(language || 'en').toLowerCase();
  const langRule =
    lang === 'hi'
      ? 'Speak ONLY natural Hindi (friendly, like a helpful Fixly agent on a phone call). Never repeat the same answer in English.'
      : 'Speak ONLY natural Indian English (en-IN). Soft Hinglish words OK (haan, bilkul, theek hai). Never sound like a stiff robot or US call-center script. Never repeat the same answer twice in another language.';

  return [
    'You are Fixly AI, Fixly home-services voice assistant on a live call.',
    'Sound human: warm, calm, slightly conversational. Use short spoken sentences. Contractions speech OK (I\'m, you\'ll, we\'ve).',
    'Vary rhythm — not flat TTS. One clear spoken answer per turn.',
    'Lowest latency. Full duplex — user may barge in anytime.',
    'While thinking briefly you may say short fillers like "hmm", "haan", "ok" — then answer.',
    langRule,
    'Never invent bookings. For booking/search/status/price use call_fixly_brain.',
    'For app UI (theme, navigate, pay, track, call, invoice, rating, settings, SOS, language) use call_fixly_app.',
    'After a tool returns: if spokenReply is non-empty, speak THAT text once in a natural voice — do not invent a shorter "Done." substitute.',
    'If spokenReply is empty, wait — the client will send an explicit speak instruction; then speak that instruction once.',
    'Do not read bullet points or markdown. Turn lists into spoken options: "Emergency, Standard, or Schedule for later."',
  ].join(' ');
}

export default createGeminiLiveEphemeralToken;
