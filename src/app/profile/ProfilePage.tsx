/**
 * Profile Page Component
 */

import React, { useRef, useState, useCallback, useEffect } from 'react';
import { useAuth } from '@/components/auth/AuthProvider';
import { useUI } from '@/lib/state';
import { useAuthStore } from '@/lib/auth-store';
import './ProfilePage.css';

const AVATAR_STORAGE_KEY = 'beatrice_avatar';

function loadAvatarFromStorage(): string | null {
  try {
    return localStorage.getItem(AVATAR_STORAGE_KEY);
  } catch {
    return null;
  }
}

function saveAvatarToStorage(dataUrl: string) {
  try {
    localStorage.setItem(AVATAR_STORAGE_KEY, dataUrl);
  } catch (err) {
    console.warn('Failed to save avatar to localStorage:', err);
  }
}

export default function ProfilePage() {
  const { currentUser, logout } = useAuth();
  const { toggleProfile } = useUI();
  const setUser = useAuthStore(s => s.setUser);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(
    currentUser?.photoURL || loadAvatarFromStorage()
  );
  const [isHovering, setIsHovering] = useState(false);

  // Sync avatar to the auth store so Header can access it
  useEffect(() => {
    if (avatarUrl && currentUser) {
      const updated = { ...currentUser, photoURL: avatarUrl };
      setUser(updated);
      saveAvatarToStorage(avatarUrl);
    }
  }, [avatarUrl]);

  const getInitials = (name: string | null): string => {
    if (!name) return 'U';
    const names = name.split(' ');
    if (names.length === 1) return names[0].charAt(0).toUpperCase();
    return names[0].charAt(0).toUpperCase() + names[names.length - 1].charAt(0).toUpperCase();
  };

  const handleAvatarClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith('image/')) {
      alert('Please select an image file.');
      return;
    }

    // Validate file size (max 2MB)
    if (file.size > 2 * 1024 * 1024) {
      alert('Image must be smaller than 2MB.');
      return;
    }

    const reader = new FileReader();
    reader.onload = (event) => {
      const dataUrl = event.target?.result as string;
      if (dataUrl) {
        setAvatarUrl(dataUrl);
      }
    };
    reader.onerror = () => {
      alert('Failed to read the image file. Please try again.');
    };
    reader.readAsDataURL(file);

    // Reset input so the same file can be re-selected
    e.target.value = '';
  }, []);

  const handleRemoveAvatar = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setAvatarUrl(null);
    try {
      localStorage.removeItem(AVATAR_STORAGE_KEY);
    } catch {}
    if (currentUser) {
      setUser({ ...currentUser, photoURL: null });
    }
  }, [currentUser, setUser]);

  if (!currentUser) {
    return (
      <div className="profile-page">
        <div className="profile-section">
          <h3>Authentication Required</h3>
          <p>Please sign in to view your profile and account information.</p>
          <button
            className="btn btn-primary"
            onClick={() => {
              toggleProfile();
            }}
          >
            Sign In
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="profile-page">
      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileChange}
        style={{ display: 'none' }}
        aria-label="Choose profile picture"
      />

      {/* Profile Header */}
      <div className="profile-header">
        <div
          className="profile-avatar avatar-upload"
          onClick={handleAvatarClick}
          onMouseEnter={() => setIsHovering(true)}
          onMouseLeave={() => setIsHovering(false)}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') handleAvatarClick(); }}
          title="Click to upload profile picture"
        >
          {avatarUrl ? (
            <img src={avatarUrl} alt="Profile" className="avatar-image" />
          ) : (
            <span className="avatar-initials">
              {getInitials(currentUser.displayName || null)}
            </span>
          )}

          {/* Camera overlay on hover */}
          <div className={`avatar-overlay ${isHovering ? 'visible' : ''}`}>
            <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" />
              <circle cx="12" cy="13" r="4" />
            </svg>
            <span className="avatar-overlay-text">Change Photo</span>
          </div>

          {/* Remove button (only shown when there's an avatar) */}
          {avatarUrl && (
            <button
              className="avatar-remove-btn"
              onClick={handleRemoveAvatar}
              title="Remove profile picture"
              aria-label="Remove profile picture"
            >
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          )}
        </div>

        <div className="profile-info">
          <h2>{currentUser.displayName || currentUser.email || 'User'}</h2>
          <p className="text-muted">{currentUser.email || 'No email'}</p>
          <p className="text-muted">Provider: {currentUser.provider || 'N/A'}</p>
        </div>
      </div>

      {/* Account Details */}
      <div className="profile-section">
        <h3>Account Details</h3>
        <div className="profile-details">
          <p><strong>User ID:</strong> {currentUser.uid || 'N/A'}</p>
          <p><strong>Authentication Status:</strong> Verified</p>
        </div>
      </div>

      {/* Stats Section */}
      <div className="profile-section">
        <h3>Usage</h3>
        <div className="profile-stats">
          <div className="stat-item">
            <div className="stat-value">--</div>
            <div className="stat-label">Sessions</div>
          </div>
          <div className="stat-item">
            <div className="stat-value">--</div>
            <div className="stat-label">Messages</div>
          </div>
          <div className="stat-item">
            <div className="stat-value">--</div>
            <div className="stat-label">Minutes</div>
          </div>
        </div>
      </div>

      {/* Sign Out Button - Pinned to Bottom */}
      <div className="profile-signout-section">
        <button
          className="signout-button"
          onClick={async () => {
            await logout();
            toggleProfile();
          }}
        >
          <svg viewBox="0 0 24 24" width="18" height="18" style={{ marginRight: '8px', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
            <polyline points="16 17 21 12 16 7" />
            <line x1="21" y1="12" x2="9" y2="12" />
          </svg>
          Sign Out
        </button>
      </div>
    </div>
  );
}
