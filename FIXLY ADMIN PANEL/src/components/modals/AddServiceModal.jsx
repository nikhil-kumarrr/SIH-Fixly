import React, { useState, useEffect } from 'react';
import Modal from '../common/Modal';
import { useApp } from '../../context/AppContext';
import { api } from '../../services/api';
import { Upload, CheckCircle2 } from 'lucide-react';

import { OFFICIAL_CATEGORIES, getMergedCategories, normalizeCategory, toTitleCase } from '../../data/services';

const DEFAULT_FORM_DATA = {
  name: '',
  category: 'Plumber',
  description: '',
  basePrice: '₹350',
  image: '',
  requiredSkills: '',
  availability: '24/7 Available',
  emergencyAvailable: true,
  status: 'Active',
};

export default function AddServiceModal({ isOpen, onClose, serviceToEdit = null }) {
  const { addService, updateService, services } = useApp();

  const [formData, setFormData] = useState(DEFAULT_FORM_DATA);
  const [isCustomCategory, setIsCustomCategory] = useState(false);
  const [customCategory, setCustomCategory] = useState('');
  const [uploadingImage, setUploadingImage] = useState(false);
  const [errors, setErrors] = useState({});

  const categoryOptions = React.useMemo(() => {
    return getMergedCategories(services);
  }, [services]);

  const resetForm = () => {
    setFormData(DEFAULT_FORM_DATA);
    setIsCustomCategory(false);
    setCustomCategory('');
    setUploadingImage(false);
    setErrors({});
  };

  // Reset form when modal opens afresh or when switching between add and edit
  useEffect(() => {
    if (isOpen) {
      if (serviceToEdit) {
        const cat = normalizeCategory(serviceToEdit.category || 'Plumber');
        const isKnown = categoryOptions.includes(cat);
        setFormData({
          name: toTitleCase(serviceToEdit.title || serviceToEdit.name || ''),
          category: isKnown ? cat : 'Plumber',
          description: serviceToEdit.description || (Array.isArray(serviceToEdit.whatsIncluded) ? serviceToEdit.whatsIncluded.join(', ') : ''),
          basePrice: serviceToEdit.basePrice ? (String(serviceToEdit.basePrice).startsWith('₹') ? String(serviceToEdit.basePrice) : `₹${serviceToEdit.basePrice}`) : '₹350',
          image: serviceToEdit.image || serviceToEdit.icon || '',
          requiredSkills: serviceToEdit.requiredSkills || '',
          availability: serviceToEdit.availability || '24/7 Available',
          emergencyAvailable: serviceToEdit.emergencyAvailable ?? true,
          status: serviceToEdit.isActive === false ? 'Inactive' : 'Active',
        });
        if (!isKnown && cat) {
          setIsCustomCategory(true);
          setCustomCategory(cat);
        } else {
          setIsCustomCategory(false);
          setCustomCategory('');
        }
      } else {
        // Brand new creation -> strictly reset to clean defaults
        resetForm();
      }
      setErrors({});
      setUploadingImage(false);
    }
  }, [isOpen, serviceToEdit]);

  const handleClose = () => {
    resetForm();
    onClose();
  };

  const handleFileUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    try {
      setUploadingImage(true);
      const res = await api.uploadImage(file);
      if (res && (res.url || res.fileUrl)) {
        setFormData((prev) => ({ ...prev, image: res.url || res.fileUrl }));
        setErrors((prev) => ({ ...prev, image: undefined }));
      } else {
        throw new Error('No URL returned from server');
      }
    } catch (err) {
      console.warn('Server upload failed, falling back to local base64:', err.message);
      const reader = new FileReader();
      reader.onload = () => {
        setFormData((prev) => ({ ...prev, image: reader.result }));
        setErrors((prev) => ({ ...prev, image: undefined }));
      };
      reader.readAsDataURL(file);
    } finally {
      setUploadingImage(false);
    }
  };

  const validate = () => {
    const errs = {};
    const effectiveCategory = isCustomCategory ? customCategory.trim() : formData.category?.trim();
    if (!formData.name.trim()) errs.name = 'Service title is required';
    if (!effectiveCategory) errs.category = 'Service category is required';
    if (!formData.description.trim()) errs.description = 'Description is required';
    if (!formData.basePrice.trim() || parseInt(formData.basePrice.replace(/\D/g, ''), 10) <= 0) {
      errs.basePrice = 'Valid base rate is required';
    }
    if (!formData.image || !formData.image.trim()) {
      errs.image = 'Service icon/image is strictly mandatory. Please upload an icon for the app.';
    }
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!validate()) return;

    const rawCat = isCustomCategory ? customCategory.trim() : formData.category?.trim();
    const effectiveCategory = (rawCat || '').toLowerCase().trim();

    const rawTitle = formData.name.trim();
    const effectiveTitle = rawTitle.toLowerCase();

    try {
      const payload = {
        title: effectiveTitle,
        name: effectiveTitle,
        category: effectiveCategory,
        image: formData.image || '',
        basePrice: parseInt(formData.basePrice.replace(/\D/g, ''), 10) || 100,
        estimatedTime: '1 Hour',
        whatsIncluded: formData.description ? [formData.description] : ['Professional Service'],
        isActive: formData.status === 'Active'
      };

      if (serviceToEdit) {
        await updateService(serviceToEdit.id || serviceToEdit._id, payload);
      } else {
        await addService(payload);
      }

      // Complete reset on success
      resetForm();
      onClose();
    } catch (err) {
      console.error('Failed to submit service modal:', err);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title={serviceToEdit ? 'Edit Cooperative Service' : 'Add New Cooperative Service'}
      subtitle={serviceToEdit ? 'Update rate cards, details, and emergency availability' : 'Define rate cards, skill prerequisites, and emergency availability'}
      maxWidth="560px"
      footer={
        <>
          <button
            onClick={handleClose}
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
            {serviceToEdit ? 'Save Changes' : 'Publish to Catalog'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Service Title *
          </label>
          <input

            type="text"
            placeholder="e.g. Geyser Repair & Thermostat Installation"
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

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
              <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155' }}>
                Service Category *
              </label>
              {isCustomCategory ? (
                <button
                  type="button"
                  onClick={() => {
                    setIsCustomCategory(false);
                    setCustomCategory('');
                  }}
                  style={{ background: 'none', border: 'none', color: '#0284c7', fontSize: '11px', cursor: 'pointer', fontWeight: 600 }}
                >
                  ← Select Existing
                </button>
              ) : null}
            </div>

            {isCustomCategory ? (
              <input
                type="text"
                placeholder="Type new category name (e.g. Gardening)..."
                value={customCategory}
                onChange={(e) => {
                  setCustomCategory(e.target.value);
                  setErrors((prev) => ({ ...prev, category: undefined }));
                }}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  border: `1px solid ${errors.category ? '#ef4444' : '#0284c7'}`,
                  fontSize: '13px',
                  backgroundColor: '#f0f9ff',
                }}
              />
            ) : (
              <select
                value={formData.category}
                onChange={(e) => {
                  if (e.target.value === '__custom__') {
                    setIsCustomCategory(true);
                  } else {
                    setFormData({ ...formData, category: e.target.value });
                  }
                }}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  border: `1px solid ${errors.category ? '#ef4444' : '#cbd5e1'}`,
                  fontSize: '13px',
                  backgroundColor: '#ffffff',
                }}
              >
                {categoryOptions.map((cat) => (
                  <option key={cat} value={cat}>{cat}</option>
                ))}
                <option value="__custom__" style={{ fontWeight: '700', color: '#0284c7' }}>+ Add New / Custom Category...</option>
              </select>
            )}
            {errors.category && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.category}</span>}
          </div>

          <div>
            <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
              Base Standard Rate *
            </label>
            <input
              type="text"
              placeholder="₹350"
              value={formData.basePrice}
              onChange={(e) => setFormData({ ...formData, basePrice: e.target.value })}
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: '8px',
                border: `1px solid ${errors.basePrice ? '#ef4444' : '#cbd5e1'}`,
                fontSize: '13px',
              }}
            />
            {errors.basePrice && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.basePrice}</span>}
          </div>
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: errors.image ? '#ef4444' : '#334155', display: 'block', marginBottom: '6px' }}>
            Service App Icon / Image * <span style={{ color: '#ef4444', fontWeight: 'bold' }}>(Mandatory)</span>
          </label>
          <div
            style={{
              border: errors.image ? '2px dashed #ef4444' : '2px dashed #cbd5e1',
              borderRadius: '10px',
              padding: '16px',
              textAlign: 'center',
              backgroundColor: errors.image ? '#fef2f2' : '#f8fafc',
              position: 'relative',
              cursor: 'pointer'
            }}
          >
            {formData.image ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <img
                  src={formData.image}
                  alt="Preview"
                  style={{ width: '54px', height: '54px', borderRadius: '8px', objectFit: 'cover', border: '1px solid #cbd5e1' }}
                />
                <div style={{ textAlign: 'left', flex: 1 }}>
                  <div style={{ fontSize: '12.5px', fontWeight: '700', color: '#15803d', display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <CheckCircle2 size={14} /> Icon Uploaded Successfully!
                  </div>
                  <div style={{ fontSize: '11px', color: '#64748b', textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap', maxWidth: '240px' }}>
                    {formData.image.startsWith('data:') ? 'Image selected from desktop' : formData.image}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setFormData({ ...formData, image: '' })}
                  style={{ fontSize: '12px', color: '#ef4444', border: 'none', background: 'none', cursor: 'pointer', fontWeight: '600' }}
                >
                  Change
                </button>
              </div>
            ) : (
              <div>
                <Upload size={22} color={errors.image ? '#ef4444' : '#64748b'} style={{ marginBottom: '4px' }} />
                <div style={{ fontSize: '13px', fontWeight: '600', color: errors.image ? '#b91c1c' : '#334155' }}>
                  {uploadingImage ? 'Uploading icon from desktop...' : 'Click to select icon image from Desktop'}
                </div>
                <div style={{ fontSize: '11px', color: errors.image ? '#ef4444' : '#94a3b8', marginTop: '2px' }}>
                  Supports PNG, JPG, WEBP (Required for mobile app display)
                </div>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileUpload}
                  disabled={uploadingImage}
                  style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    width: '100%',
                    height: '100%',
                    opacity: 0,
                    cursor: 'pointer'
                  }}
                />
              </div>
            )}
          </div>
          {errors.image && (
            <span style={{ fontSize: '12px', color: '#ef4444', fontWeight: '600', display: 'block', marginTop: '4px' }}>
              {errors.image}
            </span>
          )}
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Service Description *
          </label>
          <textarea
            rows="3"
            placeholder="Detailed scope of service, warranty terms, and standard tools required..."
            value={formData.description}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            style={{
              width: '100%',
              padding: '8px 12px',
              borderRadius: '8px',
              border: `1px solid ${errors.description ? '#ef4444' : '#cbd5e1'}`,
              fontSize: '13px',
              fontFamily: 'inherit',
            }}
          />
          {errors.description && <span style={{ fontSize: '11px', color: '#ef4444' }}>{errors.description}</span>}
        </div>

        <div>
          <label style={{ fontSize: '12px', fontWeight: '600', color: '#334155', display: 'block', marginBottom: '4px' }}>
            Mandatory Skill Certifications
          </label>
          <input
            type="text"
            placeholder="e.g. Electrical Safety License, High-Voltage Certification"
            value={formData.requiredSkills}
            onChange={(e) => setFormData({ ...formData, requiredSkills: e.target.value })}
            style={{
              width: '100%',
              padding: '8px 12px',
              borderRadius: '8px',
              border: '1px solid #cbd5e1',
              fontSize: '13px',
            }}
          />
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '4px' }}>
          <input
            type="checkbox"
            id="emergency"
            checked={formData.emergencyAvailable}
            onChange={(e) => setFormData({ ...formData, emergencyAvailable: e.target.checked })}
            style={{ width: '18px', height: '18px', accentColor: '#1e7e45' }}
          />
          <label htmlFor="emergency" style={{ fontSize: '13px', color: '#1e293b', fontWeight: '500', cursor: 'pointer' }}>
            Enable 24/7 Emergency Instant Dispatch for this service
          </label>
        </div>
      </form>
    </Modal>
  );
}
