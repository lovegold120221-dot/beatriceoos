/**
 * Profile Page Component
 */

import React from 'react';
import { useAuth } from '@/components/auth/AuthProvider';
import { useUI } from '@/lib/state';
import './ProfilePage.css';

export default function ProfilePage() {
  const { currentUser, logout } = useAuth();
  const { toggleProfile } = useUI();

  const getInitials = (name: string | null): string => {
    if (!name) return 'U';
    const names = name.split(' ');
    if (names.length === 1) return names[0].charAt(0).toUpperCase();
    return names[0].charAt(0).toUpperCase() + names[names.length - 1].charAt(0).toUpperCase();
  };

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
              // Auth flow will handle redirect
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
      {/* Profile Header */}
      <div className="profile-header">
        <div className="profile-avatar">
          {getInitials(currentUser.displayName || null)}
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
