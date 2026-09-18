import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useApp } from '../../context/AppContext';
import { useToast } from '../../context/ToastContext';
import { api } from '../../services/api';
import {
  ArrowLeft,
  ShieldCheck,
  Star,
  Phone,
  Mail,
  MapPin,
  Award,
  CreditCard,
  CalendarCheck,
  Clock,
  Download,
  Save,
  CheckCircle2,
  XCircle,
  ToggleLeft,
  ToggleRight,
  Briefcase,
  User,
  DollarSign,
  FileText,
  AlertTriangle,
  Eye,
  Camera,
  Upload,
  Image as ImageIcon,
  ExternalLink,
  CheckCircle,
  Sparkles
} from 'lucide-react';
import Badge from '../../components/common/Badge';
import Modal from '../../components/common/Modal';
import Avatar from '../../components/common/Avatar';
import { OFFICIAL_CATEGORIES, getMergedCategories } from '../../data/services';
import StateDistrictSelect from '../../components/common/StateDistrictSelect';

// Reusable Document Thumbnail with Preview & Zoom
const DocumentCard = ({ title, url, inputKey, inputValue, onInputChange, isPdf }) => {
  const [modalOpen, setModalOpen] = useState(false);
  const isDocumentPdf = isPdf || (url && (/\.pdf($|\?)/i.test(url) || url.toLowerCase().includes('/raw/upload')));

  return (
    <div
      style={{
        backgroundColor: '#f8fafc',
        padding: '16px',
        borderRadius: '12px',
        border: '1px solid #e2e8f0',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
      }}
    >
      <div>
        <div
          style={{
            fontSize: '13px',
            fontWeight: '700',
            color: '#0f172a',
            marginBottom: '10px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            {isDocumentPdf ? <FileText size={16} color="#0284c7" /> : <ImageIcon size={16} color="#15803d" />}
            {title}
          </span>
          {url && (
            <a
              href={url}
              target="_blank"
              rel="noreferrer"
              style={{
                fontSize: '11.5px',
                fontWeight: '700',
                color: '#15803d',
                textDecoration: 'none',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px',
              }}
            >
              <ExternalLink size={12} /> Open
            </a>
          )}
        </div>

        {url ? (
          <div style={{ position: 'relative', marginBottom: '10px' }}>
            {isDocumentPdf ? (
              <div
                style={{
                  height: '140px',
                  backgroundColor: '#ffffff',
                  border: '1px solid #cbd5e1',
                  borderRadius: '8px',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#475569',
                  gap: '8px',
                }}
              >
                <FileText size={32} color="#0284c7" />
                <span style={{ fontSize: '12px', fontWeight: '600' }}>PDF Document Attached</span>
              </div>
            ) : (
              <div
                style={{
                  position: 'relative',
                  cursor: 'pointer',
                  borderRadius: '8px',
                  overflow: 'hidden',
                  border: '1px solid #cbd5e1',
                }}
                onClick={() => setModalOpen(true)}
              >
                <img
                  src={url}
                  alt={title}
                  style={{
                    width: '100%',
                    height: '140px',
                    objectFit: 'contain',
                    backgroundColor: '#ffffff',
                    display: 'block',
                  }}
                />
                <div
                  style={{
                    position: 'absolute',
                    bottom: '6px',
                    right: '6px',
                    backgroundColor: 'rgba(0, 0, 0, 0.7)',
                    color: '#ffffff',
                    padding: '3px 8px',
                    borderRadius: '6px',
                    fontSize: '11px',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                  }}
                >
                  <Eye size={12} /> Preview
                </div>
              </div>
            )}
          </div>
        ) : (
          <div
            style={{
              backgroundColor: '#fff1f2',
              border: '1px dashed #fda4af',
              padding: '24px 16px',
              borderRadius: '8px',
              textAlign: 'center',
              color: '#be123c',
              fontSize: '12px',
              marginBottom: '10px',
            }}
          >
            <AlertTriangle size={20} color="#e11d48" style={{ margin: '0 auto 6px auto', display: 'block' }} />
            <strong>{title} Not Uploaded</strong>
          </div>
        )}
      </div>

      <div>
        <label
          style={{
            fontSize: '11px',
            fontWeight: '600',
            color: '#64748b',
            display: 'block',
            marginBottom: '4px',
          }}
        >
          Image / Document URL
        </label>
        <input
          type="text"
          value={inputValue || ''}
          onChange={(e) => onInputChange(inputKey, e.target.value)}
          placeholder={`https://res.cloudinary.com/.../${inputKey}.jpg`}
          style={{
            width: '100%',
            padding: '7px 10px',
            borderRadius: '6px',
            border: '1px solid #cbd5e1',
            fontSize: '12px',
            backgroundColor: '#ffffff',
          }}
        />
      </div>

      {/* Full Preview Modal */}
      {modalOpen && (
        <Modal
          isOpen={modalOpen}
          onClose={() => setModalOpen(false)}
          title={`Document View: ${title}`}
          maxWidth="700px"
        >
          <div style={{ textAlign: 'center', padding: '10px' }}>
            <img
              src={url}
              alt={title}
              style={{
                maxWidth: '100%',
                maxHeight: '70vh',
                borderRadius: '8px',
                boxShadow: '0 4px 16px rgba(0,0,0,0.15)',
              }}
            />
            <div style={{ marginTop: '16px', display: 'flex', justifyContent: 'center', gap: '12px' }}>
              <a
                href={url}
                target="_blank"
                rel="noreferrer"
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '6px',
                  padding: '8px 16px',
                  backgroundColor: '#15803d',
                  color: '#ffffff',
                  borderRadius: '8px',
                  fontSize: '13px',
                  fontWeight: '600',
                  textDecoration: 'none',
                }}
              >
                <ExternalLink size={14} /> Open Original Full Resolution
              </a>
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                style={{
                  padding: '8px 16px',
                  backgroundColor: '#e2e8f0',
                  color: '#334155',
                  borderRadius: '8px',
                  fontSize: '13px',
                  fontWeight: '600',
                  border: 'none',
                  cursor: 'pointer',
                }}
              >
                Close Preview
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default function WorkerDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { workers, bookings, updateWorker, verifyWorker, rejectWorker, services } = useApp();
  const { showToast } = useToast();

  const [loadingWorker, setLoadingWorker] = useState(true);
  const [workerData, setWorkerData] = useState(null);
  const [workerBookings, setWorkerBookings] = useState([]);
  const [saving, setSaving] = useState(false);
  const [verifyingAction, setVerifyingAction] = useState(false);
  const [declineOpen, setDeclineOpen] = useState(false);
  const [declineText, setDeclineText] = useState('Documents unclear or incomplete. Please re-upload clear Aadhaar and PAN photos.');
  const [activeTab, setActiveTab] = useState('edit'); // 'edit', 'documents', 'financials', 'history'
  const [isCustomTrade, setIsCustomTrade] = useState(false);
  const [customTrade, setCustomTrade] = useState('');

  const tradeOptions = React.useMemo(() => {
    return getMergedCategories(services);
  }, [services]);

  // Editable Form State
  const [formState, setFormState] = useState({
    name: '',
    email: '',
    phone: '',
    isVerified: false,
    category: 'Plumbing',
    hourlyRate: 500,
    serviceRadiusKm: 15,
    state: '',
    district: '',
    experienceYears: 3,
    bio: '',
    skills: '',
    walletBalance: 0,
    totalEarnings: 0,
    totalJobs: 0,
    rating: 4.9,
    // KYC Document fields
    aadhaarNumber: '',
    aadhaarFrontPhoto: '',
    aadhaarBackPhoto: '',
    panNumber: '',
    panFrontPhoto: '',
    panBackPhoto: '',
    selfieImageUrl: '',
    certificateUrl: '',
    govermentIdType: 'Aadhaar Card',
    govermentIdNumber: '',
    identityProofPhoto: '',
    identityFrontPhoto: '',
    identityBackPhoto: '',
    kycStatus: 'none',
    livenessScore: null,
    faceMatchScore: null,
    documentFaceDetected: null,
    selfieFaceDetected: null,
    manualReviewReason: '',
    declineReason: ''
  });

  const populateWorkerFields = (w, backendBookings = []) => {
    const kyc = w.kycDocuments || {};
    const aadhaarFront = kyc.aadhaarFrontPhoto || w.workerProfile?.identityFrontPhoto || w.workerProfile?.identityProofPhoto || '';
    const aadhaarBack = kyc.aadhaarBackPhoto || w.workerProfile?.identityBackPhoto || '';
    const panFront = kyc.panFrontPhoto || '';
    const panBack = kyc.panBackPhoto || '';
    const selfie = kyc.selfieImageUrl || w.workerProfile?.selfieImageUrl || w.avatar || '';
    const cert = kyc.certificateUrl || (Array.isArray(w.workerProfile?.certifications) ? w.workerProfile.certifications[0] : '') || '';
    const aadhaarNum = kyc.aadhaarNumber || kyc.govermentIdNumber || w.workerProfile?.govermentIdNumber || '';
    const panNum = kyc.panNumber || '';
    const govIdType = kyc.govermentIdType || w.workerProfile?.govermentIdType || (aadhaarNum ? 'Aadhaar Card' : (panNum ? 'PAN Card' : 'Aadhaar Card'));
    const govIdNum = kyc.govermentIdNumber || aadhaarNum || panNum || w.workerProfile?.govermentIdNumber || '';

    setFormState({
      name: w.name || '',
      email: w.email || '',
      phone: w.phone || '',
      isVerified: Boolean(w.isVerified),
      category: w.workerProfile?.category || w.service || 'Plumbing',
      hourlyRate: w.workerProfile?.rate ?? w.workerProfile?.hourlyRate ?? 500,
      serviceRadiusKm: w.workerProfile?.serviceRadiusKm ?? 15,
      state: w.workerProfile?.state || w.savedAddresses?.[0]?.state || '',
      district: w.workerProfile?.district || w.savedAddresses?.[0]?.city || '',
      experienceYears: w.workerProfile?.experienceYears ?? 3,
      bio: w.workerProfile?.bio || '',
      skills: Array.isArray(w.workerProfile?.skills)
        ? w.workerProfile.skills.join(', ')
        : (w.skills ? w.skills.join(', ') : 'Plumbing, Installation'),
      walletBalance: w.workerProfile?.walletBalance ?? 0,
      totalEarnings: w.workerProfile?.totalEarnings ?? 0,
      totalJobs: w.workerProfile?.totalJobs ?? backendBookings.length,
      rating: w.workerProfile?.rating ?? 4.9,
      // KYC Document fields
      aadhaarNumber: aadhaarNum,
      aadhaarFrontPhoto: aadhaarFront,
      aadhaarBackPhoto: aadhaarBack,
      panNumber: panNum,
      panFrontPhoto: panFront,
      panBackPhoto: panBack,
      selfieImageUrl: selfie,
      certificateUrl: cert,
      govermentIdType: govIdType,
      govermentIdNumber: govIdNum,
      identityProofPhoto: aadhaarFront,
      identityFrontPhoto: aadhaarFront,
      identityBackPhoto: aadhaarBack,
      kycStatus: kyc.status || (w.isVerified ? 'approved' : 'none'),
      livenessScore: kyc.livenessScore,
      faceMatchScore: kyc.faceMatchScore,
      documentFaceDetected: kyc.documentFaceDetected,
      selfieFaceDetected: kyc.selfieFaceDetected,
      manualReviewReason: kyc.manualReviewReason || '',
      declineReason: kyc.declineReason || ''
    });
  };

  useEffect(() => {
    let isMounted = true;
    const loadWorkerDetails = async () => {
      setLoadingWorker(true);
      try {
        const res = await api.getWorkerById(id);
        if (res.success && res.worker && isMounted) {
          const w = res.worker;
          setWorkerData(w);
          const backendBookings = Array.isArray(res.bookings) ? res.bookings : [];
          setWorkerBookings(backendBookings);
          populateWorkerFields(w, backendBookings);
        }
      } catch (err) {
        console.error('Error fetching worker details by ID:', err);
        const found = workers.find((w) => w.id === id || w.rawId === id || w._id === id);
        if (found && isMounted) {
          setWorkerData(found);
          const matchedBookings = bookings.filter((b) => b && (b.workerId === found._id || b.workerId === found.id || b.worker === found.name));
          setWorkerBookings(matchedBookings);
          populateWorkerFields(found, matchedBookings);
        }
      } finally {
        if (isMounted) setLoadingWorker(false);
      }
    };

    loadWorkerDetails();
    return () => {
      isMounted = false;
    };
  }, [id, workers, bookings]);

  // Handle Quick ON/OFF Verification Toggle
  const handleToggleVerification = async () => {
    const newStatus = !formState.isVerified;
    setFormState((prev) => ({
      ...prev,
      isVerified: newStatus,
      kycStatus: newStatus ? 'approved' : 'none'
    }));
    try {
      if (newStatus) {
        await verifyWorker(id);
      } else {
        await updateWorker(id, {
          isVerified: false,
          kycStatus: 'none',
          email: formState.email
        });
      }
      showToast('success', `Worker verification status updated to ${newStatus ? 'VERIFIED' : 'UNVERIFIED'}`);
    } catch (err) {
      setFormState((prev) => ({ ...prev, isVerified: !newStatus }));
      showToast('error', 'Failed to update verification status');
    }
  };

  // Direct Approve from Documents Tab
  const handleApproveKyc = async () => {
    setVerifyingAction(true);
    try {
      await verifyWorker(id);
      setFormState((prev) => ({
        ...prev,
        isVerified: true,
        kycStatus: 'approved'
      }));
      showToast('success', 'Worker KYC approved and verified successfully!');
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to approve worker');
    } finally {
      setVerifyingAction(false);
    }
  };

  // Direct Reject / Request Re-upload
  const handleDeclineKyc = async () => {
    setVerifyingAction(true);
    try {
      await rejectWorker(id, declineText);
      setFormState((prev) => ({
        ...prev,
        isVerified: false,
        kycStatus: 'rejected',
        declineReason: declineText
      }));
      setDeclineOpen(false);
      showToast('info', 'Worker KYC marked as declined / re-upload requested.');
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to reject worker');
    } finally {
      setVerifyingAction(false);
    }
  };

  const handleDocumentFieldChange = (key, value) => {
    setFormState((prev) => ({
      ...prev,
      [key]: value
    }));
  };

  // Handle Profile Save
  const handleSaveProfile = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      const payload = {
        name: formState.name,
        email: formState.email,
        phone: formState.phone,
        isVerified: formState.isVerified,
        category: formState.category,
        rate: Number(formState.hourlyRate),
        hourlyRate: Number(formState.hourlyRate),
        serviceRadiusKm: Number(formState.serviceRadiusKm) || 15,
        state: formState.state,
        district: formState.district,
        experienceYears: Number(formState.experienceYears),
        bio: formState.bio,
        skills: formState.skills.split(',').map((s) => s.trim()).filter(Boolean),
        walletBalance: Number(formState.walletBalance),
        totalEarnings: Number(formState.totalEarnings),
        totalJobs: Number(formState.totalJobs),
        rating: Number(formState.rating),
        // Government & KYC Fields
        govermentIdType: formState.govermentIdType,
        govermentIdNumber: formState.govermentIdNumber || formState.aadhaarNumber,
        identityProofPhoto: formState.aadhaarFrontPhoto || formState.identityFrontPhoto,
        identityFrontPhoto: formState.aadhaarFrontPhoto || formState.identityFrontPhoto,
        identityBackPhoto: formState.aadhaarBackPhoto || formState.identityBackPhoto,
        aadhaarNumber: formState.aadhaarNumber,
        aadhaarFrontPhoto: formState.aadhaarFrontPhoto,
        aadhaarBackPhoto: formState.aadhaarBackPhoto,
        panNumber: formState.panNumber,
        panFrontPhoto: formState.panFrontPhoto,
        panBackPhoto: formState.panBackPhoto,
        selfieImageUrl: formState.selfieImageUrl,
        certificateUrl: formState.certificateUrl,
        kycStatus: formState.kycStatus,
        declineReason: formState.declineReason
      };

      const res = await updateWorker(id, payload);
      if (res && res.worker) {
        setWorkerData(res.worker);
      }
      showToast('success', 'Worker profile & documents updated successfully!');
    } catch (err) {
      console.error('Save worker error:', err);
      showToast('error', 'Failed to save worker modifications');
    } finally {
      setSaving(false);
    }
  };

  const currentWorker = workerData || {};
  const currentCategory = formState.category || 'Plumbing';
  const currentVerified = formState.isVerified;

  const hasDocs = Boolean(
    formState.aadhaarFrontPhoto ||
    formState.aadhaarBackPhoto ||
    formState.panFrontPhoto ||
    formState.panBackPhoto ||
    formState.selfieImageUrl ||
    formState.certificateUrl ||
    formState.identityFrontPhoto ||
    formState.identityProofPhoto
  );

  return (
    <div style={{ padding: '0 32px 32px 32px', animation: 'fadeIn 0.2s ease', maxWidth: '1100px' }}>
      {/* Back button */}
      <button
        onClick={() => navigate('/workers')}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '6px',
          padding: '6px 14px',
          borderRadius: '8px',
          backgroundColor: '#ffffff',
          border: '1px solid var(--border-light)',
          color: '#475569',
          fontSize: '13px',
          fontWeight: '600',
          marginBottom: '18px',
          cursor: 'pointer'
        }}
      >
        <ArrowLeft size={15} />
        <span>Back to Workers Directory</span>
      </button>

      {/* Main Profile Header & ON/OFF Verification Bar */}
      <div
        style={{
          backgroundColor: '#ffffff',
          borderRadius: '16px',
          border: '1px solid var(--border-light)',
          padding: '24px 28px',
          boxShadow: 'var(--shadow-card)',
          marginBottom: '20px',
        }}
      >
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            flexWrap: 'wrap',
            gap: '20px',
          }}
        >
          <div style={{ display: 'flex', gap: '20px', alignItems: 'center' }}>
            <Avatar
              src={formState.selfieImageUrl || formState.avatar || currentWorker.avatar}
              name={formState.name}
              size={80}
              border={`3.5px solid ${currentVerified ? '#15803d' : '#94a3b8'}`}
              style={{
                boxShadow: currentVerified ? '0 4px 12px rgba(21, 128, 61, 0.25)' : 'none',
              }}
            />

            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <h2 style={{ fontSize: '22px', fontWeight: '800', color: '#111827' }}>
                  {formState.name || 'Worker Member'}
                </h2>
                <Badge status={currentVerified ? 'Verified' : 'Pending Review'} />
              </div>

              <div style={{ fontSize: '13.5px', fontWeight: '700', color: '#15803d', marginTop: '2px' }}>
                {currentCategory} Professional • Member #{currentWorker._id || id}
              </div>

              <div style={{ display: 'flex', gap: '16px', marginTop: '8px', fontSize: '12.5px', color: '#64748b', flexWrap: 'wrap' }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <Phone size={13} /> {formState.phone || '+91 98765 43210'}
                </span>
                <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <Mail size={13} /> {formState.email || 'worker@cooperative.org'}
                </span>
                {(formState.district || formState.state) && (
                  <span style={{ display: 'flex', alignItems: 'center', gap: '4px', color: '#0369a1', fontWeight: 600 }}>
                    <MapPin size={13} /> {[formState.district, formState.state].filter(Boolean).join(', ')}
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Quick Verification ON/OFF Toggle Control */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '14px',
              backgroundColor: currentVerified ? '#f0fdf4' : '#fffbe0',
              padding: '12px 18px',
              borderRadius: '12px',
              border: `1.5px solid ${currentVerified ? '#bbf7d0' : '#fef08a'}`,
            }}
          >
            <div>
              <div style={{ fontSize: '12px', fontWeight: '700', color: currentVerified ? '#15803d' : '#b45309' }}>
                VERIFICATION STATUS
              </div>
              <div style={{ fontSize: '13px', fontWeight: '800', color: currentVerified ? '#166534' : '#92400e' }}>
                {currentVerified ? '✅ VERIFIED MEMBER' : '⚠️ UNVERIFIED / PENDING'}
              </div>
            </div>

            <button
              type="button"
              onClick={handleToggleVerification}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '8px 16px',
                borderRadius: '8px',
                backgroundColor: currentVerified ? '#15803d' : '#ca8a04',
                color: '#ffffff',
                border: 'none',
                fontSize: '13px',
                fontWeight: '700',
                cursor: 'pointer',
                boxShadow: '0 2px 6px rgba(0,0,0,0.1)'
              }}
              title="Click to Toggle Verification Status ON/OFF"
            >
              {currentVerified ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
              <span>{currentVerified ? 'Turn OFF (Unverify)' : 'Turn ON (Verify Member)'}</span>
            </button>
          </div>
        </div>
      </div>

      {/* Tabs Header */}
      <div style={{ display: 'flex', gap: '8px', borderBottom: '1px solid var(--border-light)', marginBottom: '20px' }}>
        {[
          { key: 'edit', label: '✏️ Edit Profile & Trade Details', icon: User },
          { key: 'documents', label: '📑 Identity & Document Verification', icon: FileText },
          { key: 'financials', label: '💳 Wallet & Financials', icon: DollarSign },
          { key: 'history', label: `📋 Job History (${workerBookings.length})`, icon: Briefcase },
        ].map((tab) => {
          const isActive = activeTab === tab.key;
          return (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              style={{
                padding: '10px 18px',
                fontSize: '13.5px',
                fontWeight: isActive ? '700' : '500',
                color: isActive ? '#15803d' : '#64748b',
                borderBottom: isActive ? '2.5px solid #15803d' : 'none',
                backgroundColor: 'transparent',
                border: 'none',
                cursor: 'pointer',
                marginBottom: '-1px',
              }}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* TAB 1: EDIT PROFILE FORM */}
      {activeTab === 'edit' && (
        <form onSubmit={handleSaveProfile} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* Section 1: Basic Credentials */}
          <div style={{ backgroundColor: '#ffffff', padding: '22px', borderRadius: '16px', border: '1px solid var(--border-light)' }}>
            <h3 style={{ fontSize: '15px', fontWeight: '700', color: '#111827', marginBottom: '16px' }}>
              Basic Member Information
            </h3>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Full Name
                </label>
                <input
                  type="text"
                  value={formState.name}
                  onChange={(e) => setFormState({ ...formState, name: e.target.value })}
                  required
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Email Address
                </label>
                <input
                  type="email"
                  value={formState.email}
                  onChange={(e) => setFormState({ ...formState, email: e.target.value })}
                  required
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Phone Number
                </label>
                <input
                  type="text"
                  value={formState.phone}
                  onChange={(e) => setFormState({ ...formState, phone: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>
            </div>
          </div>

          {/* Section 2: Trade & Skills Configuration */}
          <div style={{ backgroundColor: '#ffffff', padding: '22px', borderRadius: '16px', border: '1px solid var(--border-light)' }}>
            <h3 style={{ fontSize: '15px', fontWeight: '700', color: '#111827', marginBottom: '16px' }}>
              Trade, Skills & Pricing Configuration
            </h3>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569' }}>
                    Primary Service Trade
                  </label>
                  {isCustomTrade ? (
                    <button
                      type="button"
                      onClick={() => setIsCustomTrade(false)}
                      style={{ background: 'none', border: 'none', color: '#0284c7', fontSize: '11px', cursor: 'pointer', fontWeight: 600 }}
                    >
                      ← Standard List
                    </button>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setIsCustomTrade(true)}
                      style={{ background: 'none', border: 'none', color: '#15803d', fontSize: '11px', cursor: 'pointer', fontWeight: 600 }}
                    >
                      + Custom Trade
                    </button>
                  )}
                </div>

                {isCustomTrade ? (
                  <input
                    type="text"
                    value={customTrade || formState.category}
                    onChange={(e) => {
                      setCustomTrade(e.target.value);
                      setFormState({ ...formState, category: e.target.value });
                    }}
                    placeholder="e.g. Solar Panel Technician"
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                  />
                ) : (
                  <select
                    value={formState.category}
                    onChange={(e) => setFormState({ ...formState, category: e.target.value })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', backgroundColor: '#ffffff' }}
                  >
                    {tradeOptions.map((trade) => (
                      <option key={trade} value={trade}>
                        {trade}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Standard Hourly / Base Rate (₹)
                </label>
                <input
                  type="number"
                  min="50"
                  step="10"
                  value={formState.hourlyRate}
                  onChange={(e) => setFormState({ ...formState, hourlyRate: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Service Radius (km)
                </label>
                <input
                  type="number"
                  min="1"
                  max="100"
                  value={formState.serviceRadiusKm}
                  onChange={(e) => setFormState({ ...formState, serviceRadiusKm: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Experience (Years)
                </label>
                <input
                  type="number"
                  value={formState.experienceYears}
                  onChange={(e) => setFormState({ ...formState, experienceYears: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>
            </div>

            <div style={{ marginBottom: '16px' }}>
              <StateDistrictSelect
                selectedState={formState.state}
                selectedDistrict={formState.district}
                onStateChange={(st) => setFormState({ ...formState, state: st, district: '' })}
                onDistrictChange={(dist) => setFormState({ ...formState, district: dist })}
                stateLabel="Home / Operating State"
                districtLabel="Home / Operating District"
                stateRequired={false}
                districtRequired={false}
              />
            </div>

            <div style={{ marginBottom: '16px' }}>
              <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                Specific Skills (Comma Separated)
              </label>
              <input
                type="text"
                value={formState.skills}
                onChange={(e) => setFormState({ ...formState, skills: e.target.value })}
                placeholder="e.g. Pipe Fitting, Bathroom Fitting, Leak Detection, Geyser Installation"
                style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
              />
            </div>

            <div>
              <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                Operational Bio & Summary
              </label>
              <textarea
                value={formState.bio}
                onChange={(e) => setFormState({ ...formState, bio: e.target.value })}
                rows="3"
                placeholder="Brief professional profile and experience summary..."
                style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', fontFamily: 'inherit' }}
              />
            </div>
          </div>

          {/* Save Button */}
          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '10px' }}>
            <button
              type="submit"
              disabled={saving}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '12px 28px',
                backgroundColor: '#15803d',
                color: '#ffffff',
                borderRadius: '10px',
                fontSize: '14px',
                fontWeight: '700',
                border: 'none',
                cursor: 'pointer',
                boxShadow: '0 4px 12px rgba(21, 128, 61, 0.25)',
              }}
            >
              <Save size={16} />
              <span>{saving ? 'Saving Edits...' : 'Save Worker Profile Changes'}</span>
            </button>
          </div>
        </form>
      )}

      {/* TAB 2: IDENTITY DOCUMENT VERIFICATION (FULL AADHAAR, PAN, SELFIE & CERTIFICATES) */}
      {activeTab === 'documents' && (
        <form onSubmit={handleSaveProfile} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ backgroundColor: '#ffffff', padding: '22px', borderRadius: '16px', border: '1px solid var(--border-light)' }}>
            
            {/* Header with Verification Status */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px', flexWrap: 'wrap', gap: '12px' }}>
              <div>
                <h3 style={{ fontSize: '16px', fontWeight: '800', color: '#111827' }}>
                  Government Identity Proof & KYC Verification
                </h3>
                <p style={{ fontSize: '12.5px', color: '#64748b', marginTop: '2px' }}>
                  Official documents uploaded by the worker (Aadhaar Card, PAN Card, Live Selfie, and Skill Certificates).
                </p>
              </div>

              <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
                <div
                  style={{
                    padding: '6px 14px',
                    borderRadius: '8px',
                    backgroundColor: currentVerified ? '#eaf8ef' : (hasDocs ? '#fefce8' : '#fff1f2'),
                    color: currentVerified ? '#15803d' : (hasDocs ? '#ca8a04' : '#e11d48'),
                    fontSize: '12.5px',
                    fontWeight: '700',
                    border: `1px solid ${currentVerified ? '#bbf7d0' : (hasDocs ? '#fef08a' : '#fecdd3')}`,
                  }}
                >
                  {currentVerified
                    ? '✅ KYC Approved & Verified'
                    : hasDocs
                    ? '⏳ Documents Submitted'
                    : '⚠️ Identity Proof Not Uploaded'}
                </div>

                {!currentVerified && hasDocs && (
                  <button
                    type="button"
                    disabled={verifyingAction}
                    onClick={handleApproveKyc}
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '6px',
                      padding: '7px 16px',
                      backgroundColor: '#15803d',
                      color: '#ffffff',
                      borderRadius: '8px',
                      fontSize: '13px',
                      fontWeight: '700',
                      border: 'none',
                      cursor: 'pointer',
                    }}
                  >
                    <CheckCircle size={15} /> Approve KYC
                  </button>
                )}

                {hasDocs && (
                  <button
                    type="button"
                    disabled={verifyingAction}
                    onClick={() => setDeclineOpen(true)}
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '6px',
                      padding: '7px 14px',
                      backgroundColor: '#fff1f2',
                      color: '#e11d48',
                      borderRadius: '8px',
                      fontSize: '13px',
                      fontWeight: '600',
                      border: '1px solid #fecdd3',
                      cursor: 'pointer',
                    }}
                  >
                    <XCircle size={15} /> Reject / Request Re-upload
                  </button>
                )}
              </div>
            </div>

            {/* AI Fraud & Liveness Banner if Available */}
            {(formState.livenessScore != null || formState.faceMatchScore != null || formState.manualReviewReason) && (
              <div
                style={{
                  backgroundColor: formState.manualReviewReason ? '#fffbeb' : '#f0fdf4',
                  border: `1px solid ${formState.manualReviewReason ? '#fef08a' : '#bbf7d0'}`,
                  borderRadius: '12px',
                  padding: '14px 18px',
                  marginBottom: '20px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  flexWrap: 'wrap',
                  gap: '12px',
                }}
              >
                <div>
                  <div style={{ fontSize: '13px', fontWeight: '700', color: formState.manualReviewReason ? '#854d0e' : '#166534', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <Sparkles size={16} /> AI Biometric & Verification Scores
                  </div>
                  {formState.manualReviewReason && (
                    <div style={{ fontSize: '12.5px', color: '#b45309', marginTop: '4px' }}>
                      <strong>Review Note:</strong> {formState.manualReviewReason}
                    </div>
                  )}
                </div>

                <div style={{ display: 'flex', gap: '16px', fontSize: '12.5px', color: '#334155' }}>
                  {formState.livenessScore != null && (
                    <div><strong>Liveness Score:</strong> {formState.livenessScore}</div>
                  )}
                  {formState.faceMatchScore != null && (
                    <div><strong>Face Match:</strong> {formState.faceMatchScore}</div>
                  )}
                  {formState.documentFaceDetected != null && (
                    <div><strong>Doc Face:</strong> {formState.documentFaceDetected ? '✅ Detected' : '❌ No Face'}</div>
                  )}
                </div>
              </div>
            )}

            {/* Government ID Numbers Bar */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px', marginBottom: '22px' }}>
              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Aadhaar Card Number
                </label>
                <input
                  type="text"
                  value={formState.aadhaarNumber}
                  onChange={(e) => setFormState({ ...formState, aadhaarNumber: e.target.value })}
                  placeholder="e.g. 1234-5678-9123"
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  PAN Card Number
                </label>
                <input
                  type="text"
                  value={formState.panNumber}
                  onChange={(e) => setFormState({ ...formState, panNumber: e.target.value })}
                  placeholder="e.g. ABCDE1234F"
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Government ID Type
                </label>
                <select
                  value={formState.govermentIdType}
                  onChange={(e) => setFormState({ ...formState, govermentIdType: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', backgroundColor: '#ffffff' }}
                >
                  <option value="Aadhaar Card">Aadhaar Card</option>
                  <option value="PAN Card">PAN Card</option>
                  <option value="Driving License">Driving License</option>
                  <option value="Voter ID">Voter ID</option>
                  <option value="Passport">Passport</option>
                </select>
              </div>
            </div>

            {/* Document Photo Cards Grid (2 columns on tablet/desktop) */}
            <div style={{ marginTop: '10px' }}>
              <h4 style={{ fontSize: '14px', fontWeight: '700', color: '#1e293b', marginBottom: '14px' }}>
                Uploaded Identity Proof & Certificate Documents (Front, Back & Selfie)
              </h4>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(310px, 1fr))', gap: '18px' }}>
                {/* 1. Aadhaar Card Front Photo */}
                <DocumentCard
                  title="Aadhaar Card (Front Side)"
                  url={formState.aadhaarFrontPhoto || formState.identityFrontPhoto || formState.identityProofPhoto}
                  inputKey="aadhaarFrontPhoto"
                  inputValue={formState.aadhaarFrontPhoto || formState.identityFrontPhoto}
                  onInputChange={handleDocumentFieldChange}
                />

                {/* 2. Aadhaar Card Back Photo */}
                <DocumentCard
                  title="Aadhaar Card (Back Side)"
                  url={formState.aadhaarBackPhoto || formState.identityBackPhoto}
                  inputKey="aadhaarBackPhoto"
                  inputValue={formState.aadhaarBackPhoto || formState.identityBackPhoto}
                  onInputChange={handleDocumentFieldChange}
                />

                {/* 3. PAN Card Front Photo */}
                <DocumentCard
                  title="PAN Card (Front Side)"
                  url={formState.panFrontPhoto}
                  inputKey="panFrontPhoto"
                  inputValue={formState.panFrontPhoto}
                  onInputChange={handleDocumentFieldChange}
                />

                {/* 4. PAN Card Back Photo */}
                <DocumentCard
                  title="PAN Card (Back Side)"
                  url={formState.panBackPhoto}
                  inputKey="panBackPhoto"
                  inputValue={formState.panBackPhoto}
                  onInputChange={handleDocumentFieldChange}
                />

                {/* 5. Live Worker Selfie */}
                <DocumentCard
                  title="Worker Live Selfie / Photo"
                  url={formState.selfieImageUrl || formState.avatar || currentWorker.avatar}
                  inputKey="selfieImageUrl"
                  inputValue={formState.selfieImageUrl}
                  onInputChange={handleDocumentFieldChange}
                />

                {/* 6. Skill Certificate / PDF Proof */}
                <DocumentCard
                  title="Skill / Trade Certificate (PDF or Image)"
                  url={formState.certificateUrl}
                  inputKey="certificateUrl"
                  inputValue={formState.certificateUrl}
                  onInputChange={handleDocumentFieldChange}
                  isPdf={true}
                />
              </div>
            </div>
          </div>

          {/* Action Bar */}
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
            <button
              type="submit"
              disabled={saving}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '12px 28px',
                backgroundColor: '#15803d',
                color: '#ffffff',
                borderRadius: '10px',
                fontSize: '14px',
                fontWeight: '700',
                border: 'none',
                cursor: 'pointer',
                boxShadow: '0 4px 12px rgba(21, 128, 61, 0.25)',
              }}
            >
              <Save size={16} />
              <span>{saving ? 'Saving Documents...' : 'Save All Document Settings'}</span>
            </button>
          </div>
        </form>
      )}

      {/* Decline / Re-upload Modal */}
      {declineOpen && (
        <Modal
          isOpen={declineOpen}
          onClose={() => setDeclineOpen(false)}
          title="Reject / Request KYC Re-upload"
          maxWidth="550px"
        >
          <div>
            <p style={{ fontSize: '13px', color: '#475569', marginBottom: '12px' }}>
              Specify the reason for rejection or re-upload request. This message will be shown directly on the worker's mobile verification screen:
            </p>

            <textarea
              value={declineText}
              onChange={(e) => setDeclineText(e.target.value)}
              rows={4}
              style={{
                width: '100%',
                padding: '10px 12px',
                borderRadius: '8px',
                border: '1px solid #cbd5e1',
                fontSize: '13px',
                fontFamily: 'inherit',
                marginBottom: '16px',
              }}
            />

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setDeclineOpen(false)}
                style={{
                  padding: '8px 16px',
                  backgroundColor: '#f1f5f9',
                  color: '#475569',
                  borderRadius: '8px',
                  fontSize: '13px',
                  fontWeight: '600',
                  border: 'none',
                  cursor: 'pointer',
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={verifyingAction}
                onClick={handleDeclineKyc}
                style={{
                  padding: '8px 18px',
                  backgroundColor: '#e11d48',
                  color: '#ffffff',
                  borderRadius: '8px',
                  fontSize: '13px',
                  fontWeight: '700',
                  border: 'none',
                  cursor: 'pointer',
                }}
              >
                {verifyingAction ? 'Declining...' : 'Submit Decline'}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* TAB 3: FINANCIALS & WALLET */}
      {activeTab === 'financials' && (
        <form onSubmit={handleSaveProfile} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ backgroundColor: '#ffffff', padding: '22px', borderRadius: '16px', border: '1px solid var(--border-light)' }}>
            <h3 style={{ fontSize: '15px', fontWeight: '700', color: '#111827', marginBottom: '16px' }}>
              Worker Wallet & Financial Ledger Balance
            </h3>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Wallet Balance (₹)
                </label>
                <input
                  type="number"
                  value={formState.walletBalance}
                  onChange={(e) => setFormState({ ...formState, walletBalance: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700', color: '#15803d' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Total Lifetime Earnings (₹)
                </label>
                <input
                  type="number"
                  value={formState.totalEarnings}
                  onChange={(e) => setFormState({ ...formState, totalEarnings: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700', color: '#0f172a' }}
                />
              </div>

              <div>
                <label style={{ fontSize: '12px', fontWeight: '600', color: '#475569', display: 'block', marginBottom: '6px' }}>
                  Total Jobs Completed
                </label>
                <input
                  type="number"
                  value={formState.totalJobs}
                  onChange={(e) => setFormState({ ...formState, totalJobs: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
            <button
              type="submit"
              disabled={saving}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '12px 28px',
                backgroundColor: '#15803d',
                color: '#ffffff',
                borderRadius: '10px',
                fontSize: '14px',
                fontWeight: '700',
                border: 'none',
                cursor: 'pointer',
              }}
            >
              <Save size={16} />
              <span>{saving ? 'Updating Wallet...' : 'Update Wallet & Earnings'}</span>
            </button>
          </div>
        </form>
      )}

      {/* TAB 4: JOB ASSIGNMENT HISTORY */}
      {activeTab === 'history' && (
        <div style={{ backgroundColor: '#ffffff', borderRadius: '16px', border: '1px solid var(--border-light)', overflow: 'hidden' }}>
          <div style={{ padding: '16px 20px', borderBottom: '1px solid #f1f5f3', fontWeight: '700', fontSize: '15px' }}>
            Recent Job Assignments for {formState.name} ({workerBookings.length})
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
            <thead>
              <tr style={{ backgroundColor: '#f8faf9', borderBottom: '1px solid #e6ede8', color: '#55695e', fontSize: '12px', fontWeight: '700' }}>
                <th style={{ padding: '12px 18px' }}>Booking ID</th>
                <th style={{ padding: '12px 18px' }}>Customer</th>
                <th style={{ padding: '12px 18px' }}>Service</th>
                <th style={{ padding: '12px 18px' }}>Amount</th>
                <th style={{ padding: '12px 18px' }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {workerBookings.length === 0 ? (
                <tr>
                  <td colSpan="5" style={{ padding: '24px', textAlign: 'center', color: '#64748b', fontSize: '13px' }}>
                    No bookings assigned to this worker yet.
                  </td>
                </tr>
              ) : (
                workerBookings.map((b) => {
                  const customerName = b.customer?.name || (typeof b.customer === 'string' ? b.customer : 'Customer');
                  const serviceTitle = b.service?.title || b.serviceTitle || (typeof b.service === 'string' ? b.service : 'Gig Service');
                  const bookingAmount = b.invoice?.totalAmount || b.pricing?.finalAmount || b.amount || 500;
                  const displayId = b.bookingId || (typeof b._id === 'string' ? b._id : b.id || 'BK-1001');

                  return (
                    <tr key={b._id || b.id || Math.random()} style={{ borderBottom: '1px solid #f1f5f3', fontSize: '13px' }}>
                      <td style={{ padding: '12px 18px', color: '#0284c7', fontWeight: '700' }}>
                        {displayId}
                      </td>
                      <td style={{ padding: '12px 18px' }}>{customerName}</td>
                      <td style={{ padding: '12px 18px' }}>{serviceTitle}</td>
                      <td style={{ padding: '12px 18px', fontWeight: '700' }}>₹{bookingAmount}</td>
                      <td style={{ padding: '12px 18px' }}><Badge status={b.status || 'COMPLETED'} /></td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
