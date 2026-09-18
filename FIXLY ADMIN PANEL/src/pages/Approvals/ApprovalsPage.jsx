import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ClipboardCheck,
  CheckCircle,
  XCircle,
  Eye,
  FileText,
  RefreshCw,
  Image as ImageIcon,
  ExternalLink,
  ArrowLeft,
} from 'lucide-react';
import { api } from '../../services/api';
import { useApp } from '../../context/AppContext';
import { useToast } from '../../context/ToastContext';
import Avatar from '../../components/common/Avatar';

const DocThumb = ({ label, url }) => {
  if (!url) {
    return (
      <div
        style={{
          border: '1px dashed #cbd5e1',
          borderRadius: '12px',
          padding: '16px',
          background: '#f8fafc',
          minHeight: '120px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#94a3b8',
          fontSize: '12px',
          textAlign: 'center',
        }}
      >
        {label}: not uploaded
      </div>
    );
  }
  const isPdf = /\.pdf($|\?)/i.test(url) || url.toLowerCase().includes('/raw/upload');
  return (
    <div
      style={{
        border: '1px solid #e2e8f0',
        borderRadius: '12px',
        overflow: 'hidden',
        background: '#fff',
      }}
    >
      <div
        style={{
          padding: '8px 12px',
          borderBottom: '1px solid #f1f5f9',
          fontSize: '12px',
          fontWeight: 700,
          color: '#334155',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <span>{label}</span>
        <a href={url} target="_blank" rel="noreferrer" style={{ color: '#15803d', display: 'inline-flex', gap: 4, alignItems: 'center' }}>
          <ExternalLink size={12} /> Open
        </a>
      </div>
      {isPdf ? (
        <div style={{ padding: '24px', textAlign: 'center', color: '#64748b' }}>
          <FileText size={28} style={{ margin: '0 auto 8px' }} />
          PDF document
        </div>
      ) : (
        <img src={url} alt={label} style={{ width: '100%', maxHeight: 220, objectFit: 'contain', background: '#f8fafc' }} />
      )}
    </div>
  );
};

export default function ApprovalsPage() {
  const { settings, fetchSettings } = useApp();
  const { showToast } = useToast();
  const [tab, setTab] = useState('pending');
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [declineOpen, setDeclineOpen] = useState(false);
  const [declineText, setDeclineText] = useState('');
  const [busy, setBusy] = useState(false);
  const [isMobile, setIsMobile] = useState(() => typeof window !== 'undefined' && window.innerWidth <= 900);

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 900);
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const templates = [
      'Your request to join as a worker has been declined.',
      'Documents unclear or incomplete. Please re-upload clear Aadhaar and PAN photos.',
      'Identity details do not match our records. Please correct and resubmit.'
  ];

  const loadList = useCallback(async () => {
    setLoading(true);
    try {
      const params =
        tab === 'pending'
          ? { pendingApproval: 'true', limit: 50, page: 1 }
          : { kycStatus: tab, limit: 50, page: 1 };
      const res = await api.getWorkers(params);
      if (res.success) setRows(res.data || []);
    } catch (err) {
      showToast?.('error', err.response?.data?.message || 'Failed to load approvals');
    } finally {
      setLoading(false);
    }
  }, [tab, showToast]);

  useEffect(() => {
    fetchSettings?.();
  }, [fetchSettings]);

  useEffect(() => {
    loadList();
    setSelected(null);
    setDeclineOpen(false);
  }, [loadList]);

  const openDetail = async (id, fallbackWorker = null) => {
    if (fallbackWorker) {
      setSelected(fallbackWorker);
    }
    setDetailLoading(true);
    setDeclineOpen(false);
    try {
      const res = await api.getWorkerById(id);
      const worker = res?.worker || res?.data;
      if (res?.success && worker) {
        setSelected(worker);
      } else if (!fallbackWorker && res?.data) {
        setSelected(res.data);
      }
    } catch (err) {
      showToast?.('error', err.response?.data?.message || 'Failed to load worker');
    } finally {
      setDetailLoading(false);
    }
  };

  const handleApprove = async () => {
    if (!selected?._id) return;
    setBusy(true);
    try {
      const res = await api.updateWorkerStatus(selected._id, {
        isVerified: true,
        kycStatus: 'approved',
      });
      if (res.success) {
        showToast?.('success', 'Worker approved — they can enter the dashboard');
        setSelected(null);
        loadList();
      }
    } catch (err) {
      showToast?.('error', err.response?.data?.message || 'Approve failed');
    } finally {
      setBusy(false);
    }
  };

  const handleDecline = async () => {
    const reason = declineText.trim();
    if (!reason) {
      showToast?.('error', 'Decline message required');
      return;
    }
    if (!selected?._id) return;
    setBusy(true);
    try {
      const res = await api.updateWorkerStatus(selected._id, {
        isVerified: false,
        kycStatus: 'rejected',
        declineReason: reason,
      });
      if (res.success) {
        showToast?.('success', 'Worker declined — message will show in the app');
        setSelected(null);
        setDeclineOpen(false);
        setDeclineText('');
        loadList();
      }
    } catch (err) {
      showToast?.('error', err.response?.data?.message || 'Decline failed');
    } finally {
      setBusy(false);
    }
  };

  const exportCSV = () => {
    if (!rows || rows.length === 0) {
      showToast?.('error', 'No data to export');
      return;
    }
    const csvRows = [];
    csvRows.push(['Name', 'Email', 'Phone', 'Status', 'Category']);
    rows.forEach(w => {
      csvRows.push([
        w.name || '',
        w.email || '',
        w.phone || '',
        w.kycDocuments?.status || '',
        w.workerProfile?.category || ''
      ].map(v => `"${v}"`).join(','));
    });
    const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'declined_workers.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  const kyc = selected?.kycDocuments || {};
  const profile = selected?.workerProfile || {};

  return (
    <div style={{ padding: '0 32px 32px', animation: 'fadeIn 0.2s ease' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18, gap: 12 }}>
        <div>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: '#111827', display: 'flex', alignItems: 'center', gap: 10 }}>
            <ClipboardCheck size={22} color="#15803d" /> Verification
          </h2>
          <p style={{ fontSize: 13, color: '#64748b', marginTop: 4 }}>
            Pending worker KYC from the app. Approve → appears under Workers. Decline → message on Flutter verification screen.
          </p>
        </div>
        <button
          type="button"
          onClick={loadList}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 6,
            padding: '8px 12px',
            borderRadius: 8,
            border: '1px solid #e2e8f0',
            background: '#fff',
            fontSize: 13,
            fontWeight: 600,
            color: '#334155',
            cursor: 'pointer',
          }}
        >
          <RefreshCw size={14} /> Refresh
        </button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16, alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', gap: 8 }}>
          {[
            { key: 'pending', label: 'Pending review' },
            { key: 'MANUAL_REVIEW', label: 'Manual Review' },
            { key: 'rejected', label: 'Declined' },
            { key: 'approved', label: 'Approved' },
          ].map((t) => (
            <button
              key={t.key}
              type="button"
              onClick={() => setTab(t.key)}
              style={{
                padding: '8px 14px',
                borderRadius: 999,
                border: 'none',
                fontSize: 13,
                fontWeight: tab === t.key ? 700 : 500,
                background: tab === t.key ? '#15803d' : '#f1f5f9',
                color: tab === t.key ? '#fff' : '#475569',
                cursor: 'pointer',
              }}
            >
              {t.label}
            </button>
          ))}
        </div>
        {tab === 'rejected' && (
          <button
            type="button"
            onClick={exportCSV}
            style={{
              padding: '8px 14px',
              borderRadius: 8,
              border: '1px solid #e2e8f0',
              background: '#fff',
              fontSize: 13,
              fontWeight: 600,
              color: '#334155',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: 6
            }}
          >
            <FileText size={16} /> Export CSV
          </button>
        )}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: (!isMobile && (selected || detailLoading)) ? '1fr 1.1fr' : '1fr', gap: 16 }}>
        {(!isMobile || (!selected && !detailLoading)) && (
          <div
            style={{
              background: '#fff',
              border: '1px solid var(--border-light)',
              borderRadius: 16,
              overflow: 'hidden',
              minHeight: 320,
            }}
          >
            {loading ? (
              <div style={{ padding: 40, textAlign: 'center', color: '#64748b' }}>Loading…</div>
            ) : rows.length === 0 ? (
              <div style={{ padding: 40, textAlign: 'center', color: '#64748b' }}>
                No workers with status “{tab === 'pending' ? 'pending review' : tab}”.
              </div>
            ) : (
              <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
                {rows.map((w) => {
                  const active = selected?._id === w._id;
                  return (
                    <li key={w._id}>
                      <button
                        type="button"
                        onClick={() => openDetail(w._id, w)}
                        style={{
                          width: '100%',
                          textAlign: 'left',
                          display: 'flex',
                          gap: 12,
                          alignItems: 'center',
                          padding: '14px 16px',
                          border: 'none',
                          borderBottom: '1px solid #f1f5f9',
                          background: active ? '#f0fdf4' : '#fff',
                          cursor: 'pointer',
                        }}
                      >
                        <Avatar name={w.name} src={w.avatar} size={40} />
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontWeight: 700, fontSize: 14, color: '#0f172a' }}>{w.name}</div>
                          <div style={{ fontSize: 12, color: '#64748b' }}>
                            {w.phone || '—'} · {w.email || '—'}
                          </div>
                          <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>
                            {w.workerProfile?.category || 'General'} · KYC {w.kycDocuments?.status || '—'}
                          </div>
                        </div>
                        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                          {tab === 'rejected' && (
                            <button
                              onClick={(e) => { e.stopPropagation(); alert('Re-invite sent'); }}
                              style={{ padding: '6px 12px', fontSize: 11, background: '#f1f5f9', color: '#475569', borderRadius: 6, border: '1px solid #e2e8f0', cursor: 'pointer', fontWeight: 600 }}
                            >
                              Re-invite
                            </button>
                          )}
                          <div
                            style={{
                              display: 'flex',
                              alignItems: 'center',
                              gap: 5,
                              padding: '6px 12px',
                              background: active ? '#15803d' : '#f0fdf4',
                              color: active ? '#fff' : '#15803d',
                              borderRadius: 8,
                              fontSize: 12,
                              fontWeight: 600,
                              border: '1px solid #bbf7d0',
                            }}
                          >
                            <Eye size={14} />
                            <span>Review</span>
                          </div>
                        </div>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        )}

        {(selected || detailLoading) && (
          <div
            style={{
              background: '#fff',
              border: '1px solid var(--border-light)',
              borderRadius: 16,
              padding: isMobile ? 14 : 20,
              display: 'flex',
              flexDirection: 'column',
              gap: 16,
              maxHeight: isMobile ? 'none' : 'calc(100vh - 180px)',
              overflowY: 'auto',
            }}
          >
            {isMobile && (
              <button
                type="button"
                onClick={() => setSelected(null)}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 6,
                  padding: '7px 12px',
                  backgroundColor: '#f1f5f9',
                  borderRadius: 8,
                  fontSize: 13,
                  fontWeight: 600,
                  color: '#334155',
                  alignSelf: 'flex-start',
                  border: '1px solid #cbd5e1',
                  cursor: 'pointer',
                  marginBottom: 4,
                }}
              >
                <ArrowLeft size={15} /> Back to List
              </button>
            )}

            {detailLoading && !selected ? (
              <div style={{ color: '#64748b' }}>Loading details…</div>
            ) : selected ? (
              <>
                <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                  <Avatar name={selected.name} src={selected.avatar} size={48} />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 17, fontWeight: 700 }}>{selected.name}</div>
                    <div style={{ fontSize: 13, color: '#64748b' }}>
                      {selected.phone} · {selected.email}
                    </div>
                  </div>
                  <span
                    style={{
                      fontSize: 11,
                      fontWeight: 700,
                      padding: '4px 10px',
                      borderRadius: 999,
                      background: kyc.status === 'approved' ? '#dcfce7' : kyc.status === 'rejected' ? '#fee2e2' : '#fef9c3',
                      color: kyc.status === 'approved' ? '#166534' : kyc.status === 'rejected' ? '#991b1b' : '#854d0e',
                    }}
                  >
                    {(kyc.status || 'none').toUpperCase()}
                  </span>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, fontSize: 13 }}>
                  <div><strong>Category:</strong> {profile.category || '—'}</div>
                  <div><strong>Base Rate:</strong> ₹{profile.rate ?? profile.hourlyRate ?? '—'}</div>
                  <div><strong>Aadhaar:</strong> {kyc.aadhaarNumber || '—'}</div>
                  <div><strong>PAN:</strong> {kyc.panNumber || '—'}</div>
                  <div style={{ gridColumn: '1 / -1' }}>
                    <strong>Skills:</strong>{' '}
                    {Array.isArray(profile.skills) && profile.skills.length
                      ? profile.skills.join(', ')
                      : '—'}
                  </div>
                  {kyc.declineReason && (
                    <div style={{ gridColumn: '1 / -1', background: '#fef2f2', padding: 10, borderRadius: 8, color: '#991b1b' }}>
                      <strong>Decline message:</strong> {kyc.declineReason}
                    </div>
                  )}
                  {kyc.manualReviewReason && (
                    <div style={{ gridColumn: '1 / -1', background: '#fef9c3', padding: 10, borderRadius: 8, color: '#854d0e' }}>
                      <strong>AI Manual Review Required:</strong> {kyc.manualReviewReason}
                    </div>
                  )}
                  {(kyc.livenessScore !== undefined && kyc.livenessScore !== null) && (
                    <div style={{ gridColumn: '1 / -1', background: '#f8fafc', padding: 10, borderRadius: 8, color: '#334155', display: 'flex', gap: 16 }}>
                      <div><strong>Liveness Score:</strong> {kyc.livenessScore}</div>
                      <div><strong>Face Match Score:</strong> {kyc.faceMatchScore}</div>
                      <div><strong>Doc Face Detected:</strong> {kyc.documentFaceDetected ? 'Yes' : 'No'}</div>
                    </div>
                  )}
                </div>

                <div>
                  <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                    <ImageIcon size={15} /> Documents
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                    <DocThumb label="Aadhaar front" url={kyc.aadhaarFrontPhoto} />
                    <DocThumb label="Aadhaar back" url={kyc.aadhaarBackPhoto} />
                    <DocThumb label="PAN front" url={kyc.panFrontPhoto} />
                    <DocThumb label="PAN back" url={kyc.panBackPhoto} />
                    <DocThumb label="Selfie" url={kyc.selfieImageUrl} />
                    <DocThumb label="Certificate / PDF" url={kyc.certificateUrl} />
                  </div>
                </div>

                {(!selected.isVerified || kyc.status?.toLowerCase() !== 'approved') &&
                  !declineOpen && (
                  <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', marginTop: 8 }}>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        setDeclineText(templates[0] || '');
                        setDeclineOpen(true);
                      }}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '10px 16px',
                        borderRadius: 10,
                        border: 'none',
                        background: '#fef2f2',
                        color: '#dc2626',
                        fontWeight: 700,
                        fontSize: 13,
                        cursor: 'pointer',
                      }}
                    >
                      <XCircle size={16} /> Decline
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={handleApprove}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '10px 16px',
                        borderRadius: 10,
                        border: 'none',
                        background: '#15803d',
                        color: '#fff',
                        fontWeight: 700,
                        fontSize: 13,
                        cursor: 'pointer',
                      }}
                    >
                      <CheckCircle size={16} /> Approve
                    </button>
                  </div>
                )}

                {(selected.isVerified && kyc.status?.toLowerCase() === 'approved') && !declineOpen && (
                  <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', marginTop: 8 }}>
                    <div
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '8px 14px',
                        borderRadius: 8,
                        background: '#dcfce7',
                        color: '#15803d',
                        fontWeight: 700,
                        fontSize: 13,
                      }}
                    >
                      <CheckCircle size={16} /> Verified Cooperative Member
                    </div>
                  </div>
                )}

                {declineOpen && (
                  <div
                    style={{
                      border: '1px solid #fecaca',
                      background: '#fff7f7',
                      borderRadius: 12,
                      padding: 14,
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 10,
                    }}
                  >
                    <div style={{ fontWeight: 700, fontSize: 13, color: '#991b1b' }}>
                      Decline message (shown in Flutter verification screen)
                    </div>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                      {templates.map((t, i) => (
                        <button
                          key={i}
                          type="button"
                          onClick={() => setDeclineText(t)}
                          style={{
                            padding: '6px 10px',
                            borderRadius: 8,
                            border: '1px solid #fecaca',
                            background: declineText === t ? '#fee2e2' : '#fff',
                            fontSize: 11,
                            cursor: 'pointer',
                            maxWidth: '100%',
                            textAlign: 'left',
                          }}
                        >
                          {t.length > 60 ? `${t.slice(0, 60)}…` : t}
                        </button>
                      ))}
                    </div>
                    <textarea
                      value={declineText}
                      onChange={(e) => setDeclineText(e.target.value)}
                      rows={3}
                      placeholder="Edit or write a custom decline message…"
                      style={{
                        width: '100%',
                        padding: 10,
                        borderRadius: 8,
                        border: '1px solid #fca5a5',
                        fontSize: 13,
                        fontFamily: 'inherit',
                      }}
                    />
                    <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                      <button
                        type="button"
                        onClick={() => setDeclineOpen(false)}
                        style={{ padding: '8px 12px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', cursor: 'pointer' }}
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={handleDecline}
                        style={{
                          padding: '8px 14px',
                          borderRadius: 8,
                          border: 'none',
                          background: '#dc2626',
                          color: '#fff',
                          fontWeight: 700,
                          cursor: 'pointer',
                        }}
                      >
                        Confirm decline
                      </button>
                    </div>
                  </div>
                )}
              </>
            ) : null}
          </div>
        )}
      </div>
    </div>
  );
}
