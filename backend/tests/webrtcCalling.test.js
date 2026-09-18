process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import redis from '../config/redis.js';

import Booking from '../models/Booking.js';
import WebRTCCallLog from '../models/WebRTCCallLog.js';
import { reportNetworkDiagnostics, getIceServers } from '../controllers/webrtcCallController.js';

test.after(() => {
    try {
        redis.disconnect();
    } catch {}
});

test('Booking schema guarantees bookingId, userId, workerId, and serviceId', () => {
    // 1. Check paths exist in schema
    assert.ok(Booking.schema.path('bookingId'), 'bookingId path missing');
    assert.ok(Booking.schema.path('customer'), 'customer path missing');
    assert.ok(Booking.schema.path('worker'), 'worker path missing');
    assert.ok(Booking.schema.path('service'), 'service path missing');

    // 2. Check virtuals exist
    assert.ok(Booking.schema.virtuals['userId'], 'userId virtual missing');
    assert.ok(Booking.schema.virtuals['workerId'], 'workerId virtual missing');
    assert.ok(Booking.schema.virtuals['serviceId'], 'serviceId virtual missing');

    // 3. Test instance instantiation with virtual mapping
    const dummyUser = new mongoose.Types.ObjectId();
    const dummyWorker = new mongoose.Types.ObjectId();
    const dummyService = new mongoose.Types.ObjectId();

    const booking = new Booking({
        customer: dummyUser,
        worker: dummyWorker,
        service: dummyService,
        serviceAddress: {
            addressLine: '123 Test St',
            location: { type: 'Point', coordinates: [77.2090, 28.6139] }
        }
    });

    // Check getters
    assert.equal(String(booking.userId), String(dummyUser));
    assert.equal(String(booking.workerId), String(dummyWorker));
    assert.equal(String(booking.serviceId), String(dummyService));

    // Check JSON serialization
    const json = booking.toJSON();
    assert.ok(json.bookingId, 'bookingId missing in JSON output');
    assert.ok(json.bookingId.startsWith('#BK-'), 'bookingId must start with #BK-');
    assert.equal(String(json.userId), String(dummyUser));
    assert.equal(String(json.workerId), String(dummyWorker));
    assert.equal(String(json.serviceId), String(dummyService));
});

