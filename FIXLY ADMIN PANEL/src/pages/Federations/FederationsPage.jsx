import React, { useState, useEffect } from 'react';
import { useApp } from '../../context/AppContext';
import { api } from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { Building2, Search, Eye, CheckCircle, XCircle, Plus, RefreshCw, EyeOff, Copy, LogIn, RotateCcw } from 'lucide-react';
import { Link } from 'react-router-dom';
import StateDistrictSelect from '../../components/common/StateDistrictSelect';

const emptyForm = () => ({
  name: '',
  federationName: '',
  email: '',
  password: '',
  phone: '',
  state: '',
  district: '',
  registrationNumber: '',
});

const generatePassword = () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
  let out = '';
  for (let i = 0; i < 12; i += 1) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
};

const fieldStyle = {
  width: '100%',
  padding: '10px 12px',
  borderRadius: 10,
  border: '1px solid #e2e8f0',
  fontSize: 14,
  outline: 'none',
};

const labelStyle = {
  display: 'block',
  fontSize: 13,
  fontWeight: 600,
  color: '#334155',
  marginBottom: 6,
};

export default function FederationsPage() {
  const { adminRole } = useApp();
  const { showToast } = useToast();
  const [federations, setFederations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filterState, setFilterState] = useState('');
  const [filterDistrict, setFilterDistrict] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [form, setForm] = useState(emptyForm());
  const [saving, setSaving] = useState(false);
  const [showPassword, setShowPassword] = useState(true);

  const fetchFederations = async () => {
    try {
      setLoading(true);
      const res = await api.getAllFederations();
      if (res.success) {
        setFederations(res.data);
      }
    } catch (err) {
      showToast('error', 'Failed to fetch federations');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchFederations();
  }, []);

  const handleApprove = async (id) => {
    try {
      const res = await api.approveFederation(id);
      if (res.success) {
        showToast('success', 'Federation approved successfully');
        fetchFederations();
      }
    } catch (err) {
      showToast('error', 'Failed to approve federation');
    }
  };

  const handleSuspend = async (id) => {
    try {
      const res = await api.suspendFederation(id);
      if (res.success) {
        showToast('success', 'Federation suspended successfully');
        fetchFederations();
      }
    } catch (err) {
      showToast('error', 'Failed to suspend federation');
    }
  };

  const handleLoginAs = async (federation) => {
    try {
      const res = await api.impersonateFederation(federation._id);
      if (!res.success || !res.token) {
        showToast('error', res.message || 'Federation login failed');
        return;
      }
      const payload = encodeURIComponent(
        btoa(JSON.stringify({ token: res.token, user: res.user }))
      );
      const opened = window.open(`/impersonate#${payload}`, '_blank', 'noopener,noreferrer');
      if (!opened) {
        showToast('error', 'Popup blocked — allow popups for this site');
        return;
      }
      showToast('success', `Opened ${federation.name || 'federation'} panel`);
    } catch (err) {
      showToast('error', err.response?.data?.message || err.message || 'Federation login failed');
    }
  };

  const openCreateModal = () => {
    setForm({ ...emptyForm(), password: generatePassword() });
    setShowPassword(true);
    setShowModal(true);
  };

  const handleCreate = async (e) => {
    e.preventDefault();
    if (!form.name.trim() || !form.email.trim() || !form.password || !form.state.trim() || !form.district.trim()) {
      showToast('error', 'Name, email, password, state, and district are required');
      return;
    }
    try {
      setSaving(true);
      const res = await api.createFederation({
        name: form.name.trim(),
        federationName: form.federationName.trim() || form.name.trim(),
        email: form.email.trim(),
        password: form.password,
        phone: form.phone.trim() || undefined,
        state: form.state.trim(),
        district: form.district.trim(),
        registrationNumber: form.registrationNumber.trim() || undefined,
      });
      if (res.success) {
        showToast('success', `Federation created. Login: ${form.email.trim()}`);
        setShowModal(false);
        setForm(emptyForm());
        fetchFederations();
      } else {
        showToast('error', res.message || 'Failed to create federation');
      }
    } catch (err) {
      showToast('error', err.response?.data?.message || err.message || 'Failed to create federation');
    } finally {
      setSaving(false);
    }
  };

  if (adminRole !== 'super_admin') {
    return (
      <div style={{ padding: '32px', textAlign: 'center' }}>
        <h2>Unauthorized</h2>
        <p>You do not have permission to view this page.</p>
      </div>
    );
  }

  const filtered = federations.filter((f) => {
    const s = search.toLowerCase().trim();
    const matchesSearch =
      !s ||
      (f.name || '').toLowerCase().includes(s) ||
      (f.email || '').toLowerCase().includes(s) ||
      (f.registrationNumber || '').toLowerCase().includes(s) ||
      (f.state || '').toLowerCase().includes(s) ||
      (f.district || '').toLowerCase().includes(s);
    const matchesState = !filterState || (f.state || '').toLowerCase() === filterState.toLowerCase();
    const matchesDistrict = !filterDistrict || (f.district || '').toLowerCase() === filterDistrict.toLowerCase();
    return matchesSearch && matchesState && matchesDistrict;
  });

  return (
    <div style={{ padding: '0 32px 32px', animation: 'fadeIn 0.2s ease' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24, gap: 16, flexWrap: 'wrap' }}>
        <div>
          <h2 style={{ fontSize: 24, fontWeight: 700, color: '#111827', display: 'flex', alignItems: 'center', gap: 10 }}>
            <Building2 size={26} color="var(--primary-brand)" /> Federation Management
          </h2>
          <p style={{ fontSize: 14, color: '#64748b', marginTop: 4 }}>
            Create federations with login email/password. Hierarchy: super admin → federation → workers.
          </p>
        </div>
        <button
          type="button"
          onClick={openCreateModal}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            padding: '10px 18px',
            background: '#2563EB',
            color: '#fff',
            border: 'none',
            borderRadius: 10,
            fontWeight: 700,
            fontSize: 14,
            cursor: 'pointer',
            minHeight: 44,
          }}
        >
          <Plus size={18} />
          Add Federation
        </button>
      </div>

      <div style={{ background: '#fff', borderRadius: 16, padding: '20px', border: '1px solid var(--border-light)' }}>
        <div style={{ display: 'flex', gap: 12, marginBottom: 20, flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ position: 'relative', flex: '1 1 240px', minWidth: 200, maxWidth: 300 }}>
            <Search size={18} color="#94a3b8" style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)' }} />
            <input
              type="text"
              placeholder="Search federations..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{
                width: '100%',
                padding: '10px 10px 10px 38px',
                borderRadius: 10,
                border: '1px solid #e2e8f0',
                outline: 'none',
                fontSize: 14,
              }}
            />
          </div>

          <div style={{ flex: '2 1 340px', minWidth: 280 }}>
            <StateDistrictSelect
              isFilter={true}
              showLabels={false}
              selectedState={filterState}
              selectedDistrict={filterDistrict}
              onStateChange={(st) => {
                setFilterState(st);
                setFilterDistrict('');
              }}
              onDistrictChange={(dist) => setFilterDistrict(dist)}
              fieldStyle={{ padding: '9.5px 12px', borderRadius: 10, border: '1px solid #e2e8f0', fontSize: 13.5 }}
            />
          </div>

          {(search || filterState || filterDistrict) && (
            <button
              type="button"
              onClick={() => {
                setSearch('');
                setFilterState('');
                setFilterDistrict('');
              }}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 6,
                padding: '9.5px 14px',
                borderRadius: 10,
                border: '1px solid #cbd5e1',
                background: '#f8fafc',
                color: '#64748b',
                fontSize: 13,
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              <RotateCcw size={14} /> Reset
            </button>
          )}
        </div>

        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
            <thead>
              <tr style={{ borderBottom: '1px solid #e2e8f0', color: '#64748b', textAlign: 'left' }}>
                <th style={{ padding: '12px 16px', fontWeight: 600 }}>Name</th>
                <th style={{ padding: '12px 16px', fontWeight: 600 }}>Reg. No.</th>
                <th style={{ padding: '12px 16px', fontWeight: 600 }}>State / District</th>
                <th style={{ padding: '12px 16px', fontWeight: 600 }}>Email</th>
                <th style={{ padding: '12px 16px', fontWeight: 600 }}>Status</th>
                <th style={{ padding: '12px 16px', fontWeight: 600, textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={6} style={{ textAlign: 'center', padding: '30px', color: '#64748b' }}>
                    Loading...
                  </td>
                </tr>
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={6} style={{ textAlign: 'center', padding: '30px', color: '#64748b' }}>
                    No federations found.
                  </td>
                </tr>
              ) : (
                filtered.map((f) => (
                  <tr key={f._id} style={{ borderBottom: '1px solid #f1f5f9' }}>
                    <td style={{ padding: '14px 16px', fontWeight: 500, color: '#1e293b' }}>{f.name}</td>
                    <td style={{ padding: '14px 16px', color: '#64748b' }}>{f.registrationNumber || '—'}</td>
                    <td style={{ padding: '14px 16px', color: '#64748b' }}>{f.state} / {f.district}</td>
                    <td style={{ padding: '14px 16px', color: '#64748b' }}>{f.email || f.owner?.email || f.ownerEmail || '—'}</td>
                    <td style={{ padding: '14px 16px' }}>
                      <span style={{
                        padding: '4px 10px',
                        borderRadius: 999,
                        fontSize: 12,
                        fontWeight: 600,
                        backgroundColor: f.status === 'approved' ? '#dcfce7' : f.status === 'suspended' ? '#fee2e2' : '#fef9c3',
                        color: f.status === 'approved' ? '#166534' : f.status === 'suspended' ? '#991b1b' : '#854d0e',
                      }}>
                        {(f.status || 'pending').toUpperCase()}
                      </span>
                    </td>
                    <td style={{ padding: '14px 16px', textAlign: 'right' }}>
                      <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                        <button
                          type="button"
                          onClick={() => handleLoginAs(f)}
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: 6,
                            padding: '6px 12px',
                            borderRadius: 8,
                            background: '#eff6ff',
                            color: '#1d4ed8',
                            border: '1px solid #bfdbfe',
                            cursor: 'pointer',
                            fontWeight: 700,
                            fontSize: 12,
                            minHeight: 44,
                          }}
                          title="Login as this federation in a new tab"
                          aria-label={`Login as ${f.name || 'federation'}`}
                        >
                          <LogIn size={15} />
                          Login
                        </button>
                        {f.status !== 'approved' && (
                          <button
                            type="button"
                            onClick={() => handleApprove(f._id)}
                            style={{ padding: '6px', borderRadius: 6, background: '#dcfce7', color: '#166534', border: 'none', cursor: 'pointer', minWidth: 44, minHeight: 44 }}
                            title="Approve"
                            aria-label="Approve federation"
                          >
                            <CheckCircle size={16} />
                          </button>
                        )}
                        {f.status !== 'suspended' && (
                          <button
                            type="button"
                            onClick={() => handleSuspend(f._id)}
                            style={{ padding: '6px', borderRadius: 6, background: '#fee2e2', color: '#991b1b', border: 'none', cursor: 'pointer', minWidth: 44, minHeight: 44 }}
                            title="Suspend"
                            aria-label="Suspend federation"
                          >
                            <XCircle size={16} />
                          </button>
                        )}
                        <Link
                          to={`/federations/${f._id}`}
                          style={{ padding: '6px', borderRadius: 6, background: '#f1f5f9', color: '#475569', border: 'none', cursor: 'pointer', display: 'inline-flex', minWidth: 44, minHeight: 44, alignItems: 'center', justifyContent: 'center' }}
                          title="View Details"
                          aria-label="View federation details"
                        >
                          <Eye size={16} />
                        </Link>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showModal && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="add-federation-title"
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(15, 23, 42, 0.45)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            padding: 16,
          }}
          onClick={() => !saving && setShowModal(false)}
        >
          <form
            onSubmit={handleCreate}
            onClick={(e) => e.stopPropagation()}
            style={{
              width: '100%',
              maxWidth: 560,
              maxHeight: '90vh',
              overflowY: 'auto',
              background: '#fff',
              borderRadius: 16,
              padding: 24,
              boxShadow: '0 20px 40px rgba(0,0,0,0.15)',
            }}
          >
            <h3 id="add-federation-title" style={{ fontSize: 20, fontWeight: 800, color: '#0f172a', margin: '0 0 4px' }}>
              Add Federation
            </h3>
            <p style={{ fontSize: 13, color: '#64748b', marginBottom: 20 }}>
              Creates approved federation + federation_admin login (password stored hashed).
            </p>

            <div style={{ display: 'grid', gap: 14 }}>
              <div>
                <label htmlFor="fed-name" style={labelStyle}>Federation Name *</label>
                <input id="fed-name" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Delhi Labour Federation" style={fieldStyle} />
              </div>
              <div>
                <label htmlFor="fed-fname" style={labelStyle}>Display / Legal Name</label>
                <input id="fed-fname" value={form.federationName} onChange={(e) => setForm({ ...form, federationName: e.target.value })} placeholder="Optional alternate name" style={fieldStyle} />
              </div>
              <div>
                <label htmlFor="fed-email" style={labelStyle}>Login Email *</label>
                <input id="fed-email" type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="admin@federation.org" style={fieldStyle} autoComplete="off" />
              </div>
              <div>
                <label htmlFor="fed-password" style={labelStyle}>Password *</label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <div style={{ position: 'relative', flex: 1 }}>
                    <input
                      id="fed-password"
                      type={showPassword ? 'text' : 'password'}
                      required
                      value={form.password}
                      onChange={(e) => setForm({ ...form, password: e.target.value })}
                      style={{ ...fieldStyle, paddingRight: 42 }}
                      autoComplete="new-password"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword((v) => !v)}
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                      style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', border: 'none', background: 'transparent', cursor: 'pointer', color: '#64748b', minWidth: 32, minHeight: 32 }}
                    >
                      {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                    </button>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      const next = generatePassword();
                      setForm({ ...form, password: next });
                      setShowPassword(true);
                    }}
                    style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '0 12px', borderRadius: 10, border: '1px solid #cbd5e1', background: '#f8fafc', cursor: 'pointer', fontWeight: 600, fontSize: 13, minHeight: 44 }}
                  >
                    <RefreshCw size={14} /> Auto
                  </button>
                  <button
                    type="button"
                    onClick={async () => {
                      try {
                        await navigator.clipboard.writeText(form.password);
                        showToast('success', 'Password copied');
                      } catch {
                        showToast('error', 'Copy failed');
                      }
                    }}
                    aria-label="Copy password"
                    style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0 12px', borderRadius: 10, border: '1px solid #cbd5e1', background: '#f8fafc', cursor: 'pointer', minWidth: 44, minHeight: 44 }}
                  >
                    <Copy size={14} />
                  </button>
                </div>
                <p style={{ fontSize: 12, color: '#64748b', marginTop: 6 }}>Copy and share securely — shown once here.</p>
              </div>
              <div>
                <label htmlFor="fed-phone" style={labelStyle}>Contact Phone</label>
                <input id="fed-phone" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="+91 98765 43210" style={fieldStyle} />
              </div>
              <StateDistrictSelect
                selectedState={form.state}
                selectedDistrict={form.district}
                onStateChange={(st) => setForm({ ...form, state: st, district: '' })}
                onDistrictChange={(dist) => setForm({ ...form, district: dist })}
                stateId="fed-state"
                districtId="fed-district"
                fieldStyle={{ ...fieldStyle, backgroundColor: '#ffffff', cursor: 'pointer' }}
                labelStyle={labelStyle}
              />
              <div>
                <label htmlFor="fed-reg" style={labelStyle}>Registration Number (optional)</label>
                <input id="fed-reg" value={form.registrationNumber} onChange={(e) => setForm({ ...form, registrationNumber: e.target.value })} placeholder="Legal reg. id — not used for login" style={fieldStyle} />
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 22 }}>
              <button
                type="button"
                disabled={saving}
                onClick={() => setShowModal(false)}
                style={{ padding: '10px 16px', borderRadius: 10, border: '1px solid #e2e8f0', background: '#fff', cursor: 'pointer', fontWeight: 600, minHeight: 44 }}
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving}
                style={{ padding: '10px 18px', borderRadius: 10, border: 'none', background: '#2563EB', color: '#fff', cursor: saving ? 'wait' : 'pointer', fontWeight: 700, minHeight: 44 }}
              >
                {saving ? 'Saving…' : 'Save Federation'}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
