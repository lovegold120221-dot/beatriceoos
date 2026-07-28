import { useUI } from '@/lib/state';
import ProfilePage from '@/src/app/profile/ProfilePage';
import c from 'classnames';

export default function ProfilePanel() {
  const { showProfile, toggleProfile } = useUI();

  return (
    <aside className={c('profile-panel', { open: showProfile })}>
      <div className="profile-panel-header">
        <h3>Profile</h3>
        <button onClick={toggleProfile} className="close-button">
          <span className="icon">&times;</span>
        </button>
      </div>
      <div className="profile-panel-content">
        <ProfilePage />
      </div>
    </aside>
  );
}