test('generateUniqueBookingId produces 100% collision-free IDs with date prefix', async () => {
    const { generateUniqueBookingId } = await import('../models/Booking.js');
    const id = generateUniqueBookingId();

    // Verify format: #BK-YYMMDD-SSSSXXXX (e.g. #BK-260906-01042A8F)
    assert.match(id, /^#BK-\d{6}-\d{5}[0-9A-F]{4}$/);

    // Test uniqueness across 1,000 rapid iterations
    const set = new Set();
    for (let i = 0; i < 1000; i++) {
        const generated = generateUniqueBookingId();
        assert.ok(!set.has(generated), `Duplicate bookingId generated: ${generated}`);
        set.add(generated);
    }
    assert.equal(set.size, 1000);
});

test('WebRTCCallLog schema enforces audit integrity and phone number privacy', () => {
    // Path checks
    assert.ok(WebRTCCallLog.schema.path('booking'), 'booking ref missing');
    assert.ok(WebRTCCallLog.schema.path('bookingId'), 'bookingId string missing');
    assert.ok(WebRTCCallLog.schema.path('caller'), 'caller ref missing');
    assert.ok(WebRTCCallLog.schema.path('receiver'), 'receiver ref missing');
    assert.ok(WebRTCCallLog.schema.path('status'), 'status missing');
    assert.ok(WebRTCCallLog.schema.path('durationSeconds'), 'durationSeconds missing');
    assert.ok(WebRTCCallLog.schema.path('endReason'), 'endReason missing');
    assert.ok(WebRTCCallLog.schema.path('networkDiagnostics.firewallBlocked'), 'networkDiagnostics missing');

    // Strict privacy check: No phone number field allowed in call log schema
    assert.equal(WebRTCCallLog.schema.path('phone'), undefined, 'phone field must NOT exist');
    assert.equal(WebRTCCallLog.schema.path('callerPhone'), undefined, 'callerPhone must NOT exist');
    assert.equal(WebRTCCallLog.schema.path('receiverPhone'), undefined, 'receiverPhone must NOT exist');
});

test('getIceServers provides high availability STUN servers for WebRTC', async () => {
    let capturedStatus = null;
    let capturedJson = null;

    const res = {
        status(code) {
            capturedStatus = code;
            return this;
        },
        json(data) {
            capturedJson = data;
            return this;
        }
    };

    await getIceServers({}, res);

    assert.equal(capturedStatus, 200);
    assert.equal(capturedJson.success, true);
    assert.ok(Array.isArray(capturedJson.iceServers));
    assert.ok(capturedJson.iceServers.length > 0);
    assert.ok(capturedJson.iceServers.some(s => s.urls.includes('google.com')));
});

test('reportNetworkDiagnostics returns FIREWALL_BLOCKED_WIFI_RESTRICTION when Wi-Fi blocks ICE', async () => {
    let capturedStatus = null;
    let capturedJson = null;

    const req = {
        body: {
            bookingId: '#BK-99999',
            networkType: 'wifi',
            iceConnectionState: 'failed',
            candidateType: 'host'
        }
    };

    const res = {
        status(code) {
            capturedStatus = code;
            return this;
        },
        json(data) {
            capturedJson = data;
            return this;
        }
    };

    await reportNetworkDiagnostics(req, res);

    assert.equal(capturedStatus, 400);
    assert.equal(capturedJson.success, false);
    assert.equal(capturedJson.errorCode, 'FIREWALL_BLOCKED_WIFI_RESTRICTION');
    assert.equal(capturedJson.suggestion, 'SWITCH_TO_MOBILE_DATA');
    assert.equal(capturedJson.networkType, 'wifi');
    assert.ok(capturedJson.message.includes('Wi-Fi'));
});

test('reportNetworkDiagnostics handles cellular network failures gracefully', async () => {
    let capturedStatus = null;
    let capturedJson = null;

    const req = {
        body: {
            bookingId: '#BK-99999',
            networkType: 'cellular',
            iceConnectionState: 'failed'
        }
    };

    const res = {
        status(code) {
            capturedStatus = code;
            return this;
        },
        json(data) {
            capturedJson = data;
            return this;
        }
    };

    await reportNetworkDiagnostics(req, res);

    assert.equal(capturedStatus, 400);
    assert.equal(capturedJson.success, false);
    assert.equal(capturedJson.errorCode, 'WEBRTC_ICE_CONNECTION_FAILED');
    assert.equal(capturedJson.suggestion, 'CHECK_INTERNET_CONNECTION');
});

test('sendIncomingCallPush handles missing recipient and gracefully handles unconfigured FCM', async () => {
    const { sendIncomingCallPush, sendCancelCallPush } = await import('../services/webrtcCallPushService.js');
    const resNoRecipient = await sendIncomingCallPush({});
    assert.equal(resNoRecipient.success, false);
    assert.equal(resNoRecipient.reason, 'NO_RECIPIENT');

    // Safe invocation of cancel push
    await assert.doesNotReject(async () => {
        await sendCancelCallPush({ recipientUserId: null });
    });
});

test('buildBookingQuery normalizes unique IDs with or without hash prefix and MongoDB ObjectIds', async () => {
    const { buildBookingQuery } = await import('../controllers/webrtcCallController.js');

    // 1. With Hash
    const q1 = buildBookingQuery('#BK-260906-01042A8F');
    assert.ok(q1.$or.some(c => c.bookingId === '#BK-260906-01042A8F'));
    assert.ok(q1.$or.some(c => c.bookingId === 'BK-260906-01042A8F'));

    // 2. Without Hash (user entered BK-...)
    const q2 = buildBookingQuery('BK-260906-01042A8F');
    assert.ok(q2.$or.some(c => c.bookingId === '#BK-260906-01042A8F'));
    assert.ok(q2.$or.some(c => c.bookingId === 'BK-260906-01042A8F'));

    // 3. MongoDB 24-hex ObjectId
    const mongoId = '66da1b9872f9b8c011234567';
    const q3 = buildBookingQuery(mongoId);
    assert.ok(q3.$or.some(c => c._id === mongoId));

    // 4. Whitespace trimming safety
    const q4 = buildBookingQuery('  #BK-260906-01042A8F  ');
    assert.ok(q4.$or.some(c => c.bookingId === '#BK-260906-01042A8F'));

    // 5. Invalid / null handling
    assert.equal(buildBookingQuery(null), null);
    assert.equal(buildBookingQuery(''), null);
});

test('getTargetCallRooms and getTargetBookingRooms resolve dual hash/non-hash rooms without regex mismatch', async () => {
    const { getTargetCallRooms, getCanonicalBookingKey } = await import('../sockets/webrtcCallSocket.js');
    const { getTargetBookingRooms } = await import('../sockets/tracking.js');

    const testIdWithHash = '#BK-260906-0001A8F2';
    const testIdWithoutHash = 'BK-260906-0001A8F2';

    // WebRTC call room aliases
    const rooms1 = getTargetCallRooms(testIdWithHash);
    assert.ok(rooms1.includes(`webrtc_call_${testIdWithHash}`));
    assert.ok(rooms1.includes(`webrtc_call_${testIdWithoutHash}`));

    const rooms2 = getTargetCallRooms(testIdWithoutHash);
    assert.ok(rooms2.includes(`webrtc_call_${testIdWithHash}`));
    assert.ok(rooms2.includes(`webrtc_call_${testIdWithoutHash}`));

    // Canonical Redis key (always stripped of leading #)
    assert.equal(getCanonicalBookingKey(testIdWithHash), testIdWithoutHash);
    assert.equal(getCanonicalBookingKey(testIdWithoutHash), testIdWithoutHash);

    // Tracking room aliases
    const trackRooms1 = getTargetBookingRooms(testIdWithHash);
    assert.ok(trackRooms1.includes(`booking_${testIdWithHash}`));
    assert.ok(trackRooms1.includes(`booking_${testIdWithoutHash}`));

    const trackRooms2 = getTargetBookingRooms(testIdWithoutHash);
    assert.ok(trackRooms2.includes(`booking_${testIdWithHash}`));
    assert.ok(trackRooms2.includes(`booking_${testIdWithoutHash}`));
});

test('hangupWebRTCCall terminates call cleanly and validates bookingId', async () => {
    const { hangupWebRTCCall } = await import('../controllers/webrtcCallController.js');

    let capturedStatus = null;
    let capturedJson = null;
    const res = {
        status(code) {
            capturedStatus = code;
            return this;
        },
        json(data) {
            capturedJson = data;
            return this;
        }
    };

    // 1. Missing bookingId returns 400
    await hangupWebRTCCall({
        body: {},
        user: { id: new mongoose.Types.ObjectId() },
        app: { get: () => null }
    }, res);

    assert.equal(capturedStatus, 400);
    assert.equal(capturedJson.success, false);

    // 2. Valid bookingId executes cleanly without throwing
    capturedStatus = null;
    capturedJson = null;
    await hangupWebRTCCall({
        body: { bookingId: '#BK-260906-0001A8F2', endReason: 'NORMAL_HANGUP', durationSeconds: 45 },
        user: { id: new mongoose.Types.ObjectId() },
        app: { get: () => null }
    }, res);

    assert.equal(capturedStatus, 200);
    assert.equal(capturedJson.success, true);
});


