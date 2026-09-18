import React, { useMemo } from 'react';
import { ALL_STATES, getDistrictsForState } from '../../data/indiaLocations';

/**
 * StateDistrictSelect
 * Reusable dropdown component providing official Indian States and Districts.
 * Prevents spelling errors and standardizes DB values across frontend & backend.
 */
export default function StateDistrictSelect({
  selectedState = '',
  selectedDistrict = '',
  onStateChange,
  onDistrictChange,
  isFilter = false,
  stateLabel = isFilter ? 'State' : 'State *',
  districtLabel = isFilter ? 'District' : 'District *',
  stateRequired = !isFilter,
  districtRequired = !isFilter,
  disabled = false,
  layout = 'grid', // 'grid' | 'stack' | 'inline'
  stateId = 'state-select',
  districtId = 'district-select',
  fieldStyle = {},
  labelStyle = {},
  showLabels = true,
}) {
  const districts = useMemo(() => {
    return getDistrictsForState(selectedState);
  }, [selectedState]);

  const handleStateChange = (e) => {
    const newState = e.target.value;
    if (onStateChange) onStateChange(newState);

    // If new state doesn't have the existing district, clear it
    if (selectedDistrict) {
      const newDistricts = getDistrictsForState(newState);
      const exists = newDistricts.some(
        (d) => d.toLowerCase() === String(selectedDistrict).toLowerCase()
      );
      if (!exists && onDistrictChange) {
        onDistrictChange('');
      }
    }
  };

  const handleDistrictChange = (e) => {
    const newDistrict = e.target.value;
    if (onDistrictChange) onDistrictChange(newDistrict);
  };

  const defaultFieldStyle = {
    width: '100%',
    padding: '9px 12px',
    borderRadius: '8px',
    border: '1px solid #cbd5e1',
    fontSize: '13px',
    backgroundColor: disabled ? '#f1f5f9' : '#ffffff',
    color: '#1e293b',
    cursor: disabled ? 'not-allowed' : 'pointer',
    outline: 'none',
    boxSizing: 'border-box',
    ...fieldStyle,
  };

  const defaultLabelStyle = {
    display: 'block',
    fontSize: '12.5px',
    fontWeight: '600',
    color: '#334155',
    marginBottom: '4px',
    ...labelStyle,
  };

  const containerStyle = {
    grid: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' },
    stack: { display: 'flex', flexDirection: 'column', gap: '12px' },
    inline: { display: 'flex', alignItems: 'center', gap: '8px' },
  }[layout] || { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' };

  return (
    <div style={containerStyle}>
      <div style={{ flex: 1, minWidth: 0 }}>
        {showLabels && stateLabel && (
          <label htmlFor={stateId} style={defaultLabelStyle}>
            {stateLabel}
          </label>
        )}
        <select
          id={stateId}
          value={selectedState}
          onChange={handleStateChange}
          required={stateRequired}
          disabled={disabled}
          style={defaultFieldStyle}
        >
          <option value="">
            {isFilter ? '— All States —' : 'Select State...'}
          </option>
          {ALL_STATES.map((state) => (
            <option key={state} value={state}>
              {state}
            </option>
          ))}
        </select>
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        {showLabels && districtLabel && (
          <label htmlFor={districtId} style={defaultLabelStyle}>
            {districtLabel}
          </label>
        )}
        <select
          id={districtId}
          value={selectedDistrict}
          onChange={handleDistrictChange}
          required={districtRequired}
          disabled={disabled || (!isFilter && !selectedState)}
          style={{
            ...defaultFieldStyle,
            backgroundColor: !selectedState && !isFilter ? '#f8fafc' : defaultFieldStyle.backgroundColor,
            cursor: !selectedState && !isFilter ? 'not-allowed' : defaultFieldStyle.cursor,
          }}
        >
          <option value="">
            {isFilter
              ? '— All Districts —'
              : selectedState
              ? 'Select District...'
              : 'Select State First...'}
          </option>
          {districts.map((district) => (
            <option key={district} value={district}>
              {district}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
