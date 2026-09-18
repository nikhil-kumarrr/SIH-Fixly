import Service from '../models/Service.js';
import User from '../models/User.js';
import { uploadToCloudinary } from '../utils/cloudinary.js';
import { getGroqClient, classifyIssueWithGroq } from '../utils/groqClient.js';
import { analyzeImageWithGemini, isGeminiVisionConfigured } from '../utils/geminiVisionClient.js';

// Screen 4: AI Issue Analyzer
export const analyzeIssue = async (req, res) => {
    try {
        const { problemDescription } = req.body;
        if (!problemDescription) {
            return res.status(400).json({ success: false, message: 'Problem description is required.' });
        }

        let issueImageUrl = null;
        if (req.file) {
            const uploaded = await uploadToCloudinary(req.file.buffer, 'gigconnect/ai');
            issueImageUrl = uploaded.secure_url;
        }

        // Use Gemini Vision for image analysis if image is provided, otherwise use Groq for text
        let detectedCategory;
        let geminiAnalysis = null;

        if (req.file && isGeminiVisionConfigured()) {
            // Use Gemini Vision to analyze the image
            geminiAnalysis = await analyzeImageWithGemini(req.file.buffer);
            detectedCategory = geminiAnalysis.category;
        } else {
            // Fall back to Groq for text-based classification
            detectedCategory = await classifyIssueWithGroq(problemDescription.toLowerCase());
        }

        let estimatedHours = 1; // default

        // Adjust estimated hours based on category
        switch(detectedCategory) {
            case 'Electrical':
                estimatedHours = 1.5;
                break;
            case 'Plumbing':
                estimatedHours = 2;
                break;
            case 'Cleaning':
                estimatedHours = 3;
                break;
            case 'HVAC':
                estimatedHours = 2.5;
                break;
            case 'Carpentry':
                estimatedHours = 4;
                break;
            case 'Painting':
                estimatedHours = 3.5;
                break;
            default:
                estimatedHours = 1;
        }

        const suggestedService = await Service.findOne({ category: detectedCategory, isActive: true }).lean();

        return res.status(200).json({
            success: true,
            analysis: {
                category: detectedCategory,
                estimatedHours,
                suggestedService: suggestedService || null,
                issueImageUrl,
                geminiAnalysis: geminiAnalysis || null,
                aiNote: geminiAnalysis
                    ? `Based on the image analysis: ${geminiAnalysis.description}. We recommend a ${detectedCategory} specialist.`
                    : `Based on your query "${problemDescription}", we recommend a ${detectedCategory} specialist.`
            }
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const serviceDiscovery = async (req, res) => {
    try {
        const text = String(req.body.text || req.body.problemDescription || '').toLowerCase();
        if (!text) return res.status(400).json({ success: false, code: 'VALIDATION_ERROR', message: 'Text is required.' });
        
        const isAiDiscoveryEnabled = String(process.env.AI_DISCOVERY_ENABLED ?? process.env.ENABLE_AI_DISCOVERY ?? 'false').toLowerCase() === 'true';

        let aiResult = null;
        if (isAiDiscoveryEnabled) {
            try {
                const rawUrl = process.env.SERVICE_DISCOVERY_URL || process.env.AI_DISCOVERY_URL || 'http://127.0.0.1:8002';
                const discoveryUrl = rawUrl.replace(/\/discover\/?$/, '').replace(/\/$/, '');
                const response = await fetch(`${discoveryUrl}/discover`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ text })
                });
                if (response.ok) {
                    aiResult = await response.json();
                }
            } catch (err) {
                console.error('AI Service Discovery failed, falling back to Node classifier:', err.message);
            }
        }

        const services = await Service.find({ isActive: true }).lean();

        if (aiResult && aiResult.top_matches) {
            // AI service succeeded
            const suggestions = aiResult.top_matches.map((match) => {
                const s = services.find((srv) => srv.category === match.category);
                return {
                    categoryId: match.category,
                    serviceId: s ? s._id : null,
                    title: s ? s.title : match.category,
                    confidence: match.probability || match.score || 0.5,
                };
            });
            return res.status(200).json({ success: true, suggestions });
        }

        // Fallback: Node keyword matcher
        const scored = services.map((s) => {
            const hay = `${s.title || ''} ${s.category || ''} ${s.description || ''}`.toLowerCase();
            let score = 0;
            for (const token of text.split(/\s+/).filter((t) => t.length > 2)) {
                if (hay.includes(token)) score += 1;
            }
            return { service: s, score };
        }).filter((x) => x.score > 0).sort((a, b) => b.score - a.score).slice(0, 5);
        
        const fallback = scored.length ? scored : services.slice(0, 3).map((s) => ({ service: s, score: 0.2 }));
        const max = Math.max(...fallback.map((x) => x.score), 1);
        return res.status(200).json({
            success: true,
            suggestions: fallback.map((x) => ({
                categoryId: x.service.category,
                serviceId: x.service._id,
                title: x.service.title,
                confidence: Number((x.score / max).toFixed(2)),
            })),
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

export const matchWorkers = async (req, res) => {
    try {
        const { serviceId, latitude, longitude } = req.body || {};
        if (latitude == null || longitude == null) {
            return res.status(400).json({ success: false, code: 'VALIDATION_ERROR', message: 'Latitude and longitude are required.' });
        }
        const workers = await User.find({
            role: 'worker',
            location: {
                $near: {
                    $geometry: { type: 'Point', coordinates: [Number(longitude), Number(latitude)] },
                    $maxDistance: 15000,
                },
            },
        }).select('name workerProfile location isVerified');

        const matches = workers.slice(0, 10).map((w, i) => {
            const rating = w.workerProfile?.rating || 0;
            const available = Boolean(w.workerProfile?.isOnline);
            const jobs = w.workerProfile?.totalJobs || 0;
            let score = Math.round((rating / 5) * 40 + (available ? 25 : 5) + Math.min(jobs, 20) + (w.isVerified ? 15 : 0));
            if (serviceId && (w.workerProfile?.categories || []).length) score += 5;
            const reasons = [];
            if (rating >= 4.5) reasons.push('Strong skill match');
            if (available) reasons.push('Available now');
            if (jobs >= 10) reasons.push('High completion rate');
            if (!reasons.length) reasons.push('Nearby worker');
            return { workerId: w._id, matchScore: Math.min(99, score + (10 - i)), reasons };
        }).sort((a, b) => b.matchScore - a.matchScore);

        return res.status(200).json({ success: true, matches });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
