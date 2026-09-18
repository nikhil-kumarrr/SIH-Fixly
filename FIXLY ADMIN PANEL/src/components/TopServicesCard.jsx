import React, { useMemo } from 'react';
import { useApp } from '../context/AppContext';
import {
  Wrench,
  Zap,
  Sparkles,
  Hammer,
  Paintbrush,
  HeartHandshake,
  Sprout,
  Car,
  Cpu,
  FolderOpen
} from 'lucide-react';

const DEFAULT_CATEGORIES = [
  { id: 'plumbing', name: 'Plumbing', percentage: 25, icon: 'wrench', color: '#1e40af', bg: '#eff6ff' },
  { id: 'electrical', name: 'Electrical', percentage: 20, icon: 'zap', color: '#ca8a04', bg: '#fefce8' },
  { id: 'cleaning', name: 'Cleaning', percentage: 15, icon: 'sparkles', color: '#16a34a', bg: '#f0fdf4' },
  { id: 'carpentry', name: 'Carpentry', percentage: 15, icon: 'hammer', color: '#ea580c', bg: '#fff7ed' },
  { id: 'others', name: 'Others', percentage: 25, icon: 'grid', color: '#0d9488', bg: '#f0fdfa' },
];

export default function TopServicesCard({ onSelectService }) {
  const { services = [], bookings = [], topServices: apiTopServices = [] } = useApp();

  const getCategoryMeta = (catName) => {
    const name = (catName || '').toLowerCase().trim();
    if (name.includes('plumb')) {
      return { id: 'plumbing', name: 'Plumbing', icon: 'wrench', color: '#1e40af', bg: '#eff6ff' };
    }
    if (name.includes('electr')) {
      return { id: 'electrical', name: 'Electrical', icon: 'zap', color: '#ca8a04', bg: '#fefce8' };
    }
    if (
      name.includes('clean') ||
      name.includes('maid') ||
      name.includes('housekeep') ||
      name.includes('domestic')
    ) {
      return { id: 'cleaning', name: 'Cleaning', icon: 'sparkles', color: '#16a34a', bg: '#f0fdf4' };
    }
    if (name.includes('carpent')) {
      return { id: 'carpentry', name: 'Carpentry', icon: 'hammer', color: '#ea580c', bg: '#fff7ed' };
    }
    if (name.includes('paint')) {
      return { id: 'painting', name: 'Painting', icon: 'paintbrush', color: '#9333ea', bg: '#faf5ff' };
    }
    if (name.includes('care') || name.includes('nurs')) {
      return { id: 'caregiving', name: 'Caregiving', icon: 'heart', color: '#e11d48', bg: '#ffe4e6' };
    }
    if (name.includes('garden') || name.includes('lawn')) {
      return { id: 'gardening', name: 'Gardening', icon: 'sprout', color: '#059669', bg: '#ecfdf5' };
    }
    if (name.includes('driv') || name.includes('transport')) {
      return { id: 'driver', name: 'Driver', icon: 'car', color: '#0284c7', bg: '#f0f9ff' };
    }
    if (
      name.includes('tech') ||
      name.includes('appliance') ||
      name.includes('ac') ||
      name.includes('repair')
    ) {
      return { id: 'technician', name: 'Technician', icon: 'cpu', color: '#4f46e5', bg: '#eef2ff' };
    }

    const formattedName = name
      ? name.charAt(0).toUpperCase() + name.slice(1)
      : 'Others';
    return { id: name || 'others', name: formattedName, icon: 'grid', color: '#0d9488', bg: '#f0fdfa' };
  };

  const renderServiceIcon = (iconName, color) => {
    switch (iconName) {
      case 'wrench':
        return <Wrench size={16} color={color} strokeWidth={2.4} />;
      case 'zap':
        return <Zap size={16} color={color} strokeWidth={2.4} />;
      case 'sparkles':
        return <Sparkles size={16} color={color} strokeWidth={2.4} />;
      case 'hammer':
        return <Hammer size={16} color={color} strokeWidth={2.4} />;
      case 'paintbrush':
        return <Paintbrush size={16} color={color} strokeWidth={2.4} />;
      case 'heart':
        return <HeartHandshake size={16} color={color} strokeWidth={2.4} />;
      case 'sprout':
        return <Sprout size={16} color={color} strokeWidth={2.4} />;
      case 'car':
        return <Car size={16} color={color} strokeWidth={2.4} />;
      case 'cpu':
        return <Cpu size={16} color={color} strokeWidth={2.4} />;
      case 'grid':
      case 'folder':
      default:
        return <FolderOpen size={16} color={color} strokeWidth={2.4} />;
    }
  };

  // Dynamically compute Top 5 Services combining real backend bookings & service catalog
  const displayList = useMemo(() => {
    // 1. Gather all unique category keys from active bookings & catalog
    const categoryCounts = {};

    // Count from actual bookings
    if (Array.isArray(bookings) && bookings.length > 0) {
      bookings.forEach((b) => {
        const rawCat = b.serviceCategory || b.service || '';
        const meta = getCategoryMeta(rawCat);
        categoryCounts[meta.name] = (categoryCounts[meta.name] || 0) + 1;
      });
    }

    // Include categories from active services catalog
    if (Array.isArray(services) && services.length > 0) {
      services.forEach((s) => {
        const rawCat = s.category || s.name || '';
        const meta = getCategoryMeta(rawCat);
        if (categoryCounts[meta.name] === undefined) {
          categoryCounts[meta.name] = 0;
        }
      });
    }

    // Include backend API topServices if present
    if (Array.isArray(apiTopServices) && apiTopServices.length > 0) {
      apiTopServices.forEach((ts) => {
        const rawCat = ts.name || ts.id || '';
        const meta = getCategoryMeta(rawCat);
        if (categoryCounts[meta.name] === undefined) {
          categoryCounts[meta.name] = Number(ts.count) || 0;
        }
      });
    }

    // If we have categories from real data
    const presentCategoryNames = Object.keys(categoryCounts);

    if (presentCategoryNames.length > 0) {
      const totalBookings = Object.values(categoryCounts).reduce((sum, val) => sum + val, 0);

      // Default baseline percentage weights for top 5 slots (25%, 20%, 15%, 15%, 25%)
      const defaultWeights = [25, 20, 15, 15, 25];

      // Sort categories: highest real booking count first, then catalog categories
      let sortedCategories = presentCategoryNames.sort(
        (a, b) => (categoryCounts[b] || 0) - (categoryCounts[a] || 0)
      );

      // If fewer than 5 categories found, pad with standard default demo categories
      if (sortedCategories.length < 5) {
        DEFAULT_CATEGORIES.forEach((def) => {
          if (!sortedCategories.includes(def.name)) {
            sortedCategories.push(def.name);
          }
        });
      }

      const top5Names = sortedCategories.slice(0, 5);

      // If there are real bookings distributed across multiple categories, use dynamic percentages
      const hasDistributedBookings =
        totalBookings > 0 &&
        top5Names.filter((cat) => (categoryCounts[cat] || 0) > 0).length >= 3;

      return top5Names.map((catName, index) => {
        const meta = getCategoryMeta(catName);
        const count = categoryCounts[catName] || 0;

        let percentage;
        if (hasDistributedBookings) {
          percentage = Math.min(100, Math.max(1, Math.round((count / totalBookings) * 100)));
        } else {
          // If all bookings are in 1 category or low volume, use clean proportional scale
          if (count > 0 && index === 0) {
            percentage = totalBookings > 1 ? 28 : 25;
          } else {
            percentage = defaultWeights[index] || 15;
          }
        }

        return {
          id: meta.id || catName.toLowerCase(),
          name: meta.name,
          percentage,
          count,
          icon: meta.icon,
          color: meta.color,
          bg: meta.bg,
        };
      });
    }

    // Default fallback list
    return DEFAULT_CATEGORIES;
  }, [bookings, services, apiTopServices]);

  return (
    <div
      style={{
        backgroundColor: 'var(--bg-card)',
        borderRadius: 'var(--radius-lg)',
        border: '1px solid var(--border-light)',
        padding: '22px 24px',
        boxShadow: 'var(--shadow-card)',
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
        justifyContent: 'space-between',
      }}
    >
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: '16px',
        }}
      >
        <h2
          style={{
            fontSize: '16px',
            fontWeight: '700',
            color: '#12251a',
          }}
        >
          Top Services
        </h2>
        <span
          style={{
            fontSize: '11px',
            fontWeight: '600',
            color: '#15803d',
            backgroundColor: '#eaf7ee',
            padding: '3px 8px',
            borderRadius: '6px',
          }}
        >
          By Volume
        </span>
      </div>

      {/* Services List */}
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '14px',
          justifyContent: 'space-around',
          flex: 1,
        }}
      >
        {displayList.map((service) => (
          <div
            key={service.id}
            onClick={() => onSelectService && onSelectService(service)}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: '12px',
              padding: '4px 6px',
              borderRadius: '8px',
              cursor: 'pointer',
              transition: 'background 0.15s ease',
            }}
            onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#f8faf9')}
            onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
          >
            {/* Icon + Service Name */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                width: '105px',
                flexShrink: 0,
              }}
            >
              <div
                style={{
                  width: '28px',
                  height: '28px',
                  borderRadius: '7px',
                  backgroundColor: service.bg || '#eff6ff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0,
                }}
              >
                {renderServiceIcon(service.icon, service.color)}
              </div>
              <span
                style={{
                  fontSize: '13px',
                  fontWeight: '600',
                  color: '#28392f',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {service.name}
              </span>
            </div>

            {/* Progress Bar Container */}
            <div
              style={{
                flex: 1,
                height: '7px',
                backgroundColor: '#e6ede8',
                borderRadius: '999px',
                overflow: 'hidden',
                position: 'relative',
              }}
            >
              <div
                style={{
                  width: `${Math.min(100, service.percentage * 3.2)}%`,
                  maxWidth: '100%',
                  height: '100%',
                  backgroundColor: '#22864c',
                  borderRadius: '999px',
                  transition: 'width 0.6s cubic-bezier(0.16, 1, 0.3, 1)',
                }}
              />
            </div>

            {/* Percentage Text */}
            <div
              style={{
                width: '38px',
                textAlign: 'right',
                fontSize: '12.5px',
                fontWeight: '600',
                color: '#495a50',
                flexShrink: 0,
              }}
            >
              {service.percentage}%
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
