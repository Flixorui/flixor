import { useState } from 'react';
import { profileInitials } from '@/services/profiles';

type ProfileAvatarProps = {
  name: string;
  thumb?: string;
  size?: number;
  ring?: boolean;
};

/** Round avatar: the Plex picture, or initials on the accent color. */
export default function ProfileAvatar({ name, thumb, size = 28, ring = false }: ProfileAvatarProps) {
  const [failed, setFailed] = useState(false);
  const ringClass = ring ? 'ring-2 ring-brand' : '';
  if (thumb && !failed) {
    return (
      <img
        src={thumb}
        alt=""
        onError={() => setFailed(true)}
        style={{ width: size, height: size }}
        className={`rounded-full object-cover ${ringClass}`}
      />
    );
  }
  return (
    <span
      style={{ width: size, height: size, fontSize: Math.max(11, size * 0.38) }}
      className={`rounded-full bg-brand text-white font-bold flex items-center justify-center ${ringClass}`}
    >
      {profileInitials(name)}
    </span>
  );
}
