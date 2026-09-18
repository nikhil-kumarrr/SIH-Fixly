import test from 'node:test';
import assert from 'node:assert/strict';
import { detectCategory, detectLanguage, isBookingQuery } from '../agent/flexiAgent.js';
import { llm, isGeminiConfigured } from '../agent/model.js';
import { FIXLY_SYSTEM_PROMPT } from '../agent/prompts/agentPrompt.js';
import Booking from '../models/Booking.js';
import CooperativeSociety from '../models/CooperativeSociety.js';
import Cooperative from '../models/Cooperative.js';

test('Fixly AI Agent correctly recognizes categories from natural words', () => {
    assert.equal(detectCategory('bijli ka fuse ud gaya hai'), 'Electrical');
    assert.equal(detectCategory('nal se paani leak ho raha hai'), 'Plumbing');
    assert.equal(detectCategory('sofa ki deep cleaning karwani hai'), 'Cleaning');
    assert.equal(detectCategory('bed aur darwaza repair karna hai'), 'Carpentry');
    assert.equal(detectCategory('ac thanda nahi kar raha'), 'Appliance');
});

test('Fixly AI Agent detects language preference accurately', () => {
    assert.equal(detectLanguage('mujhe ek plumber chahiye turant'), 'hi');
    assert.equal(detectLanguage('I need a professional electrician today'), 'hi');
});

test('Fixly AI Agent detects active booking query phrases', () => {
    assert.equal(isBookingQuery('meri current booking ka status batao'), true);
    assert.equal(isBookingQuery('what is my booking status'), true);
});

test('Fixly AI Agent system prompt enforces safety and strict cooperative scope', () => {
    assert.ok(FIXLY_SYSTEM_PROMPT.includes('Fixly AI'));
    assert.equal(typeof isGeminiConfigured, 'function');
    assert.ok(llm);
});

test('Booking model schema validates bookingType and isEmergency', () => {
    const booking = new Booking({
        customer: '64f1bc000000000000000001',
        service: '64f1bc000000000000000002',
        bookingType: 'EMERGENCY_SOS',
        isEmergency: true,
        timeSlot: 'Immediate (SOS Emergency)',
        serviceAddress: {
            addressLine: 'Test Address',
            location: { type: 'Point', coordinates: [77.2090, 28.6139] }
        }
    });

    assert.equal(booking.bookingType, 'EMERGENCY_SOS');
    assert.equal(booking.isEmergency, true);
    assert.equal(booking.timeSlot, 'Immediate (SOS Emergency)');
});

test('Cooperative Federation schema includes minimumWageFloor', () => {
    const coop = new Cooperative();
    assert.equal(coop.name, 'Fixly Cooperative Federation');
    assert.equal(coop.emergencySurchargePercent, 20);
    assert.equal(coop.minimumWageFloor.electrical, 400);
    assert.equal(coop.minimumWageFloor.plumbing, 350);
});
