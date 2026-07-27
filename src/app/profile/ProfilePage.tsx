/**
 * Profile Page Component
 */

import React from 'react';
import { useAuth } from '@/components/auth/AuthProvider';
import { Link } from 'react-router-dom';

export default function ProfilePage() {
  const { currentUser } = useAuth();

  if (!currentUser) {
    return (
      <div className="profile-page">
        <div className="profile-section">
          <h3>Authentication Required</h3>
          <p>Please sign in to view your profile and account information.</p>
          <Link to="/auth" className="btn btn-primary">
            Sign In
          </Link>
        </div>
      </div>
    );
  }

  const getInitials = (name: string | null): string => {
    if (!name) return 'U';
    const names = name.split(' ');
    if (names.length === 1) return names[0].charAt(0).toUpperCase();
    return names[0].charAt(0).toUpperCase() + names[names.length - 1].charAt(0).toUpperCase();
  };

  return (
    <div className="profile-page">
      <div className="profile-header">
        <div className="profile-avatar">
          {getInitials(currentUser.displayName)}
        </div>
        <div className="profile-info">
          <h2>{currentUser.displayName || 'User'}</h2>
          <p className="text-muted">{currentUser.email}</p>
          <p className="text-muted">Provider: {currentUser.provider || 'N/A'}</p>
        </div>
      </div>

      <div className="profile-section">
        <h3>Account Details</h3>
        <div className="profile-details">
          <p><strong>User ID:</strong> {currentUser.uid}</p>
          <p><strong>Authentication Status:</strong> Verified</p>
        </div>
      </div>

      <div className="profile-actions">
        <Link to="/account/settings" className="btn btn-primary">
          Account Settings
        </Link>
        <Link to="/history" className="btn">
          View History
        </Link>
      </div>
    </div>
  );
}
