import Cooperative from '../models/Cooperative.js';
import CooperativeSociety from '../models/CooperativeSociety.js';
import User from '../models/User.js';
import { fail, ok, isObjectId } from '../utils/http.js';
import { syncWorkerToRedis } from '../utils/homeCache.js';

const getOrCreateFederation = async () => {
    let doc = await Cooperative.findOne({ active: true });
    if (!doc) doc = await Cooperative.create({});
    return doc;
};

// 0. Get Public Federations (for signup)
export const getPublicFederations = async (req, res) => {
    try {
        const federations = await Cooperative.find({ status: 'approved' })
            .select('name federationName state district logo');
        return ok(res, { data: federations });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 1. Get Federation Level Info
export const getCooperativeInfo = async (_req, res) => {
    try {
        const info = await getOrCreateFederation();
        const totalSocieties = await CooperativeSociety.countDocuments({ active: true });
        const totalWorkers = await User.countDocuments({ role: 'worker' });
        return ok(res, {
            data: {
                ...info.toObject(),
                totalSocieties,
                totalAffiliatedWorkers: totalWorkers,
            }
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 2. Get Logged-in Worker's Membership Details (Federation + Primary Society)
export const getMyMembership = async (req, res) => {
    try {
        if (req.user.role !== 'worker') return fail(res, 403, 'FORBIDDEN', 'Worker role required');
        const federation = await getOrCreateFederation();
        const worker = await User.findById(req.user.id)
            .select('name email phone isVerified createdAt workerProfile')
            .populate('workerProfile.society');

        const society = worker?.workerProfile?.society || null;

        return ok(res, {
            data: {
                member: Boolean(worker),
                verified: Boolean(worker?.isVerified),
                joinedAt: worker?.createdAt,
                societyMemberId: worker?.workerProfile?.societyMemberId || null,
                society: society ? {
                    _id: society._id,
                    name: society.name,
                    registrationNumber: society.registrationNumber,
                    district: society.district,
                    state: society.state,
                    wardOrArea: society.wardOrArea,
                    contactPhone: society.contactPhone,
                    presidentName: society.presidentName,
                    fairWageComplianceScore: society.fairWageComplianceScore,
                } : null,
                federation: {
                    name: federation.name,
                    federationName: federation.federationName,
                    registrationNumber: federation.registrationNumber,
                    fairWagePolicy: federation.fairWagePolicy,
                    minimumWageFloor: federation.minimumWageFloor,
                    welfareContributionRate: federation.welfareContributionRate,
                    insuranceEnabled: federation.insuranceEnabled,
                },
            },
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 3. List Primary Cooperative Societies
export const listSocieties = async (req, res) => {
    try {
        const { state, district, active } = req.query;
        const query = {};
        if (state) query.state = new RegExp(state, 'i');
        if (district) query.district = new RegExp(district, 'i');
        if (active !== undefined) query.active = active === 'true';

        const societies = await CooperativeSociety.find(query).sort({ name: 1 });
        return ok(res, { data: societies, total: societies.length });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 4. Get Primary Society by ID
export const getSocietyById = async (req, res) => {
    try {
        const { id } = req.params;
        if (!isObjectId(id)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid society id');

        const society = await CooperativeSociety.findById(id).populate('federation');
        if (!society) return fail(res, 404, 'NOT_FOUND', 'Cooperative Society not found');

        const members = await User.find({
            role: 'worker',
            'workerProfile.society': society._id
        }).select('name phone isVerified workerProfile.skills workerProfile.rating workerProfile.totalJobs workerProfile.societyMemberId');

        return ok(res, { data: { society, members, memberCount: members.length } });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 5. Admin: Get Federation Info
export const adminGetCooperative = async (_req, res) => {
    try {
        return ok(res, { data: await getOrCreateFederation() });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 6. Admin: Update Federation Info & Wage Floors
export const adminUpdateCooperative = async (req, res) => {
    try {
        const info = await getOrCreateFederation();
        const fields = [
            'name', 'federationName', 'registrationNumber', 'state', 'district', 'commissionRate',
            'welfareContributionRate', 'insuranceEnabled', 'fairWagePolicy', 'active',
            'emergencySurchargePercent', 'minimumWageFloor'
        ];
        for (const key of fields) {
            if (req.body[key] !== undefined) info[key] = req.body[key];
        }
        await info.save();
        return ok(res, { data: info });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 7. Admin: Create Primary Cooperative Society
export const adminCreateSociety = async (req, res) => {
    try {
        const {
            name, registrationNumber, state, district, wardOrArea,
            officeAddress, contactPhone, presidentName, secretaryName
        } = req.body;

        if (!name || !registrationNumber || !state || !district) {
            return fail(res, 400, 'VALIDATION_ERROR', 'name, registrationNumber, state and district are required');
        }

        const existing = await CooperativeSociety.findOne({ registrationNumber });
        if (existing) {
            return fail(res, 409, 'CONFLICT', 'Society registration number already exists');
        }

        const federation = await getOrCreateFederation();

        const society = await CooperativeSociety.create({
            name,
            registrationNumber,
            federation: federation._id,
            state,
            district,
            wardOrArea: wardOrArea || null,
            officeAddress: officeAddress || null,
            contactPhone: contactPhone || null,
            presidentName: presidentName || null,
            secretaryName: secretaryName || null,
            active: true
        });

        return ok(res, { data: society, message: 'Cooperative Society created successfully' }, 201);
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 8. Admin: Update Primary Cooperative Society
export const adminUpdateSociety = async (req, res) => {
    try {
        const { id } = req.params;
        if (!isObjectId(id)) return fail(res, 400, 'VALIDATION_ERROR', 'Invalid society id');

        const society = await CooperativeSociety.findByIdAndUpdate(id, { $set: req.body }, { returnDocument: 'after' });
        if (!society) return fail(res, 404, 'NOT_FOUND', 'Cooperative Society not found');

        return ok(res, { data: society, message: 'Cooperative Society updated successfully' });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 9. Admin: Assign Worker to a Cooperative Society
export const adminAssignWorkerToSociety = async (req, res) => {
    try {
        const { workerId, societyId, societyMemberId } = req.body;
        if (!isObjectId(workerId) || !isObjectId(societyId)) {
            return fail(res, 400, 'VALIDATION_ERROR', 'Valid workerId and societyId required');
        }

        const society = await CooperativeSociety.findById(societyId);
        if (!society) return fail(res, 404, 'NOT_FOUND', 'Cooperative Society not found');

        const worker = await User.findById(workerId);
        if (!worker || worker.role !== 'worker') {
            return fail(res, 404, 'NOT_FOUND', 'Worker not found');
        }

        if (!worker.workerProfile) worker.workerProfile = {};
        worker.workerProfile.society = societyId;
        if (societyMemberId) {
            worker.workerProfile.societyMemberId = societyMemberId;
        } else if (!worker.workerProfile.societyMemberId) {
            worker.workerProfile.societyMemberId = `MEM-${society.district.toUpperCase().slice(0, 3)}-${Math.floor(1000 + Math.random() * 9000)}`;
        }

        await worker.save();

        // Update society member count
        const count = await User.countDocuments({ role: 'worker', 'workerProfile.society': societyId });
        society.activeMembersCount = count;
        await society.save();

        // Instantly synchronize worker profile to Redis
        await syncWorkerToRedis(worker._id, worker);

        const io = req.app?.get('io');
        if (io) {
            io.emit('worker:updated', { worker });
        }

        return ok(res, {
            data: {
                workerId: worker._id,
                societyId: society._id,
                societyName: society.name,
                societyMemberId: worker.workerProfile.societyMemberId,
            },
            message: 'Worker assigned to Cooperative Society successfully'
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 10. Admin: List Cooperative Members
export const adminCooperativeMembers = async (req, res) => {
    try {
        const { societyId } = req.query;
        const query = { role: 'worker' };
        if (societyId && isObjectId(societyId)) {
            query['workerProfile.society'] = societyId;
        }

        const workers = await User.find(query)
            .select('name email phone isVerified createdAt workerProfile.skills workerProfile.rating workerProfile.society workerProfile.societyMemberId')
            .populate('workerProfile.society', 'name registrationNumber district state');

        return ok(res, { data: workers, total: workers.length });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};

// 11. Worker: Request to join a Cooperative Society
export const workerJoinSociety = async (req, res) => {
    try {
        if (req.user.role !== 'worker') return fail(res, 403, 'FORBIDDEN', 'Worker role required');
        const { societyId } = req.body;
        
        if (!isObjectId(societyId)) {
            return fail(res, 400, 'VALIDATION_ERROR', 'Valid societyId required');
        }

        const society = await CooperativeSociety.findById(societyId);
        if (!society) return fail(res, 404, 'NOT_FOUND', 'Cooperative Society not found');

        const worker = await User.findById(req.user.id);
        if (!worker) return fail(res, 404, 'NOT_FOUND', 'Worker not found');

        if (!worker.workerProfile) worker.workerProfile = {};
        
        worker.workerProfile.society = societyId;
        if (!worker.workerProfile.societyMemberId) {
            worker.workerProfile.societyMemberId = `MEM-${society.district.toUpperCase().slice(0, 3)}-${Math.floor(1000 + Math.random() * 9000)}`;
        }

        await worker.save();

        const count = await User.countDocuments({ role: 'worker', 'workerProfile.society': societyId });
        society.activeMembersCount = count;
        await society.save();

        return ok(res, {
            data: {
                societyId: society._id,
                societyName: society.name,
                societyMemberId: worker.workerProfile.societyMemberId,
            },
            message: 'Successfully affiliated with Cooperative Society'
        });
    } catch (error) {
        return fail(res, 500, 'INTERNAL_ERROR', error.message);
    }
};
