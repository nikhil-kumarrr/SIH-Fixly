import test from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import dotenv from 'dotenv';
dotenv.config();

import redis from '../config/redis.js';
import { processFlexiAgentMessage } from '../agent/index.js';

test('AI Agent Interactive Conversation Flow (Progressive Slot-Filling & Availability Guardrails)', async (t) => {
    console.log('\n========================================================');
    console.log('🤖 Fixly "Hey Fixly" Multi-Agent State Machine Test');
    console.log('========================================================');

    if (mongoose.connection.readyState === 0) {
        try {
            await mongoose.connect(process.env.MONGO_URI);
            console.log('✅ MongoDB connected for test suite');
        } catch (err) {
            console.warn('⚠️ MongoDB connection error:', err.message);
        }
    }

    t.after(async () => {
        if (mongoose.connection.readyState === 1) {
            await mongoose.disconnect();
        }
        try {
            await redis.quit();
        } catch (e) {}
    });

    const dummyUserId = '6a9d23aef9e7bb2f29d0f3dc';
    try {
        await redis.del(`fixly:session:${dummyUserId}`);
        await redis.del(`fixly:history:${dummyUserId}`);
        await redis.del(`flexi:session:${dummyUserId}`);
        await redis.del(`flexi:history:${dummyUserId}`);
    } catch (e) {}

    // TURN 1: Initial speech requesting electrician
    await t.test('Turn 1: Category detected, prompts booking type', async () => {
        const input = 'नमस्ते फिक्सली, मुझे बिजली का काम है स्विच बोर्ड खराब हो गया है';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res1 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res1.reply}"`);
        console.log(`⚡ [Action]: ${res1.action}`);
        console.log(`📊 [Extracted Category]: ${res1.state.category}`);

        assert.equal(res1.state.category, 'Electrical');
        assert.ok(res1.reply.length > 10);
        assert.equal(res1.action, 'PROMPT_BOOKING_TYPE');
    });

    // TURN 2: Booking Type Selected (Standard) -> Online Workers Check
    await t.test('Turn 2: Standard booking selected -> Online workers returned', async () => {
        const input = 'Standard booking chahiye';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res2 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: { category: 'Electrical', step: 'AWAITING_BOOKING_TYPE' },
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res2.reply}"`);
        console.log(`⚡ [Action]: ${res2.action}`);
        console.log(`👷 [Workers Available]: ${res2.workers?.map(w => w.name)}`);

        assert.equal(res2.action, 'PROMPT_WORKER_SELECTION');
        assert.ok(res2.workers && res2.workers.length > 0);
        assert.ok(res2.workers.some(w => w.name.includes('Vaibhav')));
    });

    // TURN 3: Worker Selection -> Cost Estimate & Cooperative Fair Wage Policy Card
    await t.test('Turn 3: Select Worker -> Price Estimate & Cooperative Policy Card', async () => {
        const input = 'Vaibhav Jain ko select karo';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res3 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {
                category: 'Electrical',
                bookingType: 'STANDARD',
                step: 'AWAITING_WORKER_SELECTION'
            },
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res3.reply}"`);
        console.log(`⚡ [Action]: ${res3.action}`);
        console.log(`💰 [Estimate]:`, res3.estimate);
        console.log(`🛡️ [Policy]:`, res3.policy);

        assert.equal(res3.action, 'PROMPT_CONFIRMATION');
        assert.ok(res3.estimate);
        assert.ok(res3.estimate.totalAmount > 0);
        assert.ok(res3.policy);
    });

    // TURN 4: Confirm Booking -> DB creation with status PENDING
    await t.test('Turn 4: Confirm Booking -> DB creation with status PENDING', async () => {
        const input = 'Haan booking confirm kardo';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res4 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {
                category: 'Electrical',
                bookingType: 'STANDARD',
                workerId: '6a9d255bf09b371a043e8b77',
                workerName: 'Vaibhav Jain',
                workerRate: 200,
                step: 'AWAITING_CONFIRMATION'
            },
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res4.reply}"`);
        console.log(`⚡ [Action]: ${res4.action}`);
        console.log(`🎉 [Created Booking]:`, res4.booking?.bookingId, 'Status:', res4.booking?.status);

        assert.equal(res4.action, 'BOOKING_CREATED');
        assert.ok(res4.booking);
        assert.equal(res4.booking.status, 'PENDING');
        assert.equal(String(res4.booking.worker), '6a9d255bf09b371a043e8b77');
    });

    // TURN 5: Strict Zero Workers Guardrail (Painting Category)
    await t.test('Turn 5: Strict Zero Workers Guardrail blocks booking creation', async () => {
        const input = 'Standard booking kardo';
        console.log(`\n🗣️ [User Voice Input (Painting)]: "${input}"`);

        const res5 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: { category: 'Painting', step: 'AWAITING_BOOKING_TYPE' },
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res5.reply}"`);
        console.log(`⚡ [Action]: ${res5.action}`);

        assert.ok(res5.action === 'CATEGORY_NOT_SUPPORTED' || res5.action === 'NO_WORKERS_AVAILABLE');
        assert.ok(res5.workers === null || res5.workers.length === 0);
    });

    // TURN 6: Off-topic Guardrail rejection
    await t.test('Turn 6: Off-topic Guardrail Rejection', async () => {
        const input = 'आज का क्रिकेट मैच का स्कोर क्या है?';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res6 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res6.reply}"`);
        console.log(`⚡ [Action]: ${res6.action}`);

        assert.equal(res6.action, 'OFF_TOPIC_GUARD');
        assert.ok(res6.reply.includes('माफ़ कीजिए') || res6.reply.includes('Fixly'));
    });

    // TURN 7: Customer queries active booking status
    await t.test('Turn 7: Customer queries active booking status', async () => {
        const input = 'मेरी बुकिंग का स्टेटस बताओ';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res7 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res7.reply}"`);
        console.log(`⚡ [Action]: ${res7.action}`);

        assert.ok(res7.action === 'BOOKING_STATUS' || res7.action === 'NO_BOOKINGS');
    });

    // TURN 8: Strict Identity & Developer verification
    await t.test('Turn 8: Strict Identity check (developed by Vaibhav Jain)', async () => {
        const input = 'Who created you and what are you?';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res8 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'en',
        });

        console.log(`🤖 [Agent Reply]: "${res8.reply}"`);
        console.log(`⚡ [Action]: ${res8.action}`);

        assert.equal(res8.action, 'IDENTITY_INFO');
        assert.ok(res8.reply.includes('Vaibhav Jain'));
        assert.ok(res8.reply.includes('Fixly'));
    });

    // TURN 9: Emergency SOS Fast-Track Flow
    await t.test('Turn 9: Emergency SOS Fast-Track Flow', async () => {
        const input = 'Emergency plumber chahiye turant nal toot gaya hai';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res9 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res9.reply}"`);
        console.log(`⚡ [Action]: ${res9.action}`);
        console.log(`🚨 [Is Emergency]: ${res9.state.isEmergency}`);
        console.log(`👷 [Auto-Assigned Worker]: ${res9.state.workerName}`);

        assert.equal(res9.state.category, 'Plumbing');
        assert.equal(res9.state.isEmergency, true);
        assert.equal(res9.state.bookingType, 'EMERGENCY_SOS');
        assert.ok(res9.action === 'PROMPT_CONFIRMATION' || res9.action === 'BOOKING_CREATED');
        assert.ok(res9.state.workerName);
    });

    // TURN 10: Scheduled Booking Time Extraction
    await t.test('Turn 10: Scheduled Booking with explicit date & time', async () => {
        const input = 'Kal subah 10 baje electrician schedule kardo';
        console.log(`\n🗣️ [User Voice Input]: "${input}"`);

        const res10 = await processFlexiAgentMessage({
            userId: dummyUserId,
            message: input,
            conversationState: {},
            explicitLanguage: 'hi',
        });

        console.log(`🤖 [Agent Reply]: "${res10.reply}"`);
        console.log(`⚡ [Action]: ${res10.action}`);
        console.log(`📅 [Scheduled Time]: ${res10.state.scheduledTime}`);

        assert.equal(res10.state.category, 'Electrical');
        assert.equal(res10.state.bookingType, 'SCHEDULED');
        assert.ok(res10.state.scheduledTime);
    });

    console.log('\n========================================================');
    console.log('✅ ALL PROGRESSIVE MULTI-AGENT STEPS VERIFIED!');
    console.log('========================================================\n');
});
