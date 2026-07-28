import { useEffect, useState } from 'react';
import { useDeviceControl } from '@/lib/state';

export default function StatusBar() {
  const [timeStr, setTimeStr] = useState('');
  const { mobileUseConnected } = useDeviceControl();

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
    </div>
  );
}
