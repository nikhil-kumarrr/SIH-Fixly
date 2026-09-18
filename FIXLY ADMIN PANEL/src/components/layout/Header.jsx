import React, { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Bell,
  ChevronDown,
  Calendar,
  Search,
  Menu,
  Check,
  User,
  Shield,
  LogOut,
  SlidersHorizontal,
  Globe,
  X,
  CalendarCheck,
  Wrench,
  Users,
  UserCheck
} from 'lucide-react';
import { useLanguage } from '../../context/LanguageContext';
import { useApp } from '../../context/AppContext';
import Avatar from '../common/Avatar';

export default function Header({ onOpenMobileMenu }) {
  const navigate = useNavigate();
  const { t, language, setLanguage } = useLanguage();
  const {
    workers,
    customers,
    bookings,
    services,
    notifications,
    markAllNotificationsRead,
    selectedDateRange,
    setSelectedDateRange,
    logoutAdmin,
    adminUser,
  } = useApp();

  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isDateOpen, setIsDateOpen] = useState(false);
  const [isLangOpen, setIsLangOpen] = useState(false);
  const [isNotifOpen, setIsNotifOpen] = useState(false);
  const [isProfileOpen, setIsProfileOpen] = useState(false);

  const searchRef = useRef(null);

  // Global search matching
  const matchingWorkers = searchQuery.trim()
    ? workers.filter((w) =>
        w.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        w.service.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : [];

  const matchingCustomers = searchQuery.trim()
    ? customers.filter((c) =>
        c.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        c.phone.includes(searchQuery)
      )
    : [];

  const matchingBookings = searchQuery.trim()
    ? bookings.filter((b) =>
        b.id.toLowerCase().includes(searchQuery.toLowerCase()) ||
        b.service.toLowerCase().includes(searchQuery.toLowerCase()) ||
        b.customer.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : [];

  const matchingServices = searchQuery.trim()
    ? services.filter((s) =>
        s.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        s.category.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : [];

  const hasResults =
    matchingWorkers.length > 0 ||
    matchingCustomers.length > 0 ||
    matchingBookings.length > 0 ||
    matchingServices.length > 0;

  // Keyboard shortcut Ctrl+K
  useEffect(() => {
    const handleKeyDown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        searchRef.current?.focus();
        setIsSearchOpen(true);
      }
      if (e.key === 'Escape') {
        setIsSearchOpen(false);
        setIsDateOpen(false);
        setIsLangOpen(false);
        setIsNotifOpen(false);
        setIsProfileOpen(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const unreadNotifs = notifications.filter((n) => n.unread);

  return (
    <header
      className="admin-header"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '20px 32px 14px 32px',
        gap: '16px',
        flexWrap: 'wrap',
        position: 'relative',
        zIndex: 30,
      }}
    >
      {/* Left: Greeting & Subtitle */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
        {/* Mobile menu hamburger */}
        <button
          onClick={onOpenMobileMenu}
          className="mobile-only"
          style={{
            display: 'none',
            padding: '8px',
            borderRadius: '10px',
            backgroundColor: '#ffffff',
            border: '1px solid var(--border-light)',
            color: '#334155',
          }}
        >
          <Menu size={20} />
        </button>

        <div>
          <h1
            className="admin-header-title"
            style={{
              fontSize: '23px',
              fontWeight: '700',
              color: 'var(--primary-brand)',
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              letterSpacing: '-0.4px',
            }}
          >
            {t('welcomeBack')} <span style={{ fontSize: '22px' }}>👋</span>
          </h1>
        </div>
      </div>

      {/* Right Controls */}
      <div
        className="admin-header-controls"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          flexWrap: 'wrap',
        }}
      >
        {/* Working Global Search Input with instant dropdown */}
        <div className="admin-search-container" style={{ position: 'relative' }}>
          <div
            className="admin-search-box"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '7px 14px',
              backgroundColor: '#ffffff',
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-pill)',
              color: '#64748b',
              fontSize: '13px',
              boxShadow: 'var(--shadow-card)',
              width: '260px',
            }}
          >
            <Search size={15} color="#1e7e45" />
            <input
              ref={searchRef}
              type="text"
              placeholder="Search anything... (⌘K)"
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                setIsSearchOpen(true);
              }}
              onFocus={() => setIsSearchOpen(true)}
              style={{
                border: 'none',
                outline: 'none',
                backgroundColor: 'transparent',
                width: '100%',
                fontSize: '12.5px',
                color: '#1e293b',
              }}
            />
            {searchQuery && (
              <button
                onClick={() => {
                  setSearchQuery('');
                  setIsSearchOpen(false);
                }}
                style={{ color: '#94a3b8' }}
              >
                <X size={14} />
              </button>
            )}
          </div>

          {/* Search Results Dropdown */}
          {isSearchOpen && searchQuery.trim() && (
            <div
              style={{
                position: 'absolute',
                top: 'calc(100% + 8px)',
                left: 0,
                width: '380px',
                backgroundColor: '#ffffff',
                borderRadius: '14px',
                border: '1px solid var(--border-light)',
                boxShadow: '0 15px 35px rgba(0,0,0,0.12)',
                maxHeight: '380px',
                overflowY: 'auto',
                padding: '8px',
                zIndex: 60,
                animation: 'fadeIn 0.15s ease',
              }}
            >
              {!hasResults && (
                <div style={{ padding: '16px', textAlign: 'center', fontSize: '13px', color: '#94a3b8' }}>
                  No results found for "{searchQuery}"
                </div>
              )}

              {/* Bookings */}
              {matchingBookings.length > 0 && (
                <div style={{ marginBottom: '8px' }}>
                  <div style={{ fontSize: '11px', fontWeight: '700', color: '#94a3b8', padding: '4px 8px', textTransform: 'uppercase' }}>
                    Bookings ({matchingBookings.length})
                  </div>
                  {matchingBookings.slice(0, 3).map((b) => (
                    <div
                      key={b.id}
                      onClick={() => {
                        navigate('/bookings');
                        setIsSearchOpen(false);
                        setSearchQuery('');
                      }}
                      style={{
                        padding: '6px 10px',
                        borderRadius: '8px',
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        fontSize: '12.5px',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f1f8f3')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <CalendarCheck size={14} color="#1e7e45" />
                        <div>
                          <strong style={{ color: 'var(--text-link)' }}>{b.id}</strong> — {b.customer} ({b.service})
                        </div>
                      </div>
                      <span style={{ fontSize: '11px', color: '#15803d', fontWeight: '600' }}>{b.status}</span>
                    </div>
                  ))}
                </div>
              )}

              {/* Workers */}
              {matchingWorkers.length > 0 && (
                <div style={{ marginBottom: '8px' }}>
                  <div style={{ fontSize: '11px', fontWeight: '700', color: '#94a3b8', padding: '4px 8px', textTransform: 'uppercase' }}>
                    Workers ({matchingWorkers.length})
                  </div>
                  {matchingWorkers.slice(0, 3).map((w) => (
                    <div
                      key={w.id}
                      onClick={() => {
                        navigate(`/workers/${w.id}`);
                        setIsSearchOpen(false);
                        setSearchQuery('');
                      }}
                      style={{
                        padding: '6px 10px',
                        borderRadius: '8px',
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        fontSize: '12.5px',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f1f8f3')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <Users size={14} color="#0284c7" />
                        <div>
                          <strong>{w.name}</strong> • {w.service}
                        </div>
                      </div>
                      <span style={{ fontSize: '11px', color: '#64748b' }}>⭐ {w.rating}</span>
                    </div>
                  ))}
                </div>
              )}

              {/* Customers */}
              {matchingCustomers.length > 0 && (
                <div style={{ marginBottom: '8px' }}>
                  <div style={{ fontSize: '11px', fontWeight: '700', color: '#94a3b8', padding: '4px 8px', textTransform: 'uppercase' }}>
                    Customers ({matchingCustomers.length})
                  </div>
                  {matchingCustomers.slice(0, 3).map((c) => (
                    <div
                      key={c.id}
                      onClick={() => {
                        navigate(`/customers/${c.id}`);
                        setIsSearchOpen(false);
                        setSearchQuery('');
                      }}
                      style={{
                        padding: '6px 10px',
                        borderRadius: '8px',
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        fontSize: '12.5px',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f1f8f3')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <UserCheck size={14} color="#15803d" />
                        <div>
                          <strong>{c.name}</strong> ({c.phone})
                        </div>
                      </div>
                      <span style={{ fontSize: '11px', color: '#15803d', fontWeight: '600' }}>{c.totalSpent}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Multilingual Selector */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setIsLangOpen(!isLangOpen)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '7px 12px',
              backgroundColor: '#ffffff',
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-pill)',
              fontSize: '12.5px',
              fontWeight: '600',
              color: '#334155',
              boxShadow: 'var(--shadow-card)',
            }}
          >
            <Globe size={14} color="#1e7e45" />
            <span>{language === 'en' ? 'English' : 'हिंदी'}</span>
            <ChevronDown size={13} color="#64748b" />
          </button>

          {isLangOpen && (
            <div
              style={{
                position: 'absolute',
                top: 'calc(100% + 8px)',
                right: 0,
                backgroundColor: '#ffffff',
                borderRadius: '12px',
                border: '1px solid var(--border-light)',
                boxShadow: '0 10px 25px rgba(0,0,0,0.1)',
                width: '140px',
                padding: '6px',
                zIndex: 50,
              }}
            >
              {[
                { code: 'en', label: 'English' },
                { code: 'hi', label: 'हिंदी (Hindi)' },
              ].map((l) => (
                <button
                  key={l.code}
                  onClick={() => {
                    setLanguage(l.code);
                    setIsLangOpen(false);
                  }}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    width: '100%',
                    padding: '7px 10px',
                    borderRadius: '6px',
                    fontSize: '12.5px',
                    fontWeight: language === l.code ? '700' : '500',
                    color: language === l.code ? '#15803d' : '#334155',
                    backgroundColor: language === l.code ? '#f0fdf4' : 'transparent',
                    textAlign: 'left',
                  }}
                >
                  <span>{l.label}</span>
                  {language === l.code && <Check size={13} color="#15803d" />}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Date Selector Dropdown */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setIsDateOpen(!isDateOpen)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '7px 14px',
              backgroundColor: '#ffffff',
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-pill)',
              color: '#2d3f34',
              fontSize: '13px',
              fontWeight: '600',
              boxShadow: 'var(--shadow-card)',
            }}
          >
            <Calendar size={14} color="#1e7e45" />
            <span>{selectedDateRange.split(' (')[0]}</span>
            <ChevronDown size={14} color="#64748b" />
          </button>

          {isDateOpen && (
            <div
              style={{
                position: 'absolute',
                top: 'calc(100% + 8px)',
                right: 0,
                backgroundColor: '#ffffff',
                borderRadius: '12px',
                border: '1px solid var(--border-light)',
                boxShadow: '0 10px 25px rgba(0,0,0,0.1)',
                width: '210px',
                padding: '6px',
                zIndex: 50,
              }}
            >
              {[
                'Today (26 May, 2025)',
                'This Week (20 - 26 May)',
                'This Month (May 2025)',
                'This Year (2025)',
              ].map((d) => (
                <button
                  key={d}
                  onClick={() => {
                    setSelectedDateRange(d);
                    setIsDateOpen(false);
                  }}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    fontSize: '12px',
                    color: '#334155',
                    textAlign: 'left',
                    fontWeight: selectedDateRange === d ? '700' : '500',
                    backgroundColor: selectedDateRange === d ? '#eaf7ee' : 'transparent',
                  }}
                >
                  <span>{d}</span>
                  {selectedDateRange === d && <Check size={13} color="#15803d" />}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Notifications Popover */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setIsNotifOpen(!isNotifOpen)}
            style={{
              position: 'relative',
              width: '38px',
              height: '38px',
              borderRadius: '50%',
              backgroundColor: '#ffffff',
              border: '1px solid var(--border-light)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: 'var(--shadow-card)',
            }}
          >
            <Bell size={17} color="#475569" />
            {unreadNotifs.length > 0 && (
              <span
                style={{
                  position: 'absolute',
                  top: '7px',
                  right: '8px',
                  width: '8px',
                  height: '8px',
                  borderRadius: '50%',
                  backgroundColor: 'var(--primary-brand)',
                  boxShadow: '0 0 0 2px #ffffff',
                }}
              />
            )}
          </button>

          {isNotifOpen && (
            <div
              style={{
                position: 'absolute',
                top: 'calc(100% + 8px)',
                right: 0,
                width: '340px',
                backgroundColor: '#ffffff',
                borderRadius: '16px',
                border: '1px solid var(--border-light)',
                boxShadow: '0 15px 35px rgba(0,0,0,0.15)',
                padding: '14px',
                zIndex: 60,
                animation: 'fadeIn 0.15s ease',
              }}
            >
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  marginBottom: '10px',
                  borderBottom: '1px solid #f1f5f9',
                  paddingBottom: '8px',
                }}
              >
                <div style={{ fontWeight: '700', fontSize: '14px', color: '#0f172a' }}>
                  Notifications ({unreadNotifs.length} new)
                </div>
                <button
                  onClick={markAllNotificationsRead}
                  style={{ fontSize: '11px', color: 'var(--primary-brand)', fontWeight: '600' }}
                >
                  Mark read
                </button>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '280px', overflowY: 'auto' }}>
                {notifications.slice(0, 4).map((n) => (
                  <div
                    key={n.id}
                    onClick={() => {
                      navigate('/notifications');
                      setIsNotifOpen(false);
                    }}
                    style={{
                      padding: '8px',
                      borderRadius: '8px',
                      backgroundColor: n.unread ? '#f6fbf8' : '#f8fafc',
                      border: `1px solid ${n.unread ? '#bbf7d0' : '#e2e8f0'}`,
                      cursor: 'pointer',
                    }}
                  >
                    <div style={{ fontSize: '12.5px', fontWeight: '700', color: '#1e293b' }}>
                      {n.title}
                    </div>
                    <div style={{ fontSize: '11.5px', color: '#64748b', marginTop: '2px', lineHeight: '1.3' }}>
                      {n.message}
                    </div>
                    <div style={{ fontSize: '10px', color: '#94a3b8', marginTop: '4px' }}>
                      {n.time}
                    </div>
                  </div>
                ))}
              </div>

              <button
                onClick={() => {
                  navigate('/notifications');
                  setIsNotifOpen(false);
                }}
                style={{
                  width: '100%',
                  marginTop: '10px',
                  padding: '8px',
                  backgroundColor: '#f1f8f3',
                  color: '#15803d',
                  borderRadius: '8px',
                  fontSize: '12px',
                  fontWeight: '600',
                  textAlign: 'center',
                }}
              >
                View All Notifications →
              </button>
            </div>
          )}
        </div>

        {/* Admin Profile Pill */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setIsProfileOpen(!isProfileOpen)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '9px',
              padding: '4px 12px 4px 4px',
              backgroundColor: '#ffffff',
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-pill)',
              boxShadow: 'var(--shadow-card)',
              cursor: 'pointer',
            }}
          >
            <Avatar
              src={adminUser?.avatar}
              name={adminUser?.name || 'Admin'}
              size={30}
              alt={adminUser?.name || 'Admin'}
            />
            <span style={{ fontSize: '13px', fontWeight: '600', color: '#1f2937' }}>
              {adminUser?.name || 'Admin'}
            </span>
            <ChevronDown size={13} color="#64748b" />
          </button>

          {isProfileOpen && (
            <div
              style={{
                position: 'absolute',
                top: 'calc(100% + 8px)',
                right: 0,
                backgroundColor: '#ffffff',
                borderRadius: '12px',
                border: '1px solid var(--border-light)',
                boxShadow: '0 10px 25px rgba(0,0,0,0.1)',
                width: '230px',
                padding: '6px',
                zIndex: 50,
                animation: 'fadeIn 0.15s ease',
              }}
            >
              <div style={{ padding: '8px 12px', borderBottom: '1px solid #f1f5f9', marginBottom: '4px', display: 'flex', alignItems: 'center', gap: '10px' }}>
                <Avatar
                  src={adminUser?.avatar}
                  name={adminUser?.name || 'Admin'}
                  size={36}
                />
                <div style={{ overflow: 'hidden' }}>
                  <div style={{ fontSize: '13px', fontWeight: '700', color: '#0f172a', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {adminUser?.name || 'Administrator'}
                  </div>
                  <div style={{ fontSize: '11px', color: '#64748b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {adminUser?.email || ''}
                  </div>
                </div>
              </div>

              <button
                onClick={() => {
                  navigate('/settings?tab=profile');
                  setIsProfileOpen(false);
                }}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '6px',
                  fontSize: '12.5px',
                  color: '#15803d',
                  fontWeight: '600',
                  textAlign: 'left',
                  backgroundColor: '#f0fdf4',
                  marginBottom: '2px',
                }}
              >
                <User size={14} color="#15803d" />
                <span>Admin Profile</span>
              </button>

              <button
                onClick={() => {
                  navigate('/settings?tab=platform');
                  setIsProfileOpen(false);
                }}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '6px',
                  fontSize: '12.5px',
                  color: '#334155',
                  textAlign: 'left',
                }}
              >
                <SlidersHorizontal size={14} color="#64748b" />
                <span>Platform Settings</span>
              </button>

              <button
                onClick={() => {
                  logoutAdmin();
                  setIsProfileOpen(false);
                }}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '6px',
                  fontSize: '12.5px',
                  color: '#dc2626',
                  textAlign: 'left',
                }}
              >
                <LogOut size={14} />
                <span>Sign Out</span>
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
