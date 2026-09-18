import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useApp } from '../../context/AppContext';
import { useToast } from '../../context/ToastContext';
import { api } from '../../services/api';
import {
  Sliders,
  User,
  MessageSquareText,
  Save,
  Building2,
  Tag,
  DollarSign,
  Plus,
  Trash2,
  Edit3,
  Search,
  CheckCircle2,
  X,
  Phone,
  MapPin,
  Users,
  Shield,
  Percent,
  Clock,
  RefreshCw,
  Camera,
  Link as LinkIcon,
  Zap,
  Wrench,
  Hammer,
  Sparkles,
  Flame,
  ChevronRight,
  Info,
  Smartphone,
  Database
} from 'lucide-react';
import Avatar from '../../components/common/Avatar';
import StateDistrictSelect from '../../components/common/StateDistrictSelect';

export default function SettingsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { settings, fetchSettings, updateSettings, adminUser, updateAdminProfile } = useApp();
  const { showToast } = useToast();

  const tabParam = searchParams.get('tab');
  const [activeTab, setActiveTab] = useState(tabParam || 'platform');

  const fileInputRef = useRef(null);


  // -------------------------------------------------------------
  // TAB 6: EMERGENCY CONTACTS
  // -------------------------------------------------------------
  const [emergencyContacts, setEmergencyContacts] = useState([]);
  const [showContactModal, setShowContactModal] = useState(false);
  const [newContact, setNewContact] = useState({ name: '', phone: '', category: 'Police' });

  const fetchEmergencyContacts = async () => {
    try {
      const res = await api.getEmergencyContacts();
      if(res && res.data) setEmergencyContacts(res.data);
      else if(Array.isArray(res)) setEmergencyContacts(res);
    } catch(err) {
      console.error(err);
    }
  };

  useEffect(() => {
    if (activeTab === 'emergency_contacts') {
      fetchEmergencyContacts();
    }
  }, [activeTab]);

  const handleAddContact = async (e) => {
    e.preventDefault();
    try {
      await api.createEmergencyContact(newContact);
      setShowContactModal(false);
      setNewContact({ name: '', phone: '', category: 'Police' });
      fetchEmergencyContacts();
      showToast('success', 'Emergency contact added');
    } catch(err) {
      showToast('error', 'Failed to add emergency contact');
    }
  };

  // -------------------------------------------------------------
  // TAB: APP VERSION & REDIS CACHE GOVERNANCE STATE
  // -------------------------------------------------------------
  const [appVersionForm, setAppVersionForm] = useState({
    apiVersion: 'V1',
    appVersion: '1.0.0',
    minVersion: 'V1',
    forceUpdate: false,
    updateTitle: 'Update Available',
    updateMessage: 'A new version of Fixly is available. Please update the app to continue.',
    updateUrl: 'https://play.google.com/store/apps/details?id=com.fixly.app',
    platform: 'all'
  });
  const [savingAppVersion, setSavingAppVersion] = useState(false);
  const [clearingRedis, setClearingRedis] = useState(false);
  const [activeRedisAction, setActiveRedisAction] = useState('');

  const fetchAppVersionData = async () => {
    try {
      const res = await api.getAppVersion();
      if (res && res.version) {
        setAppVersionForm({
          apiVersion: res.version.apiVersion || 'V1',
          appVersion: res.version.appVersion || '1.0.0',
          minVersion: res.version.minVersion || 'V1',
          forceUpdate: Boolean(res.version.forceUpdate),
          updateTitle: res.version.updateTitle || 'Update Available',
          updateMessage: res.version.updateMessage || '',
          updateUrl: res.version.updateUrl || '',
          platform: res.version.platform || 'all'
        });
      }
    } catch (err) {
      console.warn('Could not fetch app version:', err);
    }
  };

  const handleSaveAppVersion = async (e) => {
    if (e) e.preventDefault();
    try {
      setSavingAppVersion(true);
      const res = await api.updateAppVersion(appVersionForm);
      showToast('success', res?.message || `App version updated to ${appVersionForm.apiVersion} & Redis synced!`);
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to update app version');
    } finally {
      setSavingAppVersion(false);
    }
  };

  const handleClearRedisCache = async (type) => {
    if (type === 'all' && !window.confirm('Are you sure you want to FLUSH all Redis cache? This will clear all cached sessions and query results.')) {
      return;
    }
    try {
      setClearingRedis(true);
      setActiveRedisAction(type);
      const res = await api.clearRedisCache(type);
      showToast('success', res?.message || `Redis cache cleared for ${type}!`);
    } catch (err) {
      showToast('error', err.response?.data?.message || `Failed to clear Redis cache for ${type}`);
    } finally {
      setClearingRedis(false);
      setActiveRedisAction('');
    }
  };

  // -------------------------------------------------------------
  // TAB 1: PLATFORM GOVERNANCE STATE
  // -------------------------------------------------------------
  const [platformForm, setPlatformForm] = useState({
    customerPlatformFee: 0,
    workerCommissionPercent: 5,
    cooperativeWelfarePercent: 5,
    workerSearchRadiusKm: 15,
    defaultLaborRatePerHour: 350,
    autoDispatchEnabled: true,
    emergencyHotline: '+91 98765 43210',
    apiKeys: {
      groqApiKey: '',
      geminiApiKey: '',
      cloudinaryUrl: '',
      fixlySupportNumber: '1800-123-4567'
    }
  });
  const [savingPlatform, setSavingPlatform] = useState(false);

  // -------------------------------------------------------------
  // TAB 2: FEDERATION WAGE FLOORS & EMERGENCY SURCHARGES
  // -------------------------------------------------------------
  const [federationForm, setFederationForm] = useState({
    name: 'Fixly Cooperative Federation',
    federationName: 'National Labour Cooperative Federation of India',
    registrationNumber: 'FED-COOP-2026-001',
    fairWagePolicy: 'Cooperative Minimum Fair Wage Guarantee Policy v1.0',
    commissionRate: 0.05,
    welfareContributionRate: 0.05,
    emergencySurchargePercent: 20,
    emergencySurchargeFixed: 50,
    minimumWageFloor: {
      electrical: 450,
      plumbing: 400,
      carpentry: 400,
      cleaning: 300,
      painting: 400,
      appliance: 450,
      gardening: 300,
      default: 350
    }
  });
  const [loadingFederation, setLoadingFederation] = useState(false);
  const [savingFederation, setSavingFederation] = useState(false);

  // -------------------------------------------------------------
  // TAB 3: PRIMARY COOPERATIVE SOCIETIES
  // -------------------------------------------------------------
  const [societies, setSocieties] = useState([]);
  const [loadingSocieties, setLoadingSocieties] = useState(false);
  const [societySearch, setSocietySearch] = useState('');
  const [societyFilterState, setSocietyFilterState] = useState('');
  const [societyFilterDistrict, setSocietyFilterDistrict] = useState('');
  const [showAddSocietyModal, setShowAddSocietyModal] = useState(false);
  const [showAssignWorkerModal, setShowAssignWorkerModal] = useState(false);
  const [selectedSocietyForAssign, setSelectedSocietyForAssign] = useState(null);

  const [newSociety, setNewSociety] = useState({
    name: '',
    registrationNumber: '',
    state: '',
    district: '',
    wardOrArea: '',
    officeAddress: '',
    contactPhone: '',
    presidentName: '',
    secretaryName: '',
    fairWageComplianceScore: 100
  });
  const [assignWorkerData, setAssignWorkerData] = useState({
    workerId: '',
    societyId: '',
    societyMemberId: ''
  });

  // -------------------------------------------------------------
  // TAB 4: PROMOTIONAL COUPON BANNERS
  // -------------------------------------------------------------
  const [banners, setBanners] = useState([]);
  const [loadingBanners, setLoadingBanners] = useState(false);
  const [showAddBannerModal, setShowAddBannerModal] = useState(false);
  const [newBanner, setNewBanner] = useState({
    title: '',
    code: '',
    discount: '',
    discountPercent: 20,
    discountAmount: 0,
    description: '',
    category: 'all',
    targetUserRole: 'all',
    targetUserEmails: '',
    minOrderValue: 299,
    maxDiscount: 200,
    usageLimit: 0,
    validUntil: '',
    gradientStart: '#1E3A8A',
    gradientEnd: '#3B82F6',
    priority: 5,
    isActive: true,
    notifyUsers: true
  });

  // -------------------------------------------------------------
  // TAB 5: ADMIN PROFILE
  // -------------------------------------------------------------
  const [profileState, setProfileState] = useState({
    name: adminUser?.name || 'Administrator',
    email: adminUser?.email || '',
    avatar: adminUser?.avatar || ''
  });
  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false);
  const [showUrlInput, setShowUrlInput] = useState(false);

  // -------------------------------------------------------------
  // LIFECYCLE & SYNC
  // -------------------------------------------------------------
  useEffect(() => {
    if (tabParam) setActiveTab(tabParam);
  }, [tabParam]);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  useEffect(() => {
    if (settings && Object.keys(settings).length > 0) {
      setPlatformForm({
        customerPlatformFee: settings.customerPlatformFee ?? 0,
        workerCommissionPercent: settings.workerCommissionPercent ?? settings.platformCommissionPercent ?? 5,
        cooperativeWelfarePercent: settings.cooperativeWelfarePercent ?? 5,
        workerSearchRadiusKm: settings.workerSearchRadiusKm ?? 15,
        defaultLaborRatePerHour: settings.defaultLaborRatePerHour ?? 350,
        autoDispatchEnabled: settings.autoDispatchEnabled !== false,
        emergencyHotline: settings.emergencyHotline || '+91 98765 43210',
        apiKeys: settings.apiKeys || { groqApiKey: '', geminiApiKey: '', cloudinaryUrl: '', fixlySupportNumber: '1800-123-4567' }
      });
    }
  }, [settings]);

  useEffect(() => {
    if (adminUser) {
      setProfileState({
        name: adminUser.name || 'Administrator',
        email: adminUser.email || '',
        avatar: adminUser.avatar || ''
      });
    }
  }, [adminUser]);

  // Fetch Federation details on tab switch
  const fetchFederationData = async () => {
    try {
      setLoadingFederation(true);
      const res = await api.getCooperative();
      if (res && res.data) {
        const data = res.data;
        setFederationForm({
          name: data.name || 'Fixly Cooperative Federation',
          federationName: data.federationName || 'National Labour Cooperative Federation of India',
          registrationNumber: data.registrationNumber || 'FED-COOP-2026-001',
          fairWagePolicy: data.fairWagePolicy || 'Cooperative Minimum Fair Wage Guarantee Policy v1.0',
          commissionRate: data.commissionRate ?? 0.05,
          welfareContributionRate: data.welfareContributionRate ?? 0.05,
          emergencySurchargePercent: data.emergencySurchargePercent ?? 20,
          emergencySurchargeFixed: data.emergencySurchargeFixed ?? 50,
          minimumWageFloor: {
            electrical: data.minimumWageFloor?.electrical ?? 450,
            plumbing: data.minimumWageFloor?.plumbing ?? 400,
            carpentry: data.minimumWageFloor?.carpentry ?? 400,
            cleaning: data.minimumWageFloor?.cleaning ?? 300,
            painting: data.minimumWageFloor?.painting ?? 400,
            appliance: data.minimumWageFloor?.appliance ?? 450,
            gardening: data.minimumWageFloor?.gardening ?? 300,
            default: data.minimumWageFloor?.default ?? 350
          }
        });
      }
    } catch (err) {
      console.warn('Could not fetch federation details:', err);
    } finally {
      setLoadingFederation(false);
    }
  };

  // Fetch Societies list
  const fetchSocieties = async (customFilters = {}) => {
    try {
      setLoadingSocieties(true);
      const params = {};
      const querySearch = customFilters.search !== undefined ? customFilters.search : societySearch;
      const queryState = customFilters.state !== undefined ? customFilters.state : societyFilterState;
      const queryDistrict = customFilters.district !== undefined ? customFilters.district : societyFilterDistrict;

      if (querySearch && querySearch.trim()) params.search = querySearch.trim();
      if (queryState && queryState.trim()) params.state = queryState.trim();
      if (queryDistrict && queryDistrict.trim()) params.district = queryDistrict.trim();

      const res = await api.getSocieties(params);
      if (res && (res.societies || res.data)) {
        setSocieties(res.societies || res.data || []);
      }
    } catch (err) {
      console.warn('Could not fetch cooperative societies:', err);
    } finally {
      setLoadingSocieties(false);
    }
  };

  // Fetch Banners list
  const fetchBanners = async () => {
    try {
      setLoadingBanners(true);
      const res = await api.getBanners();
      if (res && res.banners) {
        setBanners(res.banners);
      }
    } catch (err) {
      console.warn('Could not fetch coupon banners:', err);
    } finally {
      setLoadingBanners(false);
    }
  };

  useEffect(() => {
    if (activeTab === 'app_version') fetchAppVersionData();
    if (activeTab === 'wage_floors') fetchFederationData();
    if (activeTab === 'societies') fetchSocieties();
    if (activeTab === 'banners') fetchBanners();
  }, [activeTab]);

  // -------------------------------------------------------------
  // HANDLERS
  // -------------------------------------------------------------
  const handleSavePlatform = async (e) => {
    e.preventDefault();
    try {
      setSavingPlatform(true);
      await updateSettings(platformForm);
    } finally {
      setSavingPlatform(false);
    }
  };

  const handleSaveFederation = async (e) => {
    e.preventDefault();
    try {
      setSavingFederation(true);
      const res = await api.updateCooperative(federationForm);
      if (res && (res.success || res.data)) {
        showToast('success', 'Cooperative Federation wage floors & policy saved successfully!');
      }
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to update cooperative federation');
    } finally {
      setSavingFederation(false);
    }
  };

  const handleCreateSociety = async (e) => {
    e.preventDefault();
    try {
      const res = await api.createSociety(newSociety);
      if (res && res.success) {
        showToast('success', `Primary Society '${newSociety.name}' registered successfully!`);
        setShowAddSocietyModal(false);
        setNewSociety({
          name: '',
          registrationNumber: '',
          state: '',
          district: '',
          wardOrArea: '',
          officeAddress: '',
          contactPhone: '',
          presidentName: '',
          secretaryName: '',
          fairWageComplianceScore: 100
        });
        fetchSocieties();
      }
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to create cooperative society');
    }
  };

  const handleAssignWorker = async (e) => {
    e.preventDefault();
    try {
      const res = await api.assignWorkerToSociety(assignWorkerData);
      if (res && res.success) {
        showToast('success', res.message || 'Worker successfully assigned to Cooperative Society!');
        setShowAssignWorkerModal(false);
        setAssignWorkerData({ workerId: '', societyId: '', societyMemberId: '' });
        fetchSocieties();
      }
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to assign worker');
    }
  };

  const handleCreateBanner = async (e) => {
    e.preventDefault();
    try {
      const payload = {
        title: newBanner.title,
        code: newBanner.code.toUpperCase().trim(),
        discount: newBanner.discount,
        discountPercent: Number(newBanner.discountPercent) || 0,
        discountAmount: Number(newBanner.discountAmount) || 0,
        description: newBanner.description,
        gradient: [newBanner.gradientStart, newBanner.gradientEnd],
        category: newBanner.category,
        targetUserRole: newBanner.targetUserRole,
        targetUserEmails: newBanner.targetUserEmails,
        minOrderValue: Number(newBanner.minOrderValue) || 0,
        maxDiscount: Number(newBanner.maxDiscount) || 500,
        usageLimit: Number(newBanner.usageLimit) || 0,
        validUntil: newBanner.validUntil || undefined,
        priority: Number(newBanner.priority) || 0,
        isActive: Boolean(newBanner.isActive),
        notifyUsers: Boolean(newBanner.notifyUsers)
      };

      const res = await api.createBanner(payload);
      if (res && res.success) {
        showToast('success', `Coupon banner '${newBanner.code}' created successfully!`);
        setShowAddBannerModal(false);
        setNewBanner({
          title: '',
          code: '',
          discount: '',
          discountPercent: 20,
          discountAmount: 0,
          description: '',
          category: 'all',
          targetUserRole: 'all',
          targetUserEmails: '',
          minOrderValue: 299,
          maxDiscount: 200,
          usageLimit: 0,
          validUntil: '',
          gradientStart: '#1E3A8A',
          gradientEnd: '#3B82F6',
          priority: 5,
          isActive: true,
          notifyUsers: true
        });
        fetchBanners();
      }
    } catch (err) {
      showToast('error', err.response?.data?.message || 'Failed to create coupon banner');
    }
  };

  const handleDeleteBanner = async (id, code) => {
    if (!window.confirm(`Are you sure you want to delete coupon '${code}'?`)) return;
    try {
      await api.deleteBanner(id);
      showToast('success', `Coupon banner '${code}' deleted`);
      fetchBanners();
    } catch (err) {
      showToast('error', 'Failed to delete banner');
    }
  };

  const handleSaveProfile = async (e) => {
    e.preventDefault();
    await updateAdminProfile(profileState);
  };

  const handleFileChange = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (evt) => {
      const dataUrl = evt.target?.result;
      setProfileState((prev) => ({ ...prev, avatar: dataUrl }));

      try {
        setIsUploadingPhoto(true);
        const uploadRes = await api.uploadImage(file);
        if (uploadRes && uploadRes.url) {
          setProfileState((prev) => ({ ...prev, avatar: uploadRes.url }));
        }
      } catch (err) {
        console.warn('Direct upload failed, keeping base64 preview:', err);
      } finally {
        setIsUploadingPhoto(false);
      }
    };
    reader.readAsDataURL(file);
  };

  // Calculations for net worker earnings preview
  const commPercent = Number(platformForm.workerCommissionPercent || 0);
  const welfarePercent = Number(platformForm.cooperativeWelfarePercent || 0);
  const workerNetPercent = Math.max(0, 100 - (commPercent + welfarePercent));

  return (
    <div style={{ padding: '0 32px 36px 32px', animation: 'fadeIn 0.2s ease', maxWidth: '1000px' }}>
      {/* Header */}
      <div style={{ marginBottom: '22px' }}>
        <h2 style={{ fontSize: '22px', fontWeight: '800', color: '#0f172a', letterSpacing: '-0.02em' }}>
          Platform Settings & Cooperative Governance
        </h2>
        <p style={{ fontSize: '13.5px', color: '#64748b', marginTop: '2px' }}>
          Configure dynamic platform fees, fair wage floors, primary cooperative societies, promotional vouchers, and admin credentials.
        </p>
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', gap: '4px', borderBottom: '1px solid #e2e8f0', marginBottom: '24px', overflowX: 'auto' }}>
        {[
          { key: 'platform', label: 'Platform & Fees', icon: Sliders },
          { key: 'app_version', label: 'App Version & Redis', icon: Smartphone },
          { key: 'wage_floors', label: 'Wage Floors & Policy', icon: DollarSign },
          { key: 'societies', label: 'Cooperative Societies', icon: Building2 },
          { key: 'banners', label: 'Promotions & Coupons', icon: Tag },
          { key: 'emergency_contacts', label: 'Emergency Contacts', icon: Phone },
          { key: 'api_keys', label: 'API Keys', icon: LinkIcon },
          { key: 'profile', label: 'Admin Identity', icon: User },
        ].map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.key;
          return (
            <button
              key={tab.key}
              type="button"
              onClick={() => {
                setActiveTab(tab.key);
                setSearchParams({ tab: tab.key });
              }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '11px 18px',
                fontSize: '13.5px',
                fontWeight: isActive ? '700' : '500',
                color: isActive ? '#15803d' : '#64748b',
                borderBottom: isActive ? '2.5px solid #15803d' : '2.5px solid transparent',
                backgroundColor: 'transparent',
                borderTop: 'none',
                borderLeft: 'none',
                borderRight: 'none',
                cursor: 'pointer',
                marginBottom: '-1px',
                whiteSpace: 'nowrap',
                transition: 'all 0.15s ease'
              }}
            >
              <Icon size={16} color={isActive ? '#15803d' : '#64748b'} />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* ========================================================= */}
      {/* TAB 1: PLATFORM & DYNAMIC FEES */}
      {/* ========================================================= */}
      {activeTab === 'platform' && (
        <form onSubmit={handleSavePlatform} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* Realtime Worker Earnings Preview Card */}
          <div style={{
            background: 'linear-gradient(135deg, #064e3b 0%, #047857 100%)',
            padding: '20px 24px',
            borderRadius: '16px',
            color: '#ffffff',
            boxShadow: '0 10px 25px -5px rgba(5, 150, 105, 0.25)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
              <div>
                <span style={{ fontSize: '11px', fontWeight: '800', letterSpacing: '0.08em', textTransform: 'uppercase', color: '#a7f3d0' }}>
                  Transparent Cooperative Economy
                </span>
                <h3 style={{ fontSize: '18px', fontWeight: '800', margin: '2px 0 0 0' }}>
                  Worker Direct Payout: {workerNetPercent}%
                </h3>
              </div>
              <div style={{ textAlign: 'right' }}>
                <span style={{ fontSize: '12px', opacity: 0.9 }}>Customer Platform Fee</span>
                <div style={{ fontSize: '18px', fontWeight: '800' }}>
                  {platformForm.customerPlatformFee === 0 ? '₹0 (Free)' : `₹${platformForm.customerPlatformFee}`}
                </div>
              </div>
            </div>

            {/* Split Bar */}
            <div style={{ display: 'flex', height: '10px', borderRadius: '5px', overflow: 'hidden', backgroundColor: 'rgba(255,255,255,0.2)', marginBottom: '10px' }}>
              <div style={{ width: `${workerNetPercent}%`, backgroundColor: '#34d399', transition: 'width 0.3s' }} title={`Worker Net: ${workerNetPercent}%`} />
              <div style={{ width: `${welfarePercent}%`, backgroundColor: '#fbbf24', transition: 'width 0.3s' }} title={`Welfare Pool: ${welfarePercent}%`} />
              <div style={{ width: `${commPercent}%`, backgroundColor: '#60a5fa', transition: 'width 0.3s' }} title={`Platform Fee: ${commPercent}%`} />
            </div>

            <div style={{ display: 'flex', gap: '16px', fontSize: '12px', flexWrap: 'wrap' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#34d399' }} />
                <span>Worker Take-Home ({workerNetPercent}%)</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#fbbf24' }} />
                <span>Cooperative Welfare ({welfarePercent}%)</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#60a5fa' }} />
                <span>Tech Maintenance Fee ({commPercent}%)</span>
              </div>
            </div>
          </div>

          {/* Core Fee Controls */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '18px' }}>
            {/* 1. Customer Platform Fee */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Customer Platform Convenience Fee (₹)
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                Flat fee added to each customer invoice. Set to <strong>₹0</strong> for zero customer markup.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a' }}>₹</span>
                <input
                  type="number"
                  min="0"
                  value={platformForm.customerPlatformFee}
                  onChange={(e) => setPlatformForm({ ...platformForm, customerPlatformFee: Number(e.target.value) || 0 })}
                  style={{ width: '120px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
                {platformForm.customerPlatformFee === 0 && (
                  <span style={{ fontSize: '11px', fontWeight: '700', color: '#15803d', backgroundColor: '#dcfce7', padding: '4px 8px', borderRadius: '6px' }}>
                    Zero-Fee Active
                  </span>
                )}
              </div>
            </div>

            {/* 2. Worker Commission Rate */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Worker Platform Commission (%)
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                Base software operating margin deducted from job earnings to fund servers. Supports 0%.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <input
                  type="number"
                  min="0"
                  max="50"
                  value={platformForm.workerCommissionPercent}
                  onChange={(e) => setPlatformForm({ ...platformForm, workerCommissionPercent: Number(e.target.value) || 0 })}
                  style={{ width: '100px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
                <span style={{ fontSize: '15px', fontWeight: '700', color: '#0f172a' }}>%</span>
              </div>
            </div>

            {/* 3. Cooperative Welfare Reserve */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Cooperative Welfare Reserve Split (%)
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                Routed into the worker's cooperative social security, accident insurance, and emergency pool.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <input
                  type="number"
                  min="0"
                  max="30"
                  value={platformForm.cooperativeWelfarePercent}
                  onChange={(e) => setPlatformForm({ ...platformForm, cooperativeWelfarePercent: Number(e.target.value) || 0 })}
                  style={{ width: '100px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
                <span style={{ fontSize: '15px', fontWeight: '700', color: '#0f172a' }}>%</span>
              </div>
            </div>

            {/* 4. Worker Search & Dispatch Radius */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Service & Worker Search Radius (km)
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                Maximum geographic perimeter in kilometers to locate workers and dispatch service requests.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <input
                  type="number"
                  min="1"
                  max="100"
                  value={platformForm.workerSearchRadiusKm}
                  onChange={(e) => setPlatformForm({ ...platformForm, workerSearchRadiusKm: Number(e.target.value) || 15 })}
                  style={{ width: '100px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
                <span style={{ fontSize: '14px', fontWeight: '700', color: '#64748b' }}>km radius</span>
              </div>
            </div>

            {/* 5. Default Labor Rate Floor */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Default Base Labor Rate Floor (₹ / booking)
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                Minimum fallback base wage floor per service booking estimate.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a' }}>₹</span>
                <input
                  type="number"
                  min="50"
                  value={platformForm.defaultLaborRatePerHour}
                  onChange={(e) => setPlatformForm({ ...platformForm, defaultLaborRatePerHour: Number(e.target.value) || 350 })}
                  style={{ width: '120px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                />
                <span style={{ fontSize: '13px', color: '#64748b' }}>/ booking</span>
              </div>
            </div>

            {/* 6. Emergency SOS Dispatch Hotline */}
            <div style={{ backgroundColor: '#ffffff', padding: '20px', borderRadius: '14px', border: '1px solid #e2e8f0' }}>
              <label style={{ display: 'block', fontSize: '13px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                Emergency SOS Dispatch Hotline
              </label>
              <p style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px' }}>
                24/7 dedicated helpline displayed on mobile client during urgent SOS triggers.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Phone size={16} color="#0f172a" />
                <input
                  type="text"
                  value={platformForm.emergencyHotline}
                  onChange={(e) => setPlatformForm({ ...platformForm, emergencyHotline: e.target.value })}
                  style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>
            </div>
          </div>

          {/* Toggle: Automated Fair Dispatch Engine */}
          <div style={{ backgroundColor: '#ffffff', padding: '20px 24px', borderRadius: '14px', border: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h4 style={{ fontSize: '14px', fontWeight: '700', color: '#0f172a', margin: '0 0 2px 0' }}>
                Automated Fair Dispatch & Rotation Engine
              </h4>
              <p style={{ fontSize: '12.5px', color: '#64748b', margin: 0 }}>
                Prevents gig monopolization by rotating booking requests equitably among verified cooperative members.
              </p>
            </div>
            <label style={{ position: 'relative', display: 'inline-block', width: '48px', height: '26px' }}>
              <input
                type="checkbox"
                checked={platformForm.autoDispatchEnabled}
                onChange={(e) => setPlatformForm({ ...platformForm, autoDispatchEnabled: e.target.checked })}
                style={{ opacity: 0, width: 0, height: 0 }}
              />
              <span style={{
                position: 'absolute', cursor: 'pointer', top: 0, left: 0, right: 0, bottom: 0,
                backgroundColor: platformForm.autoDispatchEnabled ? '#15803d' : '#cbd5e1',
                borderRadius: '34px', transition: '.3s'
              }}>
                <span style={{
                  position: 'absolute', content: '""', height: '20px', width: '20px', left: platformForm.autoDispatchEnabled ? '24px' : '3px', bottom: '3px',
                  backgroundColor: 'white', borderRadius: '50%', transition: '.3s'
                }} />
              </span>
            </label>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '6px' }}>
            <button
              type="submit"
              disabled={savingPlatform}
              style={{
                display: 'flex', alignItems: 'center', gap: '8px',
                padding: '11px 26px', backgroundColor: '#15803d', color: '#ffffff',
                borderRadius: '9px', fontSize: '14px', fontWeight: '700', border: 'none',
                cursor: 'pointer', boxShadow: '0 4px 10px rgba(21, 128, 61, 0.25)'
              }}
            >
              <Save size={16} />
              <span>{savingPlatform ? 'Saving...' : 'Save Platform Governance Settings'}</span>
            </button>
          </div>
        </form>
      )}

      {/* ========================================================= */}
      {/* TAB: MOBILE APP VERSION & REDIS CACHE GOVERNANCE */}
      {/* ========================================================= */}
      {activeTab === 'app_version' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* Card 1: App Version & Force Update Configuration */}
          <form onSubmit={handleSaveAppVersion} style={{ backgroundColor: '#ffffff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '18px', flexWrap: 'wrap', gap: '10px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: '#eef2ff' }}>
                  <Smartphone size={22} color="#4f46e5" />
                </div>
                <div>
                  <h3 style={{ fontSize: '17px', fontWeight: '800', color: '#111827', margin: 0 }}>
                    Mobile App Version & Splash Screen Engine
                  </h3>
                  <p style={{ fontSize: '12.5px', color: '#64748b', margin: '3px 0 0 0' }}>
                    Flutter mobile app calls this on splash screen. Changes synchronize instantly to Redis cache.
                  </p>
                </div>
              </div>
              <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                <span style={{ fontSize: '12px', fontWeight: '700', padding: '5px 12px', borderRadius: '20px', backgroundColor: '#e0e7ff', color: '#3730a3' }}>
                  Active API Version: {appVersionForm.apiVersion}
                </span>
                {appVersionForm.forceUpdate && (
                  <span style={{ fontSize: '11px', fontWeight: '800', padding: '5px 10px', borderRadius: '20px', backgroundColor: '#fee2e2', color: '#b91c1c' }}>
                    MANDATORY UPDATE
                  </span>
                )}
              </div>
            </div>

            {/* Version Form Grid */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px', marginBottom: '18px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Backend API Version (e.g. V1, V2)
                </label>
                <input
                  type="text"
                  required
                  value={appVersionForm.apiVersion}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, apiVersion: e.target.value })}
                  placeholder="V1"
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '14px',
                    fontWeight: '700',
                    color: '#0f172a'
                  }}
                />
                <span style={{ fontSize: '11px', color: '#64748b', marginTop: '4px', display: 'block' }}>
                  Client version is compared against this field.
                </span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  App Semantic Version (Semver)
                </label>
                <input
                  type="text"
                  value={appVersionForm.appVersion}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, appVersion: e.target.value })}
                  placeholder="1.0.0"
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '14px'
                  }}
                />
                <span style={{ fontSize: '11px', color: '#64748b', marginTop: '4px', display: 'block' }}>
                  Flutter <code>pubspec.yaml</code> version name.
                </span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Minimum Supported Version
                </label>
                <input
                  type="text"
                  value={appVersionForm.minVersion}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, minVersion: e.target.value })}
                  placeholder="V1"
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '14px'
                  }}
                />
                <span style={{ fontSize: '11px', color: '#64748b', marginTop: '4px', display: 'block' }}>
                  Versions below this are forced to update.
                </span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Target Platform Scope
                </label>
                <select
                  value={appVersionForm.platform}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, platform: e.target.value })}
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '14px',
                    backgroundColor: '#ffffff'
                  }}
                >
                  <option value="all">All Mobile Platforms</option>
                  <option value="android">Android Only</option>
                  <option value="ios">iOS Only</option>
                </select>
                <span style={{ fontSize: '11px', color: '#64748b', marginTop: '4px', display: 'block' }}>
                  Filter by OS if version differs.
                </span>
              </div>
            </div>

            {/* Force Update Checkbox Card */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '14px 18px',
                borderRadius: '10px',
                backgroundColor: appVersionForm.forceUpdate ? '#fef2f2' : '#f8fafc',
                border: appVersionForm.forceUpdate ? '1px solid #fecaca' : '1px solid #e2e8f0',
                marginBottom: '18px'
              }}
            >
              <div>
                <div style={{ fontSize: '13.5px', fontWeight: '700', color: appVersionForm.forceUpdate ? '#991b1b' : '#1e293b' }}>
                  Enforce Immediate Mandatory Update (Force Update)
                </div>
                <div style={{ fontSize: '12px', color: appVersionForm.forceUpdate ? '#b91c1c' : '#64748b', marginTop: '2px' }}>
                  When enabled, user cannot dismiss the modal on splash screen until updated.
                </div>
              </div>
              <input
                type="checkbox"
                checked={appVersionForm.forceUpdate}
                onChange={(e) => setAppVersionForm({ ...appVersionForm, forceUpdate: e.target.checked })}
                style={{ width: '22px', height: '22px', accentColor: '#4f46e5', cursor: 'pointer' }}
              />
            </div>

            {/* Modal Messaging Inputs */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '14px', marginBottom: '20px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Update Dialog Title
                </label>
                <input
                  type="text"
                  value={appVersionForm.updateTitle}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, updateTitle: e.target.value })}
                  placeholder="Update Available"
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '13.5px'
                  }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Update Notice Message (Shown to User)
                </label>
                <textarea
                  rows={2}
                  value={appVersionForm.updateMessage}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, updateMessage: e.target.value })}
                  placeholder="A new version of Fixly is available. Please update the app to continue."
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '13px',
                    resize: 'vertical'
                  }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '700', color: '#334155', marginBottom: '6px' }}>
                  Play Store / App Store / APK Download URL
                </label>
                <input
                  type="url"
                  value={appVersionForm.updateUrl}
                  onChange={(e) => setAppVersionForm({ ...appVersionForm, updateUrl: e.target.value })}
                  placeholder="https://play.google.com/store/apps/details?id=com.fixly.app"
                  style={{
                    width: '100%',
                    padding: '9px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    fontSize: '13px'
                  }}
                />
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
              <button
                type="submit"
                disabled={savingAppVersion}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  padding: '10px 22px',
                  backgroundColor: '#4f46e5',
                  color: '#ffffff',
                  border: 'none',
                  borderRadius: '8px',
                  fontSize: '13.5px',
                  fontWeight: '700',
                  cursor: savingAppVersion ? 'not-allowed' : 'pointer',
                  opacity: savingAppVersion ? 0.7 : 1,
                  boxShadow: '0 2px 4px rgba(79, 70, 229, 0.2)'
                }}
              >
                <Save size={16} />
                <span>{savingAppVersion ? 'Saving & Syncing Redis...' : 'Save App Version & Sync Redis'}</span>
              </button>
            </div>
          </form>

          {/* Card 2: Redis Memory Flush & Purge Controls */}
          <div style={{ backgroundColor: '#ffffff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '14px' }}>
              <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: '#fef3c7' }}>
                <Database size={22} color="#d97706" />
              </div>
              <div>
                <h3 style={{ fontSize: '17px', fontWeight: '800', color: '#111827', margin: 0 }}>
                  Redis Cache Invalidation & Flush Control Center
                </h3>
                <p style={{ fontSize: '12.5px', color: '#64748b', margin: '3px 0 0 0' }}>
                  Purge cached data instantly when modifying records directly in MongoDB or for staging tests.
                </p>
              </div>
            </div>

            {/* Granular Purge Buttons Grid */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))', gap: '14px', marginTop: '16px' }}>
              {/* User Cache */}
              <div style={{ padding: '16px', borderRadius: '12px', border: '1px solid #e2e8f0', backgroundColor: '#f8fafc' }}>
                <div style={{ fontSize: '13.5px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                  User & Auth Cache
                </div>
                <div style={{ fontSize: '11.5px', color: '#64748b', marginBottom: '12px' }}>
                  Deletes: <code>user:*</code>, <code>session:*</code>, <code>otp:*</code>
                </div>
                <button
                  type="button"
                  onClick={() => handleClearRedisCache('user')}
                  disabled={clearingRedis}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    backgroundColor: '#ffffff',
                    color: '#334155',
                    fontSize: '12.5px',
                    fontWeight: '600',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px',
                    cursor: clearingRedis ? 'not-allowed' : 'pointer'
                  }}
                >
                  <Trash2 size={14} color="#64748b" />
                  <span>{activeRedisAction === 'user' ? 'Clearing...' : 'Clear User Cache'}</span>
                </button>
              </div>

              {/* Booking Cache */}
              <div style={{ padding: '16px', borderRadius: '12px', border: '1px solid #e2e8f0', backgroundColor: '#f8fafc' }}>
                <div style={{ fontSize: '13.5px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                  Bookings Cache
                </div>
                <div style={{ fontSize: '11.5px', color: '#64748b', marginBottom: '12px' }}>
                  Deletes: <code>booking:*</code>, <code>scheduled:*</code>
                </div>
                <button
                  type="button"
                  onClick={() => handleClearRedisCache('booking')}
                  disabled={clearingRedis}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    backgroundColor: '#ffffff',
                    color: '#334155',
                    fontSize: '12.5px',
                    fontWeight: '600',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px',
                    cursor: clearingRedis ? 'not-allowed' : 'pointer'
                  }}
                >
                  <Trash2 size={14} color="#64748b" />
                  <span>{activeRedisAction === 'booking' ? 'Clearing...' : 'Clear Booking Cache'}</span>
                </button>
              </div>

              {/* Version Cache */}
              <div style={{ padding: '16px', borderRadius: '12px', border: '1px solid #e2e8f0', backgroundColor: '#f8fafc' }}>
                <div style={{ fontSize: '13.5px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                  App Version Cache
                </div>
                <div style={{ fontSize: '11.5px', color: '#64748b', marginBottom: '12px' }}>
                  Deletes: <code>app:version:*</code>
                </div>
                <button
                  type="button"
                  onClick={() => handleClearRedisCache('version')}
                  disabled={clearingRedis}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    backgroundColor: '#ffffff',
                    color: '#334155',
                    fontSize: '12.5px',
                    fontWeight: '600',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px',
                    cursor: clearingRedis ? 'not-allowed' : 'pointer'
                  }}
                >
                  <Trash2 size={14} color="#64748b" />
                  <span>{activeRedisAction === 'version' ? 'Clearing...' : 'Clear Version Cache'}</span>
                </button>
              </div>

              {/* Categories & Catalog */}
              <div style={{ padding: '16px', borderRadius: '12px', border: '1px solid #e2e8f0', backgroundColor: '#f8fafc' }}>
                <div style={{ fontSize: '13.5px', fontWeight: '700', color: '#1e293b', marginBottom: '4px' }}>
                  Catalog & Categories
                </div>
                <div style={{ fontSize: '11.5px', color: '#64748b', marginBottom: '12px' }}>
                  Deletes: <code>app:categories:*</code>, <code>app:home:*</code>
                </div>
                <button
                  type="button"
                  onClick={() => handleClearRedisCache('categories')}
                  disabled={clearingRedis}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid #cbd5e1',
                    backgroundColor: '#ffffff',
                    color: '#334155',
                    fontSize: '12.5px',
                    fontWeight: '600',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px',
                    cursor: clearingRedis ? 'not-allowed' : 'pointer'
                  }}
                >
                  <Trash2 size={14} color="#64748b" />
                  <span>{activeRedisAction === 'categories' ? 'Clearing...' : 'Clear Catalog Cache'}</span>
                </button>
              </div>
            </div>

            {/* Danger: Flushdb */}
            <div
              style={{
                marginTop: '18px',
                padding: '16px 20px',
                borderRadius: '12px',
                backgroundColor: '#fef2f2',
                border: '1px solid #fee2e2',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                flexWrap: 'wrap',
                gap: '12px'
              }}
            >
              <div>
                <div style={{ fontSize: '14px', fontWeight: '800', color: '#991b1b' }}>
                  Full Redis Reset (FLUSHDB)
                </div>
                <div style={{ fontSize: '12px', color: '#b91c1c', marginTop: '2px' }}>
                  Wipes all keys from the active Redis database. Normal client requests will fetch fresh data from MongoDB.
                </div>
              </div>
              <button
                type="button"
                onClick={() => handleClearRedisCache('all')}
                disabled={clearingRedis}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  padding: '9px 18px',
                  backgroundColor: '#dc2626',
                  color: '#ffffff',
                  border: 'none',
                  borderRadius: '8px',
                  fontSize: '13px',
                  fontWeight: '700',
                  cursor: clearingRedis ? 'not-allowed' : 'pointer',
                  boxShadow: '0 2px 4px rgba(220, 38, 38, 0.2)'
                }}
              >
                <Zap size={15} />
                <span>{activeRedisAction === 'all' ? 'Flushing Redis...' : 'Flush Entire Redis Cache'}</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* TAB 2: FEDERATION WAGE FLOORS & EMERGENCY SURCHARGES */}
      {/* ========================================================= */}
      {activeTab === 'wage_floors' && (
        <form onSubmit={handleSaveFederation} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ backgroundColor: '#ffffff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
              <Building2 size={20} color="#15803d" />
              <div>
                <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                  Federation Identification & Fair Wage Policy
                </h3>
                <p style={{ fontSize: '12.5px', color: '#64748b', margin: '2px 0 0 0' }}>
                  Governed by state cooperative laws to enforce statutory minimum compensation per trade.
                </p>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>
                  Apex Federation Name
                </label>
                <input
                  type="text"
                  value={federationForm.federationName}
                  onChange={(e) => setFederationForm({ ...federationForm, federationName: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13.5px' }}
                />
              </div>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>
                  Federation Registration Number
                </label>
                <input
                  type="text"
                  value={federationForm.registrationNumber}
                  onChange={(e) => setFederationForm({ ...federationForm, registrationNumber: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13.5px' }}
                />
              </div>
            </div>
          </div>

          {/* Trade Minimum Wage Floors */}
          <div style={{ backgroundColor: '#ffffff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div>
                <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                  Statutory Trade Wage Floors (₹ / hr)
                </h3>
                <p style={{ fontSize: '12.5px', color: '#64748b', margin: '2px 0 0 0' }}>
                  Under-bidding below these floors is strictly prevented by the booking pricing engine.
                </p>
              </div>
              <span style={{ fontSize: '11.5px', fontWeight: '700', color: '#15803d', backgroundColor: '#dcfce7', padding: '5px 10px', borderRadius: '6px' }}>
                Fair Wage Compliant
              </span>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '14px' }}>
              {[
                { key: 'electrical', label: 'Electrical', icon: Zap, color: '#eab308' },
                { key: 'plumbing', label: 'Plumbing', icon: Wrench, color: '#0284c7' },
                { key: 'carpentry', label: 'Carpentry', icon: Hammer, color: '#b45309' },
                { key: 'cleaning', label: 'Cleaning', icon: Sparkles, color: '#10b981' },
                { key: 'painting', label: 'Painting', icon: Flame, color: '#8b5cf6' },
                { key: 'appliance', label: 'Appliance & Tech', icon: Wrench, color: '#6366f1' },
                { key: 'gardening', label: 'Gardening', icon: Sparkles, color: '#059669' },
                { key: 'default', label: 'General / Other', icon: Sliders, color: '#64748b' },
              ].map((trade) => {
                const TradeIcon = trade.icon;
                return (
                  <div key={trade.key} style={{ padding: '14px', borderRadius: '12px', border: '1px solid #e2e8f0', backgroundColor: '#f8fafc' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                      <TradeIcon size={16} color={trade.color} />
                      <span style={{ fontSize: '13px', fontWeight: '700', color: '#1e293b' }}>{trade.label}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <span style={{ fontSize: '14px', fontWeight: '700', color: '#64748b' }}>₹</span>
                      <input
                        type="number"
                        min="100"
                        value={federationForm.minimumWageFloor?.[trade.key] ?? 350}
                        onChange={(e) => {
                          const val = Number(e.target.value) || 0;
                          setFederationForm({
                            ...federationForm,
                            minimumWageFloor: {
                              ...federationForm.minimumWageFloor,
                              [trade.key]: val
                            }
                          });
                        }}
                        style={{ width: '100%', padding: '7px 10px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '13.5px', fontWeight: '700' }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Emergency SOS Booking Surcharges */}
          <div style={{ backgroundColor: '#ffffff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
            <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a', margin: '0 0 4px 0' }}>
              Emergency SOS Urgent Job Surcharges
            </h3>
            <p style={{ fontSize: '12.5px', color: '#64748b', margin: '0 0 16px 0' }}>
              Added to immediate SOS requests to incentivize rapid worker mobilization.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>
                  Emergency Surcharge Percentage (%)
                </label>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={federationForm.emergencySurchargePercent}
                    onChange={(e) => setFederationForm({ ...federationForm, emergencySurchargePercent: Number(e.target.value) || 0 })}
                    style={{ width: '120px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                  />
                  <span style={{ fontSize: '14px', fontWeight: '700', color: '#0f172a' }}>% surcharge</span>
                </div>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>
                  Emergency Fixed Mobilization Fee (₹)
                </label>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a' }}>₹</span>
                  <input
                    type="number"
                    min="0"
                    value={federationForm.emergencySurchargeFixed}
                    onChange={(e) => setFederationForm({ ...federationForm, emergencySurchargeFixed: Number(e.target.value) || 0 })}
                    style={{ width: '120px', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px', fontWeight: '700' }}
                  />
                  <span style={{ fontSize: '12px', color: '#64748b' }}>flat bonus per callout</span>
                </div>
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
            <button
              type="submit"
              disabled={savingFederation}
              style={{
                display: 'flex', alignItems: 'center', gap: '8px',
                padding: '11px 26px', backgroundColor: '#15803d', color: '#ffffff',
                borderRadius: '9px', fontSize: '14px', fontWeight: '700', border: 'none',
                cursor: 'pointer', boxShadow: '0 4px 10px rgba(21, 128, 61, 0.25)'
              }}
            >
              <Save size={16} />
              <span>{savingFederation ? 'Saving...' : 'Save Federation Policy & Wage Floors'}</span>
            </button>
          </div>
        </form>
      )}

      {/* ========================================================= */}
      {/* TAB 3: PRIMARY COOPERATIVE SOCIETIES */}
      {/* ========================================================= */}
      {activeTab === 'societies' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap', flex: '1 1 auto' }}>
              <div style={{ position: 'relative', width: '220px' }}>
                <Search size={15} color="#94a3b8" style={{ position: 'absolute', left: '10px', top: '10px' }} />
                <input
                  type="text"
                  placeholder="Search society, district..."
                  value={societySearch}
                  onChange={(e) => setSocietySearch(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') fetchSocieties(); }}
                  style={{ width: '100%', padding: '8px 10px 8px 32px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                />
              </div>

              <div style={{ width: '320px' }}>
                <StateDistrictSelect
                  isFilter={true}
                  showLabels={false}
                  selectedState={societyFilterState}
                  selectedDistrict={societyFilterDistrict}
                  onStateChange={(st) => {
                    setSocietyFilterState(st);
                    setSocietyFilterDistrict('');
                    fetchSocieties({ state: st, district: '' });
                  }}
                  onDistrictChange={(dist) => {
                    setSocietyFilterDistrict(dist);
                    fetchSocieties({ district: dist });
                  }}
                  fieldStyle={{ padding: '8px 10px', fontSize: '12.5px' }}
                />
              </div>

              <button
                type="button"
                onClick={() => fetchSocieties()}
                style={{ padding: '8px 14px', backgroundColor: '#f1f5f9', color: '#334155', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', fontWeight: '600', cursor: 'pointer' }}
              >
                Filter
              </button>

              {(societySearch || societyFilterState || societyFilterDistrict) && (
                <button
                  type="button"
                  onClick={() => {
                    setSocietySearch('');
                    setSocietyFilterState('');
                    setSocietyFilterDistrict('');
                    fetchSocieties({ search: '', state: '', district: '' });
                  }}
                  style={{ padding: '8px 12px', backgroundColor: '#ffffff', color: '#64748b', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '12.5px', fontWeight: '600', cursor: 'pointer' }}
                >
                  Reset
                </button>
              )}
            </div>

            <div style={{ display: 'flex', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setShowAssignWorkerModal(true)}
                style={{
                  display: 'flex', alignItems: 'center', gap: '6px',
                  padding: '9px 16px', backgroundColor: '#eff6ff', color: '#1d4ed8',
                  borderRadius: '8px', border: '1px solid #bfdbfe', fontSize: '13px', fontWeight: '700', cursor: 'pointer'
                }}
              >
                <Users size={15} />
                <span>Assign Worker</span>
              </button>
              <button
                type="button"
                onClick={() => setShowAddSocietyModal(true)}
                style={{
                  display: 'flex', alignItems: 'center', gap: '6px',
                  padding: '9px 18px', backgroundColor: '#15803d', color: '#ffffff',
                  borderRadius: '8px', border: 'none', fontSize: '13px', fontWeight: '700', cursor: 'pointer'
                }}
              >
                <Plus size={16} />
                <span>Register Primary Society</span>
              </button>
            </div>
          </div>

          {/* Societies Grid */}
          {loadingSocieties ? (
            <div style={{ padding: '60px', textAlign: 'center', color: '#64748b' }}>Loading societies...</div>
          ) : societies.length === 0 ? (
            <div style={{ padding: '60px', textAlign: 'center', backgroundColor: '#ffffff', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
              <Building2 size={36} color="#94a3b8" style={{ margin: '0 auto 12px auto' }} />
              <h4 style={{ fontSize: '16px', fontWeight: '700', color: '#1e293b', margin: '0 0 4px 0' }}>No Primary Cooperative Societies Found</h4>
              <p style={{ fontSize: '13px', color: '#64748b', margin: '0 0 16px 0' }}>Register local labour contract cooperative societies to affiliate workers.</p>
              <button
                type="button"
                onClick={() => setShowAddSocietyModal(true)}
                style={{ padding: '8px 16px', backgroundColor: '#15803d', color: '#ffffff', borderRadius: '8px', border: 'none', fontSize: '13px', fontWeight: '700', cursor: 'pointer' }}
              >
                + Register First Society
              </button>
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(310px, 1fr))', gap: '18px' }}>
              {societies.map((soc) => (
                <div key={soc._id} style={{ backgroundColor: '#ffffff', borderRadius: '14px', border: '1px solid #e2e8f0', padding: '20px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                  <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '8px' }}>
                      <span style={{ fontSize: '11px', fontWeight: '800', color: '#15803d', backgroundColor: '#dcfce7', padding: '3px 8px', borderRadius: '6px' }}>
                        {soc.registrationNumber}
                      </span>
                      <span style={{ fontSize: '11.5px', fontWeight: '700', color: soc.fairWageComplianceScore >= 90 ? '#15803d' : '#d97706' }}>
                        {soc.fairWageComplianceScore}% Compliance
                      </span>
                    </div>

                    <h4 style={{ fontSize: '15px', fontWeight: '700', color: '#0f172a', margin: '0 0 6px 0' }}>
                      {soc.name}
                    </h4>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12.5px', color: '#64748b', marginBottom: '10px' }}>
                      <MapPin size={14} color="#64748b" />
                      <span>{soc.district}, {soc.state} {soc.wardOrArea ? `(${soc.wardOrArea})` : ''}</span>
                    </div>

                    {soc.presidentName && (
                      <div style={{ fontSize: '12px', color: '#475569', marginBottom: '4px' }}>
                        President: <strong>{soc.presidentName}</strong>
                      </div>
                    )}
                    {soc.contactPhone && (
                      <div style={{ fontSize: '12px', color: '#475569' }}>
                        Phone: <strong>{soc.contactPhone}</strong>
                      </div>
                    )}
                  </div>

                  <div style={{ marginTop: '16px', paddingTop: '12px', borderTop: '1px solid #f1f5f9', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: '12px', fontWeight: '600', color: '#2563eb' }}>
                      {soc.activeMembersCount || 0} Affiliated Workers
                    </span>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedSocietyForAssign(soc);
                        setAssignWorkerData({ ...assignWorkerData, societyId: soc._id });
                        setShowAssignWorkerModal(true);
                      }}
                      style={{ fontSize: '12px', fontWeight: '700', color: '#15803d', backgroundColor: '#dcfce7', border: 'none', padding: '4px 10px', borderRadius: '6px', cursor: 'pointer' }}
                    >
                      + Add Member
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* MODAL: Register New Primary Society */}
          {showAddSocietyModal && (
            <div style={{ position: 'fixed', inset: 0, backgroundColor: 'rgba(0,0,0,0.5)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
              <div style={{ backgroundColor: '#ffffff', borderRadius: '16px', width: '100%', maxWidth: '540px', padding: '24px', maxHeight: '90vh', overflowY: 'auto' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <h3 style={{ fontSize: '17px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                    Register Primary Labour Cooperative Society
                  </h3>
                  <button type="button" onClick={() => setShowAddSocietyModal(false)} style={{ background: 'none', border: 'none', cursor: 'pointer' }}>
                    <X size={18} color="#64748b" />
                  </button>
                </div>

                <form onSubmit={handleCreateSociety} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Society Name *</label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. South Delhi Technicians Cooperative Society"
                      value={newSociety.name}
                      onChange={(e) => setNewSociety({ ...newSociety, name: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Registration Number *</label>
                      <input
                        type="text"
                        required
                        placeholder="e.g. SOC-DL-2026-104"
                        value={newSociety.registrationNumber}
                        onChange={(e) => setNewSociety({ ...newSociety, registrationNumber: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Contact Phone</label>
                      <input
                        type="text"
                        placeholder="+91 98765 43210"
                        value={newSociety.contactPhone}
                        onChange={(e) => setNewSociety({ ...newSociety, contactPhone: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                  </div>

                  <StateDistrictSelect
                    selectedState={newSociety.state}
                    selectedDistrict={newSociety.district}
                    onStateChange={(st) => setNewSociety({ ...newSociety, state: st, district: '' })}
                    onDistrictChange={(dist) => setNewSociety({ ...newSociety, district: dist })}
                  />

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Ward or Area Coverage</label>
                    <input
                      type="text"
                      placeholder="e.g. Saket, Malviya Nagar & Hauz Khas"
                      value={newSociety.wardOrArea}
                      onChange={(e) => setNewSociety({ ...newSociety, wardOrArea: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>President Name</label>
                      <input
                        type="text"
                        placeholder="e.g. Harish Chandra"
                        value={newSociety.presidentName}
                        onChange={(e) => setNewSociety({ ...newSociety, presidentName: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Secretary Name</label>
                      <input
                        type="text"
                        placeholder="e.g. Suresh Pal"
                        value={newSociety.secretaryName}
                        onChange={(e) => setNewSociety({ ...newSociety, secretaryName: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                    <button
                      type="button"
                      onClick={() => setShowAddSocietyModal(false)}
                      style={{ padding: '8px 16px', backgroundColor: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '8px', fontSize: '13px', fontWeight: '600', cursor: 'pointer' }}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      style={{ padding: '8px 20px', backgroundColor: '#15803d', color: '#ffffff', border: 'none', borderRadius: '8px', fontSize: '13px', fontWeight: '700', cursor: 'pointer' }}
                    >
                      Save Society
                    </button>
                  </div>
                </form>
              </div>
            </div>
          )}

          {/* MODAL: Assign Worker to Society */}
          {showAssignWorkerModal && (
            <div style={{ position: 'fixed', inset: 0, backgroundColor: 'rgba(0,0,0,0.5)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
              <div style={{ backgroundColor: '#ffffff', borderRadius: '16px', width: '100%', maxWidth: '480px', padding: '24px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <h3 style={{ fontSize: '17px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                    Assign Worker to Cooperative Society
                  </h3>
                  <button type="button" onClick={() => setShowAssignWorkerModal(false)} style={{ background: 'none', border: 'none', cursor: 'pointer' }}>
                    <X size={18} color="#64748b" />
                  </button>
                </div>

                <form onSubmit={handleAssignWorker} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Worker MongoDB ID *</label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. 64f1bc..."
                      value={assignWorkerData.workerId}
                      onChange={(e) => setAssignWorkerData({ ...assignWorkerData, workerId: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Select Cooperative Society *</label>
                    <select
                      required
                      value={assignWorkerData.societyId}
                      onChange={(e) => setAssignWorkerData({ ...assignWorkerData, societyId: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', backgroundColor: '#ffffff' }}
                    >
                      <option value="">-- Choose Society --</option>
                      {societies.map((s) => (
                        <option key={s._id} value={s._id}>{s.name} ({s.district})</option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Society Member ID (Optional)</label>
                    <input
                      type="text"
                      placeholder="e.g. MEM-SD-2026-0042 (Auto-generated if blank)"
                      value={assignWorkerData.societyMemberId}
                      onChange={(e) => setAssignWorkerData({ ...assignWorkerData, societyMemberId: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                    <button
                      type="button"
                      onClick={() => setShowAssignWorkerModal(false)}
                      style={{ padding: '8px 16px', backgroundColor: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '8px', fontSize: '13px', fontWeight: '600', cursor: 'pointer' }}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      style={{ padding: '8px 20px', backgroundColor: '#15803d', color: '#ffffff', border: 'none', borderRadius: '8px', fontSize: '13px', fontWeight: '700', cursor: 'pointer' }}
                    >
                      Confirm Assignment
                    </button>
                  </div>
                </form>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ========================================================= */}
      {/* TAB 4: PROMOTIONAL COUPON BANNERS */}
      {/* ========================================================= */}
      {activeTab === 'banners' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                Promotional Coupon Banners (MongoDB)
              </h3>
              <p style={{ fontSize: '12.5px', color: '#64748b', margin: '2px 0 0 0' }}>
                Manage live mobile home banners, discounts, category tags, and priority ordering.
              </p>
            </div>
            <button
              type="button"
              onClick={() => setShowAddBannerModal(true)}
              style={{
                display: 'flex', alignItems: 'center', gap: '6px',
                padding: '9px 18px', backgroundColor: '#15803d', color: '#ffffff',
                borderRadius: '8px', border: 'none', fontSize: '13px', fontWeight: '700', cursor: 'pointer'
              }}
            >
              <Plus size={16} />
              <span>Create Coupon Banner</span>
            </button>
          </div>

          {loadingBanners ? (
            <div style={{ padding: '60px', textAlign: 'center', color: '#64748b' }}>Loading coupon banners...</div>
          ) : banners.length === 0 ? (
            <div style={{ padding: '60px', textAlign: 'center', backgroundColor: '#ffffff', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
              <Tag size={36} color="#94a3b8" style={{ margin: '0 auto 12px auto' }} />
              <h4 style={{ fontSize: '16px', fontWeight: '700', color: '#1e293b', margin: '0 0 4px 0' }}>No Promotional Banners Found</h4>
              <p style={{ fontSize: '13px', color: '#64748b', margin: '0 0 16px 0' }}>Create discount coupons to display on the mobile app home screen.</p>
              <button
                type="button"
                onClick={() => setShowAddBannerModal(true)}
                style={{ padding: '8px 16px', backgroundColor: '#15803d', color: '#ffffff', borderRadius: '8px', border: 'none', fontSize: '13px', fontWeight: '700', cursor: 'pointer' }}
              >
                + Create First Banner
              </button>
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '18px' }}>
              {banners.map((b) => {
                const gradStart = b.gradient?.[0] || '#1E3A8A';
                const gradEnd = b.gradient?.[1] || '#3B82F6';
                return (
                  <div key={b._id} style={{
                    borderRadius: '16px',
                    overflow: 'hidden',
                    backgroundColor: '#ffffff',
                    border: '1px solid #e2e8f0',
                    display: 'flex',
                    flexDirection: 'column',
                    boxShadow: '0 4px 6px -1px rgba(0,0,0,0.05)'
                  }}>
                    {/* Visual Voucher Preview */}
                    <div style={{
                      background: `linear-gradient(135deg, ${gradStart} 0%, ${gradEnd} 100%)`,
                      padding: '18px',
                      color: '#ffffff',
                      position: 'relative'
                    }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                        <span style={{ fontSize: '11px', fontWeight: '800', backgroundColor: 'rgba(255,255,255,0.25)', padding: '3px 8px', borderRadius: '6px' }}>
                          {b.category?.toUpperCase()}
                        </span>
                        <span style={{ fontSize: '14px', fontWeight: '900' }}>
                          {b.discount}
                        </span>
                      </div>
                      <h4 style={{ fontSize: '15px', fontWeight: '800', margin: '0 0 6px 0', lineHeight: 1.3 }}>
                        {b.title}
                      </h4>
                      <p style={{ fontSize: '12px', opacity: 0.9, margin: 0, lineHeight: 1.4 }}>
                        {b.description}
                      </p>
                    </div>

                    {/* Voucher Details & Controls */}
                    <div style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                          <span style={{ fontSize: '11px', color: '#64748b' }}>COUPON CODE</span>
                          <div style={{ fontSize: '15px', fontWeight: '900', color: '#0f172a', letterSpacing: '0.05em' }}>
                            {b.code}
                          </div>
                        </div>
                        <div style={{ textAlign: 'right' }}>
                          <span style={{ fontSize: '11px', color: '#64748b' }}>MIN ORDER</span>
                          <div style={{ fontSize: '13px', fontWeight: '700', color: '#1e293b' }}>
                            ₹{b.minOrderValue || 0}
                          </div>
                        </div>
                      </div>
                      {(b.targetUserEmails?.length > 0 || b.targetUserIds?.length > 0) && (
                        <div style={{ fontSize: '11px', color: '#7c3aed', fontWeight: 600 }}>
                          User-specific · {b.targetUserIds?.length || b.targetUserEmails?.length} user(s) assigned
                        </div>
                      )}
                      <div style={{ fontSize: '11px', color: '#64748b' }}>
                        Role: {b.targetUserRole || 'all'} · Used: {b.usedCount || 0}
                        {b.usageLimit ? ` / ${b.usageLimit}` : ''}
                        {b.usedByUserIds?.length > 0 ? ` · Locked: ${b.usedByUserIds.length}` : ''}
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '10px', borderTop: '1px solid #f1f5f9' }}>
                        <span style={{ fontSize: '11.5px', color: b.isActive ? '#15803d' : '#94a3b8', fontWeight: '700' }}>
                          {b.isActive ? '● Active in App' : '○ Inactive'}
                        </span>
                        <div style={{ display: 'flex', gap: '10px' }}>
                          <button
                            type="button"
                            onClick={async () => {
                              const emails = window.prompt(
                                'Re-assign coupon to users (comma-separated emails).\nClears lock so they can use again:',
                                (b.targetUserEmails || []).join(', ')
                              );
                              if (emails === null) return;
                              try {
                                await api.updateBanner(b._id, { targetUserEmails: emails });
                                showToast('success', `Coupon ${b.code} re-assigned`);
                                fetchBanners();
                              } catch (err) {
                                showToast('error', err.response?.data?.message || 'Re-assign failed');
                              }
                            }}
                            style={{
                              background: 'none', border: 'none', color: '#0369a1',
                              fontSize: '12px', fontWeight: '700', cursor: 'pointer'
                            }}
                          >
                            Re-assign
                          </button>
                          <button
                          type="button"
                          onClick={() => handleDeleteBanner(b._id, b.code)}
                          style={{
                            display: 'flex', alignItems: 'center', gap: '4px',
                            background: 'none', border: 'none', color: '#ef4444',
                            fontSize: '12px', fontWeight: '700', cursor: 'pointer'
                          }}
                        >
                          <Trash2 size={13} />
                          <span>Delete</span>
                        </button>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* MODAL: Create Coupon Banner */}
          {showAddBannerModal && (
            <div style={{ position: 'fixed', inset: 0, backgroundColor: 'rgba(0,0,0,0.5)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
              <div style={{ backgroundColor: '#ffffff', borderRadius: '16px', width: '100%', maxWidth: '500px', padding: '24px', maxHeight: '90vh', overflowY: 'auto' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <h3 style={{ fontSize: '17px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                    Create Promotional Coupon Banner
                  </h3>
                  <button type="button" onClick={() => setShowAddBannerModal(false)} style={{ background: 'none', border: 'none', cursor: 'pointer' }}>
                    <X size={18} color="#64748b" />
                  </button>
                </div>

                <form onSubmit={handleCreateBanner} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Banner Title *</label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. Flat 50% Off First Booking"
                      value={newBanner.title}
                      onChange={(e) => setNewBanner({ ...newBanner, title: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Coupon Code *</label>
                      <input
                        type="text"
                        required
                        placeholder="e.g. FIXLY50"
                        value={newBanner.code}
                        onChange={(e) => setNewBanner({ ...newBanner, code: e.target.value.toUpperCase() })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', fontWeight: '700', textTransform: 'uppercase' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Discount Tag *</label>
                      <input
                        type="text"
                        required
                        placeholder="e.g. 50% OFF or ₹100 FLAT"
                        value={newBanner.discount}
                        onChange={(e) => setNewBanner({ ...newBanner, discount: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Short Description</label>
                    <textarea
                      rows={2}
                      placeholder="Get up to ₹150 off on your first home service"
                      value={newBanner.description}
                      onChange={(e) => setNewBanner({ ...newBanner, description: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', fontFamily: 'inherit' }}
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Target Audience</label>
                      <select
                        value={newBanner.targetUserRole}
                        onChange={(e) => setNewBanner({ ...newBanner, targetUserRole: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', backgroundColor: '#ffffff' }}
                      >
                        <option value="all">All Users (Customers & Workers)</option>
                        <option value="customer">Customers Only</option>
                        <option value="worker">Workers Only</option>
                        <option value="new_user">New Customers (≤30 days)</option>
                      </select>
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Target Category</label>
                      <select
                        value={newBanner.category}
                        onChange={(e) => setNewBanner({ ...newBanner, category: e.target.value })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', backgroundColor: '#ffffff' }}
                      >
                        <option value="all">All Categories</option>
                        <option value="plumber">Plumbing</option>
                        <option value="electrician">Electrical</option>
                        <option value="technician">Technician / AC</option>
                        <option value="cleaning">Cleaning</option>
                        <option value="carpenter">Carpentry</option>
                      </select>
                    </div>
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>
                      Specific users (emails, optional)
                    </label>
                    <input
                      type="text"
                      placeholder="user1@email.com, user2@email.com — leave empty for filter-based"
                      value={newBanner.targetUserEmails}
                      onChange={(e) => setNewBanner({ ...newBanner, targetUserEmails: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                    <p style={{ fontSize: '11px', color: '#64748b', margin: '4px 0 0 0' }}>
                      If set, only these users can use the coupon. After they redeem once, access is locked until you Re-assign or create a new code.
                    </p>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>% Discount</label>
                      <input
                        type="number"
                        min="0"
                        max="100"
                        value={newBanner.discountPercent}
                        onChange={(e) => setNewBanner({ ...newBanner, discountPercent: Number(e.target.value) || 0 })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Flat ₹ Discount</label>
                      <input
                        type="number"
                        min="0"
                        value={newBanner.discountAmount}
                        onChange={(e) => setNewBanner({ ...newBanner, discountAmount: Number(e.target.value) || 0 })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Usage limit (0=∞)</label>
                      <input
                        type="number"
                        min="0"
                        value={newBanner.usageLimit}
                        onChange={(e) => setNewBanner({ ...newBanner, usageLimit: Number(e.target.value) || 0 })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Valid until</label>
                    <input
                      type="date"
                      value={newBanner.validUntil}
                      onChange={(e) => setNewBanner({ ...newBanner, validUntil: e.target.value })}
                      style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Min Order Value (₹)</label>
                      <input
                        type="number"
                        min="0"
                        value={newBanner.minOrderValue}
                        onChange={(e) => setNewBanner({ ...newBanner, minOrderValue: Number(e.target.value) || 0 })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Max Discount (₹)</label>
                      <input
                        type="number"
                        min="0"
                        value={newBanner.maxDiscount}
                        onChange={(e) => setNewBanner({ ...newBanner, maxDiscount: Number(e.target.value) || 500 })}
                        style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                      />
                    </div>
                  </div>

                  <div style={{ padding: '12px 14px', borderRadius: '8px', backgroundColor: '#f0fdf4', border: '1px solid #bbf7d0', display: 'flex', alignItems: 'flex-start', gap: '10px' }}>
                    <input
                      type="checkbox"
                      id="notifyUsersCheckbox"
                      checked={newBanner.notifyUsers}
                      onChange={(e) => setNewBanner({ ...newBanner, notifyUsers: e.target.checked })}
                      style={{ marginTop: '3px', cursor: 'pointer', accentColor: '#15803d' }}
                    />
                    <label htmlFor="notifyUsersCheckbox" style={{ fontSize: '12.5px', color: '#166534', cursor: 'pointer', lineHeight: '1.4' }}>
                      <strong>Dispatch Push & In-App Notification</strong><br />
                      Send promotion to users who have <em>"Discounts & Updates"</em> notification enabled. Users who turned OFF this toggle will NOT receive it.
                    </label>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Gradient Start</label>
                      <input
                        type="color"
                        value={newBanner.gradientStart}
                        onChange={(e) => setNewBanner({ ...newBanner, gradientStart: e.target.value })}
                        style={{ width: '100%', height: '38px', borderRadius: '8px', border: '1px solid #cbd5e1', cursor: 'pointer' }}
                      />
                    </div>
                    <div>
                      <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '4px' }}>Gradient End</label>
                      <input
                        type="color"
                        value={newBanner.gradientEnd}
                        onChange={(e) => setNewBanner({ ...newBanner, gradientEnd: e.target.value })}
                        style={{ width: '100%', height: '38px', borderRadius: '8px', border: '1px solid #cbd5e1', cursor: 'pointer' }}
                      />
                    </div>
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                    <button
                      type="button"
                      onClick={() => setShowAddBannerModal(false)}
                      style={{ padding: '8px 16px', backgroundColor: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '8px', fontSize: '13px', fontWeight: '600', cursor: 'pointer' }}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      style={{ padding: '8px 20px', backgroundColor: '#15803d', color: '#ffffff', border: 'none', borderRadius: '8px', fontSize: '13px', fontWeight: '700', cursor: 'pointer' }}
                    >
                      Save Banner
                    </button>
                  </div>
                </form>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ========================================================= */}
      
      {/* ========================================================= */}
      {/* TAB: API KEYS & INTEGRATIONS */}
      {/* ========================================================= */}
      {activeTab === 'api_keys' && (
        <form onSubmit={handleSavePlatform} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ backgroundColor: '#fff', padding: '24px', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
            <h3 style={{ fontSize: '18px', fontWeight: '700', marginBottom: '8px' }}>API Keys & Third-Party Integrations</h3>
            <div style={{ backgroundColor: '#fef2f2', border: '1px solid #fecaca', padding: '12px', borderRadius: '8px', marginBottom: '20px' }}>
              <p style={{ color: '#b91c1c', fontSize: '13px', margin: 0 }}>
                <strong>Note:</strong> Changes to API keys may require a server restart to take full effect in backend AI services.
              </p>
            </div>
            
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '13px', fontWeight: '600', marginBottom: '4px' }}>Groq API Key (Llama 3)</label>
                <input
                  type="password"
                  value={platformForm.apiKeys?.groqApiKey || ''}
                  onChange={(e) => setPlatformForm({ ...platformForm, apiKeys: { ...platformForm.apiKeys, groqApiKey: e.target.value } })}
                  placeholder="gsk_..."
                  style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #cbd5e1' }}
                />
              </div>
              
              <div>
                <label style={{ display: 'block', fontSize: '13px', fontWeight: '600', marginBottom: '4px' }}>Gemini API Key (Vision)</label>
                <input
                  type="password"
                  value={platformForm.apiKeys?.geminiApiKey || ''}
                  onChange={(e) => setPlatformForm({ ...platformForm, apiKeys: { ...platformForm.apiKeys, geminiApiKey: e.target.value } })}
                  placeholder="AIza..."
                  style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #cbd5e1' }}
                />
              </div>
              
              <div>
                <label style={{ display: 'block', fontSize: '13px', fontWeight: '600', marginBottom: '4px' }}>Cloudinary URL</label>
                <input
                  type="text"
                  value={platformForm.apiKeys?.cloudinaryUrl || ''}
                  onChange={(e) => setPlatformForm({ ...platformForm, apiKeys: { ...platformForm.apiKeys, cloudinaryUrl: e.target.value } })}
                  placeholder="cloudinary://..."
                  style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #cbd5e1' }}
                />
              </div>
              
              <div>
                <label style={{ display: 'block', fontSize: '13px', fontWeight: '600', marginBottom: '4px' }}>Fixly Support Number</label>
                <input
                  type="text"
                  value={platformForm.apiKeys?.fixlySupportNumber || ''}
                  onChange={(e) => setPlatformForm({ ...platformForm, apiKeys: { ...platformForm.apiKeys, fixlySupportNumber: e.target.value } })}
                  placeholder="1800-..."
                  style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #cbd5e1' }}
                />
              </div>
            </div>
            
            <div style={{ marginTop: '20px', display: 'flex', justifyContent: 'flex-end' }}>
              <button
                type="submit"
                disabled={savingPlatform}
                style={{
                  padding: '10px 20px', backgroundColor: '#15803d', color: 'white', borderRadius: '8px', fontWeight: '600', border: 'none', cursor: 'pointer'
                }}
              >
                {savingPlatform ? 'Saving...' : 'Save API Keys'}
              </button>
            </div>
          </div>
        </form>
      )}
      
{/* TAB 6: ADMIN IDENTITY & PROFILE */}
      {/* ========================================================= */}
      {activeTab === 'profile' && (
        <form onSubmit={handleSaveProfile} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div style={{ backgroundColor: '#ffffff', padding: '26px 28px', borderRadius: '16px', border: '1px solid #e2e8f0' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px', borderBottom: '1px solid #f1f5f9', paddingBottom: '14px' }}>
              <div>
                <h3 style={{ fontSize: '16px', fontWeight: '700', color: '#0f172a', margin: 0 }}>
                  Administrator Identity & Avatar
                </h3>
                <p style={{ fontSize: '12.5px', color: '#64748b', margin: '2px 0 0 0' }}>
                  Your official identity displayed across audits, activity logs, and cooperative decrees.
                </p>
              </div>
              <span style={{ fontSize: '11px', fontWeight: '700', color: '#15803d', backgroundColor: '#dcfce7', padding: '4px 10px', borderRadius: '6px' }}>
                Active Session
              </span>
            </div>

            {/* Avatar Row */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '20px', marginBottom: '24px' }}>
              <div style={{ position: 'relative' }}>
                <Avatar
                  src={profileState.avatar}
                  name={profileState.name}
                  size="xl"
                  style={{ width: '80px', height: '80px', fontSize: '26px', border: '3px solid #15803d' }}
                />
                {isUploadingPhoto && (
                  <div style={{ position: 'absolute', inset: 0, backgroundColor: 'rgba(0,0,0,0.4)', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: '11px' }}>
                    ...
                  </div>
                )}
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                  <input
                    type="file"
                    ref={fileInputRef}
                    onChange={handleFileChange}
                    accept="image/*"
                    style={{ display: 'none' }}
                  />
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    disabled={isUploadingPhoto}
                    style={{
                      display: 'flex', alignItems: 'center', gap: '6px',
                      padding: '7px 14px', backgroundColor: '#eff6ff', color: '#2563eb',
                      border: '1px solid #bfdbfe', borderRadius: '7px', fontSize: '12.5px', fontWeight: '600', cursor: 'pointer'
                    }}
                  >
                    <Camera size={14} />
                    <span>{isUploadingPhoto ? 'Uploading...' : 'Upload Avatar'}</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setShowUrlInput(!showUrlInput)}
                    style={{
                      display: 'flex', alignItems: 'center', gap: '6px',
                      padding: '7px 14px', backgroundColor: '#f8fafc', color: '#475569',
                      border: '1px solid #cbd5e1', borderRadius: '7px', fontSize: '12.5px', fontWeight: '600', cursor: 'pointer'
                    }}
                  >
                    <LinkIcon size={14} />
                    <span>Image URL</span>
                  </button>

                  {profileState.avatar && (
                    <button
                      type="button"
                      onClick={() => setProfileState({ ...profileState, avatar: '' })}
                      style={{
                        display: 'flex', alignItems: 'center', gap: '4px',
                        padding: '7px 10px', backgroundColor: '#fef2f2', color: '#dc2626',
                        border: '1px solid #fecaca', borderRadius: '7px', fontSize: '12px', cursor: 'pointer'
                      }}
                    >
                      <Trash2 size={13} />
                      <span>Remove</span>
                    </button>
                  )}
                </div>

                {showUrlInput && (
                  <input
                    type="text"
                    placeholder="Paste image URL (https://...)"
                    value={profileState.avatar}
                    onChange={(e) => setProfileState({ ...profileState, avatar: e.target.value })}
                    style={{ width: '320px', padding: '7px 12px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px' }}
                  />
                )}
              </div>
            </div>

            {/* Inputs */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>Administrator Name</label>
                <input
                  type="text"
                  required
                  value={profileState.name}
                  onChange={(e) => setProfileState({ ...profileState, name: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13.5px' }}
                />
              </div>
              <div>
                <label style={{ display: 'block', fontSize: '12.5px', fontWeight: '600', color: '#334155', marginBottom: '5px' }}>Administrator Official Email</label>
                <input
                  type="email"
                  required
                  value={profileState.email}
                  onChange={(e) => setProfileState({ ...profileState, email: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13.5px' }}
                />
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '20px' }}>
              <button
                type="submit"
                style={{
                  display: 'flex', alignItems: 'center', gap: '6px',
                  padding: '10px 24px', backgroundColor: '#15803d', color: '#ffffff',
                  borderRadius: '8px', fontSize: '13.5px', fontWeight: '700', border: 'none', cursor: 'pointer'
                }}
              >
                <Save size={15} />
                <span>Save Profile Changes</span>
              </button>
            </div>
          </div>
        </form>
      )}
    </div>
  );
}
