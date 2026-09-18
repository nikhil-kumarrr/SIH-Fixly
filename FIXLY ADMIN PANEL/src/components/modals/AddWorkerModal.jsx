import React, { useState } from 'react';
import Modal from '../common/Modal';
import { useApp } from '../../context/AppContext';
import { OFFICIAL_CATEGORIES, getMergedCategories } from '../../data/services';
import StateDistrictSelect from '../common/StateDistrictSelect';

export default function AddWorkerModal({ isOpen, onClose }) {
  const { addWorker, services } = useApp();

  const [formData, setFormData] = useState({
    name: '',
    phone: '',
    email: '',
    address: '',
    state: 'Delhi',
    district: 'South Delhi',
    city: 'South Delhi',
    service: 'Electrician',
    skills: '',
    experience: '5 Years',
    certifications: '',
    availability: 'Available',
    rate: 200,
    serviceRadiusKm: 15,
    idProof: 'Aadhaar Card',
    avatar: '',
  });

  const [isCustomTrade, setIsCustomTrade] = useState(false);
  const [customTrade, setCustomTrade] = useState('');
  const [errors, setErrors] = useState({});

  const tradeOptions = React.useMemo(() => {
    return getMergedCategories(services);
  }, [services]);

  const validate = () => {
    const errs = {};
    if (!formData.name.trim()) errs.name = 'Full name is required';
    if (!formData.phone.trim()) errs.phone = 'Valid phone number is required';
    if (!formData.skills.trim()) errs.skills = 'Please enter at least 1 skill';
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!validate()) return;

    const effectiveTrade = isCustomTrade ? customTrade.trim() : formData.service?.trim();

    try {
      await addWorker({
        name: formData.name,
        email: formData.email || `${formData.name.toLowerCase().replace(/\s+/g, '')}@gigworker.com`,
        phone: formData.phone,
        password: 'WorkerPass123!',
        category: effectiveTrade || 'Electrician',
        rate: Number(formData.rate) || 200,
        hourlyRate: Number(formData.rate) || 200,
        serviceRadiusKm: Number(formData.serviceRadiusKm) || 15,
        experienceYears: parseInt(formData.experience.replace(/\D/g, ''), 10) || 1,
        bio: `Professional ${effectiveTrade || 'Electrician'} worker in ${formData.district || formData.city || 'India'}`,
        skills: formData.skills ? formData.skills.split(',').map((s) => s.trim()) : ['General Service'],
        state: formData.state,
        district: formData.district,
        city: formData.district || formData.city,
        address: formData.address,
      });
      onClose();
    } catch (err) {
      console.error('Failed to add worker modal:', err);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Onboard New Cooperative Worker"
      subtitle="Register verified gig worker with insurance enrollment and skill verification"
      maxWidth="620px"
      footer={
        <>
          <button
            onClick={onClose}
            style={{
              padding: '8px 16px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              color: '#475569',
              fontSize: '13px',
              fontWeight: '600',
            }}
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            style={{
              padding: '8px 20px',
              borderRadius: '8px',
              backgroundColor: 'var(--primary-brand)',
              color: '#ffffff',
              fontSize: '13px',
              fontWeight: '600',
            }}
          >
            Register & Activate Member
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Full Name *
            </label>
            <input
              type="text"
              placeholder="e.g. Ramesh Kumar"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: `1px solid ${errors.name ? '#ef4444' : '#cbd5e1'}`,
                fontSize: '13px',
              }}
            />
            {errors.name && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.name}</span>}
          </div>

          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Phone Number *
            </label>
            <input
              type="text"
              placeholder="+91 98765 00000"
              value={formData.phone}
              onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: `1px solid ${errors.phone ? '#ef4444' : '#cbd5e1'}`,
                fontSize: '13px',
              }}
            />
            {errors.phone && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.phone}</span>}
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
              <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155' }}>
                Primary Service Trade *
              </label>
              {isCustomTrade ? (
                <button
                  type="button"
                  onClick={() => {
                    setIsCustomTrade(false);
                    setCustomTrade('');
                  }}
                  style={{ background: 'none', border: 'none', color: '#0284c7', fontSize: '11px', cursor: 'pointer', fontWeight: 600 }}
                >
                  ← Select Existing
                </button>
              ) : null}
            </div>

            {isCustomTrade ? (
              <input
                type="text"
                placeholder="Type new service/trade (e.g. Appliance Repair)..."
                value={customTrade}
                onChange={(e) => setCustomTrade(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  border: '1px solid #0284c7',
                  fontSize: '13px',
                  backgroundColor: '#f0f9ff',
                }}
              />
            ) : (
              <select
                value={formData.service}
                onChange={(e) => {
                  if (e.target.value === '__custom__') {
                    setIsCustomTrade(true);
                  } else {
                    setFormData({ ...formData, service: e.target.value });
                  }
                }}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  border: '1px solid #cbd5e1',
                  fontSize: '13px',
                  backgroundColor: '#ffffff',
                }}
              >
                {tradeOptions.map((trade) => (
                  <option key={trade} value={trade}>{trade}</option>
                ))}
                <option value="__custom__" style={{ fontWeight: '700', color: '#0284c7' }}>+ Create New Service / Trade...</option>
              </select>
            )}
          </div>

          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Experience Level
            </label>
            <input
              type="text"
              placeholder="e.g. 6 Years"
              value={formData.experience}
              onChange={(e) => setFormData({ ...formData, experience: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: '1px solid #cbd5e1',
                fontSize: '13px',
              }}
            />
          </div>
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Specific Skills (comma separated) *
          </label>
          <input
            type="text"
            placeholder="e.g. Pipe fitting, Tap repair, Drainage unclogging"
            value={formData.skills}
            onChange={(e) => setFormData({ ...formData, skills: e.target.value })}
            style={{
              width: '100%',
              padding: '8px 12px',
              borderRadius: '8px',
              border: `1px solid ${errors.skills ? '#ef4444' : '#cbd5e1'}`,
              fontSize: '13px',
            }}
          />
          {errors.skills && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.skills}</span>}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Base Service Rate (₹ / booking)
            </label>
            <input
              type="number"
              min="50"
              value={formData.rate}
              onChange={(e) => setFormData({ ...formData, rate: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: '1px solid #cbd5e1',
                fontSize: '13px',
              }}
            />
          </div>

          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Service Radius (km)
            </label>
            <input
              type="number"
              min="1"
              max="100"
              value={formData.serviceRadiusKm}
              onChange={(e) => setFormData({ ...formData, serviceRadiusKm: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: '1px solid #cbd5e1',
                fontSize: '13px',
              }}
            />
          </div>
        </div>

        <div>
          <StateDistrictSelect
            selectedState={formData.state}
            selectedDistrict={formData.district}
            onStateChange={(st) => setFormData({ ...formData, state: st, district: '', city: '' })}
            onDistrictChange={(dist) => setFormData({ ...formData, district: dist, city: dist })}
            stateLabel="Worker Home State *"
            districtLabel="Worker Home District *"
          />
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Street Address / Local Area (optional)
          </label>
          <input
            type="text"
            placeholder="e.g. Sector 62, Indirapuram"
            value={formData.address}
            onChange={(e) => setFormData({ ...formData, address: e.target.value })}
            style={{
              width: '100%',
              padding: '8px 12px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '13px',
            }}
          />
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Certifications / Trade Guild Credentials
          </label>
          <input
            type="text"
            placeholder="e.g. Skill India Level 2, ITI Certificate"
            value={formData.certifications}
            onChange={(e) => setFormData({ ...formData, certifications: e.target.value })}
            style={{
              width: '100%',
              padding: '8px 12px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '13px',
            }}
          />
        </div>
      </form>
    </Modal>
  );
}
