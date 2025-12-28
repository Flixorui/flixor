import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  Modal,
  Pressable,
  ScrollView,
  ActivityIndicator,
  StyleSheet,
  Dimensions,
  Platform,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import {
  fetchPersonDetails,
  fetchPersonCredits,
  getPersonProfileUrl,
  getTmdbImageUrl,
  PersonInfo,
  PersonCredit,
} from '../core/DetailsData';

interface PersonModalProps {
  visible: boolean;
  personId: number | null;
  personName?: string;
  onClose: () => void;
  onSelectCredit: (credit: PersonCredit) => void;
}

export default function PersonModal({
  visible,
  personId,
  personName,
  onClose,
  onSelectCredit,
}: PersonModalProps) {
  const [loading, setLoading] = useState(true);
  const [person, setPerson] = useState<PersonInfo | null>(null);
  const [credits, setCredits] = useState<PersonCredit[]>([]);
  const [showFullBio, setShowFullBio] = useState(false);

  const screenWidth = Dimensions.get('window').width;
  const posterWidth = (screenWidth - 48 - 2 * 8) / 3;

  useEffect(() => {
    if (visible && personId) {
      loadPersonData();
    } else {
      // Reset when closing
      setPerson(null);
      setCredits([]);
      setShowFullBio(false);
    }
  }, [visible, personId]);

  const loadPersonData = async () => {
    if (!personId) return;

    setLoading(true);
    try {
      const [personData, creditsData] = await Promise.all([
        fetchPersonDetails(personId),
        fetchPersonCredits(personId),
      ]);

      setPerson(personData);
      setCredits(creditsData);
    } catch (e) {
      console.log('[PersonModal] Error loading data:', e);
    } finally {
      setLoading(false);
    }
  };

  const formatDate = (dateString?: string): string => {
    if (!dateString) return '';
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
    } catch {
      return dateString;
    }
  };

  const calculateAge = (birthday?: string, deathday?: string): number | null => {
    if (!birthday) return null;
    const birth = new Date(birthday);
    const end = deathday ? new Date(deathday) : new Date();
    const age = Math.floor((end.getTime() - birth.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
    return age;
  };

  const profileUrl = getPersonProfileUrl(person?.profilePath, 'h632');
  const age = calculateAge(person?.birthday, person?.deathday);

  return (
    <Modal
      visible={visible}
      animationType="slide"
      transparent
      onRequestClose={onClose}
    >
      <View style={styles.container}>
        <BlurView intensity={80} tint="dark" style={StyleSheet.absoluteFillObject} />

        <View style={styles.content}>
          {/* Header */}
          <View style={styles.header}>
            <Text style={styles.title} numberOfLines={1}>
              {person?.name || personName || 'Loading...'}
            </Text>
            <Pressable onPress={onClose} style={styles.closeButton}>
              <Ionicons name="close" size={24} color="#fff" />
            </Pressable>
          </View>

          {loading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator color="#fff" size="large" />
            </View>
          ) : (
            <ScrollView
              style={styles.scrollView}
              contentContainerStyle={styles.scrollContent}
              showsVerticalScrollIndicator={false}
            >
              {/* Profile Section */}
              <View style={styles.profileSection}>
                {profileUrl ? (
                  <View style={styles.profileImageContainer}>
                    <FastImage
                      source={{
                        uri: profileUrl,
                        priority: FastImage.priority.high,
                        cache: FastImage.cacheControl.immutable,
                      }}
                      style={styles.profileImage}
                      resizeMode={FastImage.resizeMode.cover}
                    />
                  </View>
                ) : (
                  <View style={[styles.profileImageContainer, styles.profilePlaceholder]}>
                    <Ionicons name="person" size={48} color="#444" />
                  </View>
                )}

                <View style={styles.profileInfo}>
                  {person?.knownFor && (
                    <Text style={styles.knownFor}>{person.knownFor}</Text>
                  )}

                  {person?.birthday && (
                    <Text style={styles.infoText}>
                      Born: {formatDate(person.birthday)}
                      {age !== null && !person.deathday && ` (${age} years old)`}
                    </Text>
                  )}

                  {person?.deathday && (
                    <Text style={styles.infoText}>
                      Died: {formatDate(person.deathday)}
                      {age !== null && ` (${age} years old)`}
                    </Text>
                  )}

                  {person?.placeOfBirth && (
                    <Text style={styles.infoText} numberOfLines={2}>
                      {person.placeOfBirth}
                    </Text>
                  )}
                </View>
              </View>

              {/* Biography */}
              {person?.biography ? (
                <View style={styles.bioSection}>
                  <Text style={styles.sectionTitle}>Biography</Text>
                  <Text
                    style={styles.bioText}
                    numberOfLines={showFullBio ? undefined : 5}
                  >
                    {person.biography}
                  </Text>
                  {person.biography.length > 300 && (
                    <Pressable onPress={() => setShowFullBio(!showFullBio)}>
                      <Text style={styles.readMore}>
                        {showFullBio ? 'Show Less' : 'Read More'}
                      </Text>
                    </Pressable>
                  )}
                </View>
              ) : null}

              {/* Known For / Filmography */}
              {credits.length > 0 && (
                <View style={styles.creditsSection}>
                  <Text style={styles.sectionTitle}>Known For</Text>
                  <View style={styles.creditsGrid}>
                    {credits.map((credit) => (
                      <Pressable
                        key={`${credit.mediaType}:${credit.id}`}
                        onPress={() => {
                          onSelectCredit(credit);
                          onClose();
                        }}
                        style={[styles.creditItem, { width: posterWidth }]}
                      >
                        <View style={[styles.creditPoster, { width: posterWidth, height: posterWidth * 1.5 }]}>
                          {credit.posterPath ? (
                            <FastImage
                              source={{
                                uri: getTmdbImageUrl(credit.posterPath, 'w342'),
                                priority: FastImage.priority.normal,
                                cache: FastImage.cacheControl.immutable,
                              }}
                              style={{ width: '100%', height: '100%' }}
                              resizeMode={FastImage.resizeMode.cover}
                            />
                          ) : (
                            <View style={styles.creditPlaceholder}>
                              <Ionicons
                                name={credit.mediaType === 'movie' ? 'film-outline' : 'tv-outline'}
                                size={24}
                                color="#444"
                              />
                            </View>
                          )}
                        </View>
                        <Text style={styles.creditTitle} numberOfLines={2}>
                          {credit.title}
                        </Text>
                        {(credit.character || credit.job) && (
                          <Text style={styles.creditRole} numberOfLines={1}>
                            {credit.character || credit.job}
                          </Text>
                        )}
                        {credit.year && (
                          <Text style={styles.creditYear}>{credit.year}</Text>
                        )}
                      </Pressable>
                    ))}
                  </View>
                </View>
              )}
            </ScrollView>
          )}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  content: {
    flex: 1,
    marginTop: Platform.OS === 'ios' ? 60 : 40,
    backgroundColor: '#0d0d0f',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  title: {
    flex: 1,
    fontSize: 20,
    fontWeight: '800',
    color: '#fff',
    marginRight: 16,
  },
  closeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 40,
  },
  profileSection: {
    flexDirection: 'row',
    marginBottom: 20,
  },
  profileImageContainer: {
    width: 120,
    height: 160,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
  },
  profileImage: {
    width: '100%',
    height: '100%',
  },
  profilePlaceholder: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  profileInfo: {
    flex: 1,
    marginLeft: 16,
    justifyContent: 'center',
  },
  knownFor: {
    color: '#e50914',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
    textTransform: 'uppercase',
  },
  infoText: {
    color: '#aaa',
    fontSize: 14,
    marginBottom: 4,
    lineHeight: 20,
  },
  bioSection: {
    marginBottom: 24,
  },
  sectionTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 12,
  },
  bioText: {
    color: '#ccc',
    fontSize: 14,
    lineHeight: 22,
  },
  readMore: {
    color: '#e50914',
    fontSize: 14,
    fontWeight: '600',
    marginTop: 8,
  },
  creditsSection: {
    marginBottom: 24,
  },
  creditsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  creditItem: {
    marginBottom: 12,
  },
  creditPoster: {
    borderRadius: 10,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
  },
  creditPlaceholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1a1a1a',
  },
  creditTitle: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
    marginTop: 6,
  },
  creditRole: {
    color: '#888',
    fontSize: 12,
    marginTop: 2,
  },
  creditYear: {
    color: '#666',
    fontSize: 11,
    marginTop: 2,
  },
});
