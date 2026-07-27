import { useEffect, useState } from 'react';

export default function StatusBar() {
  const [timeStr, setTimeStr] = useState('');

  useEffect(() => {
    const updateTime = () => {
      const now = new Date();
      setTimeStr(
        now.toLocaleTimeString([], {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true,
        })
      );
    };

    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="status-bar">
      <div className="time">{timeStr || '4:39 AM'}</div>
      <div className="status-icons">
        {/* Signal Icon */}
        <svg viewBox="0 0 24 24" aria-label="Signal">
          <path
            d="M12 20V10M16 20V6M20 20V2M8 20v-5M4 20v-2"
            stroke="#fff"
            strokeWidth="2"
            strokeLinecap="round"
          />
        </svg>
        {/* Wifi Icon */}
        <svg viewBox="0 0 24 24" aria-label="Wifi">
          <path d="M12 20a2 2 0 100-4 2 2 0 000 4z" />
          <path
            d="M8.464 16.464A4.992 4.992 0 0112 15c1.38 0 2.632.56 3.536 1.464M5.636 13.636A8.981 8.981 0 0112 11c2.485 0 4.735 1.007 6.364 2.636M2.808 10.808A12.96 12.96 0 0112 7c3.59 0 6.838 1.455 9.192 3.808"
            stroke="#fff"
            strokeWidth="2"
            strokeLinecap="round"
            fill="none"
          />
        </svg>
        {/* Battery Icon */}
        <svg viewBox="0 0 24 24" aria-label="Battery">
          <rect
            x="2"
            y="7"
            width="16"
            height="10"
            rx="2"
            stroke="#fff"
            strokeWidth="2"
            fill="none"
          />
          <path
            d="M22 11v2"
            stroke="#fff"
            strokeWidth="2"
            strokeLinecap="round"
          />
          <rect x="4" y="9" width="10" height="6" rx="1" fill="#fff" />
        </svg>
      </div>
    </div>
  );
}
