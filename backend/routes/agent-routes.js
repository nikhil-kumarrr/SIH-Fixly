import express from 'express';
import { protect } from '../middleware/authMiddleware.js';
import { chatWithFlexiAgent } from '../controllers/agentController.js';

const router = express.Router();

// POST /api/agent/chat (and /api/ai/agent/chat)
router.post('/chat', protect, chatWithFlexiAgent);

export default router;
