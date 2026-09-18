import express from 'express';
import {
    initiateWebRTCCall,
    acceptWebRTCCall,
    getIceServers,
    reportNetworkDiagnostics,
    getCallStatus,
    getCallHistory,
    hangupWebRTCCall
} from '../controllers/webrtcCallController.js';
import { protect } from '../middleware/authMiddleware.js';

const router = express.Router();

/**
 * WebRTC Masked Audio Calling Endpoints
 * Base Path: /api/webrtc
 */

// 1. Initiate Audio Call for a Booking (returns masked profiles & channel)
router.post('/call/initiate', protect, initiateWebRTCCall);

// 2. Accept Audio Call (HTTP REST Fallback for 100% reliability)
router.post('/call/accept', protect, acceptWebRTCCall);

// 3. Terminate / Hangup Audio Call (Ensures 100% two-way termination)
router.post('/call/hangup', protect, hangupWebRTCCall);

// 3. Fetch ICE Servers (STUN/TURN) Configuration
router.get('/config/ice-servers', protect, getIceServers);

// 4. Network Diagnostics & Wi-Fi Firewall Issue Reporting
router.post('/call/network-diagnostics', protect, reportNetworkDiagnostics);

// 5. Check Real-Time Call Status in Redis
router.get('/call/status/:bookingId', protect, getCallStatus);

// 6. User Call History (Strictly masked, no phone numbers)
router.get('/call/history', protect, getCallHistory);

export default router;

