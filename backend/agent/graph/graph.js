import { StateGraph } from "@langchain/langgraph";
import { agentState } from "./state.js";
import { agentRouter } from "./router.js";
import { getAvailableWorkers, matchWorkerChoice, validateCategoryAgainstDB } from "../services/workerService.js";
import { calculateEstimate } from "../services/estimateService.js";
import { generateAutoDescription, createBookingInDB } from "../services/bookingService.js";
import Booking from "../../models/Booking.js";

/**
 * Suggested chips helper
 */
const getSuggestedReplies = (action, state = {}, lang = "hi") => {
    const isHi = lang === "hi";
    switch (action) {
        case "PROMPT_CATEGORY":
        case "RESET":
            return isHi
                ? ["नल लीकेज (Plumbing)", "बिजली / स्विच (Electrical)", "घर की सफाई (Cleaning)", "एसी सर्विस (Appliance)"]
                : ["Plumbing repair", "Electrician / Wiring", "Deep home cleaning", "AC service"];
        case "PROMPT_BOOKING_TYPE":
            return isHi
                ? ["Emergency SOS (तुरंत)", "Standard (सामान्य)", "Schedule (आगे का समय)"]
                : ["Emergency SOS", "Standard Booking", "Schedule for Later"];
        case "PROMPT_WORKER_SELECTION":
            return isHi
                ? ["स्वतः निकटतम चुनें (Auto)", "पहला कार्यकर्ता चुनें", "रद्द करें"]
                : ["Auto-assign nearest", "Select first worker", "Cancel"];
        case "PROMPT_SCHEDULE_TIME":
            return isHi
                ? ["कल सुबह 10 बजे", "कल दोपहर 3 बजे", "आज शाम 6 बजे"]
                : ["Tomorrow 10:00 AM", "Tomorrow 3:00 PM", "Today 6:00 PM"];
        case "PROMPT_CONFIRMATION":
            return isHi
                ? ["हाँ, बुकिंग कन्फर्म करें", "रद्द करें"]
                : ["Yes, confirm booking", "Cancel"];
        case "BOOKING_CREATED":
            return isHi
                ? ["बुकिंग स्थिति देखें", "नई सेवा बुक करें"]
                : ["Track booking", "Book another service"];
        default:
            return isHi
                ? ["प्लंबर चाहिए", "इलेक्ट्रीशियन चाहिए", "बुकिंग स्टेटस"]
                : ["Need a plumber", "Need an electrician", "Track booking"];
    }
};

/**
 * Category-aware diagnostic question — makes Fixly AI talk like a real
 * representative: it first understands the exact problem before pulling workers.
 */
