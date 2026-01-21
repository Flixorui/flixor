import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Pressable,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import type { PlexHomeUser } from '@flixor/core';
import {
  getHomeUsers,
  getActiveProfile,
  switchProfile,
  switchToMainAccount,
  type ActiveProfile,
} from '../core/ProfileService';
import ProfileAvatar from '../components/ProfileAvatar';
import PinEntryModal from '../components/PinEntryModal';

interface ProfileSelectProps {
  onProfileSelected?: () => void;
  onClose?: () => void;
}

export default function ProfileSelect({
  onProfileSelected,
  onClose,
}: ProfileSelectProps) {
  const insets = useSafeAreaInsets();

  const [users, setUsers] = useState<PlexHomeUser[]>([]);
  const [activeProfile, setActiveProfile] = useState<ActiveProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [switching, setSwitching] = useState<number | null>(null);

  // PIN modal state
  const [pinModalUser, setPinModalUser] = useState<PlexHomeUser | null>(null);
  const [pinError, setPinError] = useState<string | null>(null);
  const [pinLoading, setPinLoading] = useState(false);

  const loadProfiles = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }

    try {
      const [homeUsers, current] = await Promise.all([
        getHomeUsers(),
        getActiveProfile(),
      ]);
      setUsers(homeUsers);
      setActiveProfile(current);
    } catch (e) {
      console.log('[ProfileSelect] Error loading profiles:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadProfiles();
  }, [loadProfiles]);

  const handleSelectProfile = async (user: PlexHomeUser) => {
    // Check if this is the currently active profile
    if (activeProfile && activeProfile.userId === user.id) {
      // Already on this profile, just close
      onProfileSelected?.();
      return;
    }

    // If protected, show PIN modal
    if (user.protected) {
      setPinModalUser(user);
      setPinError(null);
      return;
    }

    await doSwitch(user);
  };

  const handlePinSubmit = async (pin: string) => {
    if (!pinModalUser) return;

    setPinError(null);
    setPinLoading(true);

    try {
      await doSwitch(pinModalUser, pin);
      setPinModalUser(null);
    } catch (e: any) {
      setPinError(e.message || 'Invalid PIN');
    } finally {
      setPinLoading(false);
    }
  };

  const doSwitch = async (user: PlexHomeUser, pin?: string) => {
    setSwitching(user.id);
    try {
      await switchProfile(user, pin);
      setActiveProfile({
        userId: user.id,
        uuid: user.uuid,
        title: user.title,
        thumb: user.thumb,
        restricted: user.restricted,
        protected: user.protected,
      });
      onProfileSelected?.();
    } catch (e: any) {
      throw e;
    } finally {
      setSwitching(null);
    }
  };

  const handleSwitchToMain = async () => {
    if (!activeProfile) {
      // Already on main
      onProfileSelected?.();
      return;
    }

    setSwitching(-1); // Special ID for main
    try {
      await switchToMainAccount();
      setActiveProfile(null);
      onProfileSelected?.();
    } catch (e) {
      console.error('[ProfileSelect] Error switching to main:', e);
    } finally {
      setSwitching(null);
    }
  };

  if (loading) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#e5a00d" />
          <Text style={styles.loadingText}>Loading profiles...</Text>
        </View>
      </View>
    );
  }

  if (users.length === 0) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          {onClose && (
            <Pressable style={styles.closeButton} onPress={onClose}>
              <Ionicons name="close" size={24} color="#fff" />
            </Pressable>
          )}
          <Text style={styles.title}>Profiles</Text>
        </View>
        <View style={styles.emptyContainer}>
          <Ionicons name="people-outline" size={64} color="#6b7280" />
          <Text style={styles.emptyTitle}>No Plex Home</Text>
          <Text style={styles.emptyText}>
            This account is not part of a Plex Home. Create a Plex Home to
            manage family profiles.
          </Text>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        {onClose && (
          <Pressable style={styles.closeButton} onPress={onClose}>
            <Ionicons name="close" size={24} color="#fff" />
          </Pressable>
        )}
        <Text style={styles.title}>Who's watching?</Text>
        <Text style={styles.subtitle}>Select your profile</Text>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadProfiles(true)}
            tintColor="#e5a00d"
          />
        }
      >
        {/* Home Users Grid */}
        <View style={styles.profilesGrid}>
          {users.map((user) => {
            const isCurrentProfile =
              activeProfile && activeProfile.userId === user.id;

            return (
              <Pressable
                key={user.id}
                style={styles.profileCard}
                onPress={() => handleSelectProfile(user)}
                disabled={switching !== null}
              >
                <View style={styles.profileContent}>
                  <View style={styles.avatarContainer}>
                    {switching === user.id ? (
                      <ActivityIndicator size="large" color="#e5a00d" />
                    ) : (
                      <ProfileAvatar
                        thumb={user.thumb}
                        title={user.title}
                        size={70}
                        isActive={!!isCurrentProfile}
                        isRestricted={user.restricted}
                        isProtected={user.protected}
                      />
                    )}
                  </View>
                  <Text
                    style={styles.profileName}
                    numberOfLines={1}
                    ellipsizeMode="tail"
                  >
                    {user.title}
                  </Text>
                  {isCurrentProfile && (
                    <View style={styles.currentBadge}>
                      <Text style={styles.currentBadgeText}>Current</Text>
                    </View>
                  )}
                  {user.admin && !isCurrentProfile && (
                    <View style={styles.adminBadge}>
                      <Text style={styles.adminBadgeText}>Admin</Text>
                    </View>
                  )}
                </View>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>

      {/* PIN Entry Modal */}
      <PinEntryModal
        visible={!!pinModalUser}
        profileName={pinModalUser?.title || ''}
        onSubmit={handlePinSubmit}
        onCancel={() => {
          setPinModalUser(null);
          setPinError(null);
        }}
        error={pinError}
        loading={pinLoading}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d0d0d',
  },
  header: {
    paddingHorizontal: 20,
    paddingVertical: 16,
    alignItems: 'center',
  },
  closeButton: {
    position: 'absolute',
    right: 16,
    top: 16,
    padding: 8,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#9ca3af',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: '#9ca3af',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 40,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#fff',
    marginTop: 16,
    marginBottom: 8,
  },
  emptyText: {
    fontSize: 14,
    color: '#9ca3af',
    textAlign: 'center',
    lineHeight: 20,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingBottom: 40,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 24,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: '#333',
  },
  dividerText: {
    marginHorizontal: 12,
    fontSize: 12,
    color: '#6b7280',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  profilesGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: 16,
  },
  profileCard: {
    alignItems: 'center',
    padding: 16,
    borderRadius: 16,
    backgroundColor: '#1a1b20',
    width: 130,
  },
  profileContent: {
    alignItems: 'center',
  },
  avatarContainer: {
    width: 76,
    height: 76,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  profileName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#fff',
    textAlign: 'center',
    maxWidth: 100,
  },
  currentBadge: {
    marginTop: 8,
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: '#e5a00d',
    borderRadius: 4,
  },
  currentBadgeText: {
    fontSize: 10,
    fontWeight: '700',
    color: '#000',
  },
  adminBadge: {
    marginTop: 8,
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: '#3498db',
    borderRadius: 4,
  },
  adminBadgeText: {
    fontSize: 10,
    fontWeight: '700',
    color: '#fff',
  },
});
