/**
 * Profile Page Component
 */

import React from 'react';
import { useAuth } from '@/components/auth/AuthProvider';
import { Link } from 'react-router-dom';

export default function ProfilePage() {
  const { currentUser } = useAuth();

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
          <Link to="/auth" className="btn btn-primary">
            Sign In
          </Link>
        </div>
      </div>
    );
  }

  const profile = {
    name: currentUser.displayName || currentUser.email?.split('@')[0] || 'User',
    email: currentUser.email || 'No email',
    joinDate: '2024-01-15',
    sessionCount: 47,
    favoriteTools: ['customer-support', 'personal-assistant'],
  };

  return (
    <div className="profile-page">
      <div className="profile-header">
        <div className="profile-avatar">
          {getInitials(profile.name)}
        </div>
        <div className="profile-info">
          <h2>{profile.name}</h2>
          <p className="text-muted">{profile.email}</p>
          <p className="text-muted">Joined {new Date(profile.joinDate).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</p>
        </div>
      </div>

      <div className="profile-section">
        <h3>Statistics</h3>
        <div className="profile-stats">
          <div className="stat-item">
            <div className="stat-value">{profile.sessionCount}</div>
            <div className="stat-label">Sessions</div>
          </div>
          <div className="stat-item">
            <div className="stat-value">{profile.favoriteTools.length}</div>
            <div className="stat-label">Favorite Tools</div>
          </div>
        </div>
      </div>

      <div className="profile-section">
        <h3>Favorite Tools</h3>
        <div className="tool-list">
          {profile.favoriteTools.map(tool => (
            <div key={tool} className="tool-item">
              <span className="tool-name">{tool.replace('-', ' ')}</span>
            </div>
          ))}
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