const getDiagnosisPrompt = (category = "", isHi = false) => {
    const c = category.toLowerCase();
    const table = {
        plumb: {
            en: "Got it — a plumbing problem. To send the right pro, tell me what's happening. Is it a leaking tap, a blocked drain, low water pressure, or a running/overflowing toilet?",
            hi: "समझ गया — प्लंबिंग की समस्या। सही कारीगर भेजने के लिए बताइए क्या हो रहा है? नल से रिसाव, जाम पाइप/ड्रेन, कम पानी का प्रेशर, या टॉयलेट लीक?",
            chipsEn: ["Leaking tap", "Blocked drain", "Low water pressure", "Toilet issue"],
            chipsHi: ["नल से रिसाव", "जाम ड्रेन", "कम प्रेशर", "टॉयलेट समस्या"],
        },
        elect: {
            en: "Understood — an electrical issue. What exactly is the problem? For example: a fan not working, a switch/socket sparking, a tripping MCB, or a power/wiring fault?",
            hi: "समझ गया — बिजली की समस्या। ठीक-ठीक क्या दिक्कत है? जैसे: पंखा नहीं चल रहा, स्विच/सॉकेट में चिंगारी, MCB बार-बार गिर रहा, या वायरिंग/पावर फॉल्ट?",
            chipsEn: ["Fan not working", "Switch sparking", "MCB tripping", "Wiring/power fault"],
            chipsHi: ["पंखा नहीं चल रहा", "स्विच में चिंगारी", "MCB गिर रहा", "वायरिंग फॉल्ट"],
        },
        clean: {
            en: "Sure — a cleaning service. What would you like cleaned? For example: full home deep clean, bathroom, kitchen, or sofa/carpet?",
            hi: "ठीक है — सफाई सेवा। क्या साफ़ करवाना है? जैसे: पूरे घर की डीप क्लीनिंग, बाथरूम, किचन, या सोफा/कारपेट?",
            chipsEn: ["Full home deep clean", "Bathroom", "Kitchen", "Sofa/Carpet"],
            chipsHi: ["पूरे घर की सफाई", "बाथरूम", "किचन", "सोफा/कारपेट"],
        },
        carp: {
            en: "Got it — carpentry work. What do you need? For example: a door/lock repair, furniture fix, drawer/hinge issue, or new fitting?",
            hi: "समझ गया — कारपेंटर का काम। क्या चाहिए? जैसे: दरवाज़ा/ताला ठीक करना, फर्नीचर रिपेयर, दराज़/कब्ज़ा, या नई फिटिंग?",
            chipsEn: ["Door/Lock repair", "Furniture fix", "Drawer/Hinge", "New fitting"],
            chipsHi: ["दरवाज़ा/ताला", "फर्नीचर रिपेयर", "दराज़/कब्ज़ा", "नई फिटिंग"],
        },
        appl: {
            en: "Understood — an appliance issue. Which appliance and what's wrong? For example: AC not cooling, fridge fault, washing machine, or geyser/RO?",
            hi: "समझ गया — उपकरण की समस्या। कौन-सा उपकरण और क्या दिक्कत है? जैसे: AC ठंडा नहीं कर रहा, फ्रिज खराब, वॉशिंग मशीन, या गीज़र/RO?",
            chipsEn: ["AC not cooling", "Fridge fault", "Washing machine", "Geyser/RO"],
            chipsHi: ["AC ठंडा नहीं", "फ्रिज खराब", "वॉशिंग मशीन", "गीज़र/RO"],
        },
        paint: {
            en: "Sure — painting work. What's the scope? For example: a single room, full home, a wall/patch touch-up, or waterproofing?",
            hi: "ठीक है — पेंटिंग का काम। कितना करवाना है? जैसे: एक कमरा, पूरा घर, दीवार/पैच टच-अप, या वॉटरप्रूफिंग?",
            chipsEn: ["Single room", "Full home", "Wall touch-up", "Waterproofing"],
            chipsHi: ["एक कमरा", "पूरा घर", "दीवार टच-अप", "वॉटरप्रूफिंग"],
        },
        garden: {
            en: "Got it — gardening help. What do you need? For example: lawn mowing, plant trimming, garden cleanup, or new planting?",
            hi: "समझ गया — बागवानी में मदद। क्या चाहिए? जैसे: घास की कटाई, पौधों की छँटाई, बगीचे की सफाई, या नई रोपाई?",
            chipsEn: ["Lawn mowing", "Plant trimming", "Garden cleanup", "New planting"],
            chipsHi: ["घास कटाई", "पौधों की छँटाई", "बगीचे की सफाई", "नई रोपाई"],
        },
    };

    const key = Object.keys(table).find((k) => c.includes(k));
    const entry = key ? table[key] : null;
    if (!entry) {
        return {
            question: isHi
                ? `समझ गया — ${category} सेवा। कृपया अपनी समस्या थोड़ा विस्तार से बताइए ताकि मैं सही कारीगर भेज सकूँ।`
                : `Understood — a ${category} request. Could you describe the exact issue in a line so I can match the right professional?`,
            chips: [],
        };
    }
    return {
        question: isHi ? entry.hi : entry.en,
        chips: isHi ? entry.chipsHi : entry.chipsEn,
    };
};

/**
 * Main Agent Handler Node
 */
export const fixlyAgentHandler = async (state) => {
    const text = (state.prompt || "").trim();
    const lang = state.language || "en";
    const isHi = lang === "hi";

    // 1. IDENTITY QUERY
    if (state.intent === "IDENTITY_QUERY") {
        const reply = isHi
            ? "नमस्ते! मैं Fixly AI Assistant हूँ, जिसे वैभव जैन (Code Vertex Team) द्वारा Fixly Cooperative प्लेटफॉर्म के लिए विकसित किया गया है। मैं प्लंबिंग, बिजली, घर की सफाई, कारपेंटर आदि घरेलू सेवाओं की बुकिंग में आपकी सहायता करता हूँ।"
            : "Hello! I am Fixly AI Assistant, developed by Code Vertex Team for Fixly Cooperative Gig Services. I help you book verified home professionals like Plumbers, Electricians, Cleaners, and Carpenters.";
        return {
            ...state,
            aiResponse: reply,
            action: "IDENTITY_INFO",
            suggestedReplies: getSuggestedReplies("IDENTITY_INFO", state, lang)
        };
    }

    // 2. OFF TOPIC GUARDRAIL
    if (state.intent === "OFF_TOPIC") {
        const reply = isHi
            ? "माफ़ कीजिए, मैं केवल Fixly सहकारी घरेलू सेवाओं (जैसे प्लंबिंग, बिजली, सफाई, कारपेंटर आदि) की बुकिंग के लिए प्रशिक्षित हूँ। अन्य विषयों पर मेरे पास डेटा नहीं है। कृपया अपनी घरेलू सेवा से संबंधित आवश्यकता बताइए।"
            : "I apologize, I am exclusively trained to assist with Fixly Cooperative home services (Plumbing, Electrical, Cleaning, Carpentry) and bookings. I do not have information on other topics. Please let me know which home service you require.";
        return {
            ...state,
            aiResponse: reply,
            action: "OFF_TOPIC_GUARD",
            suggestedReplies: getSuggestedReplies("PROMPT_CATEGORY", state, lang)
        };
    }

    // 3. CANCEL / EXIT
    if (state.intent === "CANCEL") {
        const reply = isHi
            ? "बुकिंग सत्र रद्द कर दिया गया है। कोई बुकिंग नहीं बनाई गई। जब भी आपको किसी सेवा की आवश्यकता हो, बेझिझक Fixly से कहें!"
            : "Booking session has been cancelled. No booking was created. Feel free to reach out anytime!";
        return {
            ...state,
            category: null,
            workerId: null,
            step: null,
            aiResponse: reply,
            action: "SESSION_ABORTED",
            suggestedReplies: getSuggestedReplies("PROMPT_CATEGORY", state, lang)
        };
    }

    // 4. RESET / START OVER
    if (state.intent === "RESET") {
        const reply = isHi
            ? "आइए नए सिरे से शुरू करते हैं! Fixly पर आपको किस घरेलू सेवा की आवश्यकता है? (जैसे: प्लंबिंग, बिजली, घर की सफाई, कारपेंटर आदि)"
            : "Let's start fresh! Which home service do you need? (e.g. Plumbing, Electrical, Cleaning, Carpentry)";
        return {
            ...state,
            category: null,
            workerId: null,
            workerName: null,
            bookingType: null,
            isEmergency: false,
            scheduledTime: null,
            problemDescription: null,
            estimate: null,
            policy: null,
            step: "AWAITING_CATEGORY",
            aiResponse: reply,
            action: "RESET",
            suggestedReplies: getSuggestedReplies("PROMPT_CATEGORY", state, lang)
        };
    }

    // 5. STATUS QUERY
    if (state.intent === "STATUS_QUERY") {
        try {
            const userBookings = await Booking.find({ customer: state.userId })
                .populate('service', 'title category')
                .populate('worker', 'name avatar')
                .sort({ createdAt: -1 })
                .limit(3)
                .lean();

            if (!userBookings || userBookings.length === 0) {
                const reply = isHi
                    ? "आपकी कोई सक्रिय बुकिंग नहीं मिली। क्या आप कोई नई सेवा बुक करना चाहते हैं?"
                    : "No active bookings found for your account. Would you like to book a service?";
                return {
                    ...state,
                    aiResponse: reply,
                    action: "NO_BOOKINGS",
                    bookings: [],
                    suggestedReplies: getSuggestedReplies("PROMPT_CATEGORY", state, lang)
                };
            }

            const latest = userBookings[0];
            const workerInfo = latest.worker
                ? latest.worker.name
                : (isHi ? "कार्यकर्ता आवंटित हो रहा है" : "Assigning worker");
            const reply = isHi
                ? `आपकी हालिया बुकिंग #${latest.bookingId} (${latest.service?.title || latest.problemDescription || "Service"}) की स्थिति "${latest.status}" है। कार्यकर्ता: ${workerInfo}। ऐप से सुरक्षित कॉल करें — फोन नंबर साझा नहीं किया जाता।`
                : `Your recent booking #${latest.bookingId} (${latest.service?.title || latest.problemDescription || "Service"}) is currently "${latest.status}". Assigned worker: ${workerInfo}. Use in-app call — phone numbers are never shared.`;

            // Never leak worker phone numbers into AI chat payloads.
            const safeBookings = userBookings.map((b) => {
                const copy = { ...b };
                if (copy.worker && typeof copy.worker === 'object') {
                    const { phone, ...workerRest } = copy.worker;
                    copy.worker = workerRest;
                }
                return copy;
            });

            return {
                ...state,
                aiResponse: reply,
                action: "BOOKING_STATUS",
                bookings: safeBookings,
                suggestedReplies: getSuggestedReplies("BOOKING_STATUS", state, lang)
            };
        } catch (e) {
            console.warn("[Graph] Status query error:", e.message);
        }
    }

    // 6. BOOKING FLOW & PROGRESSIVE SLOT FILLING
    let currentCategory = state.category;

    // STEP A: If Category is missing -> Prompt Category
    if (!currentCategory) {
        const reply = isHi
            ? "नमस्ते! मैं Fixly AI Assistant हूँ। आपको किस सेवा की आवश्यकता है? (जैसे: प्लंबिंग, बिजली/स्विच, घर की सफाई, कारपेंटर आदि)"
            : "Hello! I am Fixly AI Assistant. Which home service do you need? (e.g. Plumbing, Electrical, Cleaning, Carpentry)";
        return {
            ...state,
            step: "AWAITING_CATEGORY",
            aiResponse: reply,
            action: "PROMPT_CATEGORY",
            suggestedReplies: getSuggestedReplies("PROMPT_CATEGORY", state, lang)
        };
    }

    // STEP A2: Dynamic Database Validation (Ensure Category exists in DB Service catalog created by Admin)
    const categoryCheck = await validateCategoryAgainstDB(currentCategory);
    if (!categoryCheck.isValid) {
        const activeListStr = categoryCheck.availableCategories.join(", ");
        const reply = isHi
            ? `माफ़ कीजिए, वर्तमान में Fixly पर "${currentCategory}" सेवा उपलब्ध नहीं है। हमारी उपलब्ध सक्रिय सेवाएँ हैं: ${activeListStr}। कृपया इनमें से कोई सेवा चुनें।`
            : `I apologize, "${currentCategory}" service is currently not offered on Fixly. Our currently available services are: ${activeListStr}. Please choose from these services.`;
        return {
            ...state,
            category: null,
            step: "AWAITING_CATEGORY",
            aiResponse: reply,
            action: "CATEGORY_NOT_SUPPORTED",
            suggestedReplies: categoryCheck.availableCategories
        };
    }
    currentCategory = categoryCheck.matchedCategory;

    // STEP A3: DIAGNOSIS — behave like a real representative and understand the
    // exact problem BEFORE surfacing workers. Ask exactly once per session.
    const pastDiagnosis =
        state.step === "AWAITING_DIAGNOSIS" ||
        Boolean(state.bookingType) ||
        Boolean(state.workerId) ||
        [
            "AWAITING_BOOKING_TYPE",
            "AWAITING_WORKER_SELECTION",
            "AWAITING_SCHEDULE_TIME",
            "AWAITING_CONFIRMATION",
            "NO_WORKERS",
            "COMPLETED",
        ].includes(state.step);

    if (!pastDiagnosis && !state.isEmergency) {
        const { question, chips } = getDiagnosisPrompt(currentCategory, isHi);
        return {
            ...state,
            category: currentCategory,
            step: "AWAITING_DIAGNOSIS",
            aiResponse: question,
            action: "PROMPT_DIAGNOSIS",
            suggestedReplies: chips,
        };
    }

    // Capture the symptom the user just described in reply to the diagnosis.
    if (state.step === "AWAITING_DIAGNOSIS" && text) {
        state.problemDescription = text;
    }

    // STEP B: Fetch available workers for this category (used from here on)
    const availableWorkers = await getAvailableWorkers({
        category: currentCategory,
        coordinates: state.coordinates
    });

    if (!availableWorkers || availableWorkers.length === 0) {
        const reply = isHi
            ? `माफ़ कीजिए, वर्तमान में आपके क्षेत्र में ${currentCategory} के कोई कार्यकर्ता उपलब्ध नहीं हैं। क्या आप बाद के समय के लिए शेड्यूल करना चाहेंगे?`
            : `Sorry, no verified ${currentCategory} workers are currently available near your location. Would you like to schedule for later?`;
        return {
            ...state,
            category: currentCategory,
            workers: [],
            step: "NO_WORKERS",
            aiResponse: reply,
            action: "NO_WORKERS_AVAILABLE",
            suggestedReplies: ["Schedule for Later", "Try another service", "Cancel"]
        };
    }

    // STEP C: Check Booking Type (STANDARD vs EMERGENCY_SOS vs SCHEDULED)
    // Deterministic FSM: once past this step, never re-ask (recover missing slot).
    let currentBookingType = state.bookingType;
    if (
        !currentBookingType &&
        ["AWAITING_WORKER_SELECTION", "AWAITING_CONFIRMATION", "AWAITING_SCHEDULE_TIME"].includes(state.step)
    ) {
        currentBookingType = "STANDARD";
        console.warn("[FixlyAgent] Recovered missing bookingType → STANDARD at step", state.step);
    }

    if (!currentBookingType) {
        const reply = isHi
            ? `ठीक है, ${currentCategory} सेवा नोट कर ली। आपके क्षेत्र में ${availableWorkers.length} सत्यापित कार्यकर्ता उपलब्ध हैं। आप इसे कैसे बुक करना चाहेंगे?\n• Emergency SOS (तत्काल, 15-30 मिनट में)\n• Standard (सामान्य सेवा)\n• Schedule (आगे के समय के लिए)`
            : `Got it, noted your ${currentCategory} request. There are ${availableWorkers.length} verified professionals available near you. How would you like to book?\n• Emergency SOS (instant priority)\n• Standard (regular service)\n• Schedule for later`;
        return {
            ...state,
            category: currentCategory,
            // Workers are NOT attached here — they are shown once at worker selection.
            step: "AWAITING_BOOKING_TYPE",
            aiResponse: reply,
            action: "PROMPT_BOOKING_TYPE",
            suggestedReplies: getSuggestedReplies("PROMPT_BOOKING_TYPE", state, lang)
        };
    }

    // STEP D1: If EMERGENCY SOS -> Fast Path with Nearest Worker Selection
    if (currentBookingType === "EMERGENCY_SOS" || state.isEmergency) {
        let assignedWorker = null;
        if (state.workerId) {
            assignedWorker = availableWorkers.find(w => String(w._id) === String(state.workerId)) || availableWorkers[0];
        } else {
            const choice = matchWorkerChoice(state.workerSelection || text, availableWorkers);
            if (choice) {
                if (choice.isAuto) {
                    state.isAutoAssign = true;
                    assignedWorker = choice.worker || availableWorkers[0];
                } else if (choice.worker) {
                    assignedWorker = choice.worker;
                }
                if (assignedWorker) {
                    state.workerId = assignedWorker._id;
                    state.workerName = assignedWorker.name;
                    state.workerRate = assignedWorker.hourlyRate;
                }
            }
        }

        // If worker not chosen yet, present available workers for Emergency SOS!
        if (!assignedWorker && !state.isAutoAssign && !state.workerId) {
            const reply = isHi
                ? `आपातकालीन सेवा (Emergency SOS) के लिए आपके क्षेत्र में ${availableWorkers.length} सत्यापित कार्यकर्ता उपलब्ध हैं। नीचे से कार्यकर्ता चुनें या "स्वतः असाइन करें" कहें:`
                : `For Emergency SOS, found ${availableWorkers.length} verified cooperative workers near you. Please select a worker below or reply "Auto-assign":`;
            return {
                ...state,
                category: currentCategory,
                bookingType: "EMERGENCY_SOS",
                isEmergency: true,
                workers: availableWorkers,
                step: "AWAITING_WORKER_SELECTION",
                aiResponse: reply,
                action: "PROMPT_WORKER_SELECTION",
                suggestedReplies: getSuggestedReplies("PROMPT_WORKER_SELECTION", state, lang)
            };
        }

        assignedWorker = assignedWorker || availableWorkers[0];
        const autoDesc = await generateAutoDescription({
            category: currentCategory,
            promptText: state.problemDescription || text,
            isEmergency: true
        });

        const { estimate, policy } = await calculateEstimate({
            category: currentCategory,
            workerRate: assignedWorker?.hourlyRate,
            isEmergency: true,
            lang
        });

        // Check if user confirmed or proceed to prompt confirmation
        if (state.intent === "CONFIRMATION" || state.confirmation) {
            const newBooking = await createBookingInDB({
                userId: state.userId,
                category: currentCategory,
                bookingType: "EMERGENCY_SOS",
                isEmergency: true,
                scheduledTime: null,
                workerId: assignedWorker?._id,
                problemDescription: autoDesc,
                addressLine: state.addressLine,
                coordinates: state.coordinates,
                estimate
            });

            const reply = isHi
                ? `आपातकालीन SOS बुकिंग #${newBooking.bookingId} दर्ज कर ली गई है। निकटतम कार्यकर्ता ${assignedWorker?.name} को तुरंत रवाना किया गया है। कुल राशि: ₹${estimate.totalAmount}।`
                : `Emergency SOS booking #${newBooking.bookingId} confirmed. Nearest worker ${assignedWorker?.name} has been dispatched immediately. Total amount: ₹${estimate.totalAmount}.`;

            return {
                ...state,
                category: currentCategory,
                bookingType: "EMERGENCY_SOS",
                isEmergency: true,
                workerId: assignedWorker?._id,
                workerName: assignedWorker?.name,
                problemDescription: autoDesc,
                estimate,
                policy,
                booking: newBooking,
                step: "COMPLETED",
                aiResponse: reply,
                action: "BOOKING_CREATED",
                suggestedReplies: getSuggestedReplies("BOOKING_CREATED", state, lang)
            };
        }

        // Prompt SOS Confirmation
        const reply = isHi
            ? `आपातकालीन सेवा तैयार है:\n• कार्यकर्ता: ${assignedWorker?.name} (${assignedWorker?.rating}★, ${assignedWorker?.distanceKm} किमी दूर)\n• अनुमानित लागत: ₹${estimate.totalAmount} (₹50 आपातकालीन शुल्क शामिल, ₹0 प्लेटफार्म शुल्क)\n• कार्य विवरण: "${autoDesc}"\n\nक्या मैं तुरंत कार्यकर्ता को रवाना करने के लिए बुकिंग कन्फर्म कर दूँ? (हाँ / नहीं बोलें)`
            : `Emergency service ready:\n• Worker: ${assignedWorker?.name} (${assignedWorker?.rating}★, ${assignedWorker?.distanceKm} km away)\n• Total Amount: ₹${estimate.totalAmount} (Includes ₹50 emergency fee, ₹0 platform fee)\n• Task: "${autoDesc}"\n\nShall I confirm immediate dispatch? (Reply Yes / No)`;

        return {
            ...state,
            category: currentCategory,
            bookingType: "EMERGENCY_SOS",
            isEmergency: true,
            workerId: assignedWorker?._id,
            workerName: assignedWorker?.name,
            workerRate: assignedWorker?.hourlyRate,
            problemDescription: autoDesc,
            estimate,
            policy,
            step: "AWAITING_CONFIRMATION",
            aiResponse: reply,
            action: "PROMPT_CONFIRMATION",
            suggestedReplies: getSuggestedReplies("PROMPT_CONFIRMATION", state, lang)
        };
    }

    // STEP D2: If SCHEDULED -> Ensure Date and Time is filled!
    if (currentBookingType === "SCHEDULED") {
        if (!state.scheduledTime) {
            // Check if user provided time in message
            const hasTime = ["कल", "आज", "सुबह", "दोपहर", "शाम", "बजे", "tomorrow", "today", "morning", "afternoon", "evening", "am", "pm"].some(w => text.toLowerCase().includes(w));
            if (hasTime && text.length >= 3) {
                state.scheduledTime = text;
            } else {
                const reply = isHi
                    ? `कृपया बताइए आप किस दिन और समय पर सेवा चाहते हैं? (जैसे: "कल सुबह 10 बजे" या "आज शाम 5 बजे")`
                    : `Please specify your preferred date and time (e.g. "Tomorrow 10:00 AM" or "Today 5:00 PM"):`;
                return {
                    ...state,
                    category: currentCategory,
                    bookingType: "SCHEDULED",
                    step: "AWAITING_SCHEDULE_TIME",
                    aiResponse: reply,
                    action: "PROMPT_SCHEDULE_TIME",
                    suggestedReplies: getSuggestedReplies("PROMPT_SCHEDULE_TIME", state, lang)
                };
            }
        }
    }

    // STEP D3: Worker Selection (For Standard or Scheduled)
    let selectedWorkerId = state.workerId;
    let selectedWorkerName = state.workerName;
    let selectedWorkerRate = state.workerRate;

    if (!selectedWorkerId && !state.isAutoAssign) {
        const choice = matchWorkerChoice(text, availableWorkers);
        if (choice) {
            if (choice.isAuto) {
                state.isAutoAssign = true;
                selectedWorkerId = choice.worker?._id || availableWorkers[0]?._id;
                selectedWorkerName = isHi ? "निकटतम कार्यकर्ता (स्वतः आवंटित)" : "Auto-Assigned Nearest Worker";
                selectedWorkerRate = choice.worker?.hourlyRate || availableWorkers[0]?.hourlyRate;
            } else if (choice.worker) {
                selectedWorkerId = choice.worker._id;
                selectedWorkerName = choice.worker.name;
                selectedWorkerRate = choice.worker.hourlyRate;
            }
        } else {
            // Worker not chosen yet -> Prompt Worker Selection with worker cards in data.workers
            const reply = isHi
                ? `आपके क्षेत्र में ${availableWorkers.length} सत्यापित ${currentCategory} कार्यकर्ता ऑनलाइन उपलब्ध हैं। आप नीचे दी गई सूची से कार्यकर्ता चुन सकते हैं या "स्वतः असाइन करें" कह सकते हैं:`
                : `Found ${availableWorkers.length} verified ${currentCategory} cooperative workers near you. Please choose a worker from the list below or reply "Auto-assign":`;
            return {
                ...state,
                category: currentCategory,
                bookingType: currentBookingType,
                workers: availableWorkers,
                step: "AWAITING_WORKER_SELECTION",
                aiResponse: reply,
                action: "PROMPT_WORKER_SELECTION",
                suggestedReplies: getSuggestedReplies("PROMPT_WORKER_SELECTION", state, lang)
            };
        }
    }

    // STEP E: Calculate Estimate & Policy
    const { estimate, policy } = await calculateEstimate({
        category: currentCategory,
        workerRate: selectedWorkerRate,
        isEmergency: false,
        lang
    });

    // STEP F: Check Confirmation Intent -> Create Booking in DB!
    if (state.step === "AWAITING_CONFIRMATION" && (state.intent === "CONFIRMATION" || state.confirmation)) {
        const newBooking = await createBookingInDB({
            userId: state.userId,
            category: currentCategory,
            bookingType: currentBookingType,
            isEmergency: false,
            scheduledTime: state.scheduledTime,
            workerId: selectedWorkerId,
            problemDescription: state.problemDescription || `${currentCategory} service via Fixly AI`,
            addressLine: state.addressLine,
            coordinates: state.coordinates,
            estimate
        });

        const reply = isHi
            ? `बधाई हो! आपकी ${currentCategory} सेवा की बुकिंग #${newBooking.bookingId} सफलतापूर्वक दर्ज कर ली गई है। कुल अनुमानित शुल्क: ₹${estimate.totalAmount}। आवंटित कार्यकर्ता: ${selectedWorkerName || "Fixly Worker"}।`
            : `Your ${currentCategory} booking #${newBooking.bookingId} has been confirmed. Total estimated fee: ₹${estimate.totalAmount}. Assigned worker: ${selectedWorkerName || "Fixly Worker"}.`;

        return {
            ...state,
            category: currentCategory,
            bookingType: currentBookingType,
            workerId: selectedWorkerId,
            workerName: selectedWorkerName,
            estimate,
            policy,
            booking: newBooking,
            step: "COMPLETED",
            aiResponse: reply,
            action: "BOOKING_CREATED",
            suggestedReplies: getSuggestedReplies("BOOKING_CREATED", state, lang)
        };
    }

    // STEP G: Prompt Confirmation with Summary & Fair Wage Policy
    const scheduleLine = state.scheduledTime ? (isHi ? `\n• समय: ${state.scheduledTime}` : `\n• Scheduled: ${state.scheduledTime}`) : "";
    const reply = isHi
        ? `लागत अनुमान तैयार है:\n• आधार शुल्क: ₹${estimate.baseServiceFee}\n• प्लेटफॉर्म शुल्क: ₹0 (Fixly सहकारी मॉडल)\n• कुल राशि: ₹${estimate.totalAmount}${scheduleLine}\nFixly निष्पक्ष मजदूरी: 100% राशि सीधे कार्यकर्ता को दी जाती है।\nकार्यकर्ता: ${selectedWorkerName || "चयनित कार्यकर्ता"}।\n\nक्या मैं आपकी यह बुकिंग कन्फर्म कर दूँ? (हाँ / नहीं बोलें)`
        : `Here is your price estimate:\n• Base Service Fee: ₹${estimate.baseServiceFee}\n• Platform Fee: ₹0 (Fixly Cooperative)\n• Total Amount: ₹${estimate.totalAmount}${scheduleLine}\nFixly Fair Wage Guarantee: 100% payout directly to the worker.\nWorker: ${selectedWorkerName || "Selected Worker"}.\n\nShall I confirm and place this booking for you? (Reply Yes / No)`;

    return {
        ...state,
        category: currentCategory,
        bookingType: currentBookingType,
        workerId: selectedWorkerId,
        workerName: selectedWorkerName,
        workerRate: selectedWorkerRate,
        // Workers already chosen — no carousel on the confirmation step.
        estimate,
        policy,
        step: "AWAITING_CONFIRMATION",
        aiResponse: reply,
        action: "PROMPT_CONFIRMATION",
        suggestedReplies: getSuggestedReplies("PROMPT_CONFIRMATION", state, lang)
    };
};

// Build StateGraph
const workflow = new StateGraph(agentState);

workflow.addNode("router", agentRouter);
workflow.addNode("handler", fixlyAgentHandler);

workflow.addEdge("__start__", "router");
workflow.addEdge("router", "handler");
workflow.addEdge("handler", "__end__");

export const graph = workflow.compile();
export default graph;
