import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  Modal,
  Pressable,
  ScrollView,
  ActivityIndicator,
  StyleSheet,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import ConditionalBlurView from './ConditionalBlurView';
import {
  fetchMovieGenres,
  fetchTvGenres,
  fetchLibraries,
  GenreItem,
} from '../core/HomeData';
import {
  fetchCollections,
  CollectionItem,
} from '../core/CollectionsData';

type BrowseModalProps = {
  visible: boolean;
  onClose: () => void;
  onSelectGenre: (genre: GenreItem, type: 'movie' | 'tv') => void;
  onSelectLibrary: (library: { key: string; title: string; type: string }) => void;
  onSelectCollections: () => void;
};

export default function BrowseModal({
  visible,
  onClose,
  onSelectGenre,
  onSelectLibrary,
  onSelectCollections,
}: BrowseModalProps) {
  const [loading, setLoading] = useState(true);
  const [movieGenres, setMovieGenres] = useState<GenreItem[]>([]);
  const [tvGenres, setTvGenres] = useState<GenreItem[]>([]);
  const [libraries, setLibraries] = useState<Array<{ key: string; title: string; type: string }>>([]);
  const [collections, setCollections] = useState<CollectionItem[]>([]);
  const [activeTab, setActiveTab] = useState<'movies' | 'tvshows' | 'libraries' | 'collections'>('movies');

  useEffect(() => {
    if (visible) {
      loadData();
    }
  }, [visible]);

  const loadData = async () => {
    setLoading(true);
    try {
      const [movies, tv, libs, colls] = await Promise.all([
        fetchMovieGenres(),
        fetchTvGenres(),
        fetchLibraries(),
        fetchCollections(),
      ]);
      setMovieGenres(movies);
      setTvGenres(tv);
      setLibraries(libs);
      setCollections(colls);
    } catch (e) {
      console.log('[BrowseModal] Error loading data:', e);
    } finally {
      setLoading(false);
    }
  };

  const renderGenreGrid = (genres: GenreItem[], type: 'movie' | 'tv') => {
    if (genres.length === 0) {
      return (
        <Text style={styles.emptyText}>No genres available</Text>
      );
    }

    return (
      <View style={styles.grid}>
        {genres.map((genre) => (
          <Pressable
            key={genre.key}
            style={styles.genreButton}
            onPress={() => {
              onSelectGenre(genre, type);
              onClose();
            }}
          >
            <Text style={styles.genreText}>{genre.title}</Text>
          </Pressable>
        ))}
      </View>
    );
  };

  const renderCollections = () => {
    return (
      <View style={styles.libraryList}>
        {/* All Collections button */}
        <Pressable
          style={styles.libraryButton}
          onPress={() => {
            onSelectCollections();
            onClose();
          }}
        >
          <View style={[styles.libraryIcon, { backgroundColor: 'rgba(100,100,255,0.2)' }]}>
            <Ionicons name="albums" size={24} color="#fff" />
          </View>
          <View style={styles.libraryInfo}>
            <Text style={styles.libraryTitle}>All Collections</Text>
            <Text style={styles.libraryType}>
              Browse all your Plex collections
            </Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#666" />
        </Pressable>

        {/* Show first few collections as preview */}
        {collections.slice(0, 5).map((coll) => (
          <Pressable
            key={coll.ratingKey}
            style={styles.libraryButton}
            onPress={() => {
              onSelectCollections();
              onClose();
            }}
          >
            <View style={[styles.libraryIcon, { backgroundColor: 'rgba(80,80,80,0.3)' }]}>
              <Ionicons name="albums-outline" size={24} color="#fff" />
            </View>
            <View style={styles.libraryInfo}>
              <Text style={styles.libraryTitle}>{coll.title}</Text>
              {coll.childCount !== undefined && (
                <Text style={styles.libraryType}>{coll.childCount} items</Text>
              )}
            </View>
            <Ionicons name="chevron-forward" size={20} color="#666" />
          </Pressable>
        ))}

        {collections.length === 0 && (
          <Text style={styles.emptyText}>No collections found</Text>
        )}
      </View>
    );
  };

  const renderLibraries = () => {
    if (libraries.length === 0) {
      return (
        <Text style={styles.emptyText}>No libraries available</Text>
      );
    }

    return (
      <View style={styles.libraryList}>
        {libraries.map((lib) => (
          <Pressable
            key={lib.key}
            style={styles.libraryButton}
            onPress={() => {
              onSelectLibrary(lib);
              onClose();
            }}
          >
            <View style={styles.libraryIcon}>
              <Ionicons
                name={lib.type === 'movie' ? 'film-outline' : 'tv-outline'}
                size={24}
                color="#fff"
              />
            </View>
            <View style={styles.libraryInfo}>
              <Text style={styles.libraryTitle}>{lib.title}</Text>
              <Text style={styles.libraryType}>
                {lib.type === 'movie' ? 'Movies' : 'TV Shows'}
              </Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color="#666" />
          </Pressable>
        ))}
      </View>
    );
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      transparent
      onRequestClose={onClose}
    >
      <View style={styles.container}>
        <ConditionalBlurView intensity={80} tint="dark" style={StyleSheet.absoluteFillObject} />

        <View style={styles.content}>
          {/* Header */}
          <View style={styles.header}>
            <Text style={styles.title}>Browse</Text>
            <Pressable onPress={onClose} style={styles.closeButton}>
              <Ionicons name="close" size={24} color="#fff" />
            </Pressable>
          </View>

          {/* Tabs */}
          <View style={styles.tabs}>
            <Pressable
              style={[styles.tab, activeTab === 'movies' && styles.tabActive]}
              onPress={() => setActiveTab('movies')}
            >
              <Text style={[styles.tabText, activeTab === 'movies' && styles.tabTextActive]}>
                Movies
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, activeTab === 'tvshows' && styles.tabActive]}
              onPress={() => setActiveTab('tvshows')}
            >
              <Text style={[styles.tabText, activeTab === 'tvshows' && styles.tabTextActive]}>
                TV Shows
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, activeTab === 'libraries' && styles.tabActive]}
              onPress={() => setActiveTab('libraries')}
            >
              <Text style={[styles.tabText, activeTab === 'libraries' && styles.tabTextActive]}>
                Libraries
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, activeTab === 'collections' && styles.tabActive]}
              onPress={() => setActiveTab('collections')}
            >
              <Text style={[styles.tabText, activeTab === 'collections' && styles.tabTextActive]}>
                Collections
              </Text>
            </Pressable>
          </View>

          {/* Content */}
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
              {activeTab === 'movies' && renderGenreGrid(movieGenres, 'movie')}
              {activeTab === 'tvshows' && renderGenreGrid(tvGenres, 'tv')}
              {activeTab === 'libraries' && renderLibraries()}
              {activeTab === 'collections' && renderCollections()}
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
    marginTop: 60,
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
    fontSize: 24,
    fontWeight: '800',
    color: '#fff',
  },
  closeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 8,
  },
  tab: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  tabActive: {
    backgroundColor: '#fff',
  },
  tabText: {
    color: '#888',
    fontWeight: '600',
    fontSize: 14,
  },
  tabTextActive: {
    color: '#000',
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
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  genreButton: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  genreText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  emptyText: {
    color: '#666',
    textAlign: 'center',
    marginTop: 40,
  },
  libraryList: {
    gap: 12,
  },
  libraryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  libraryIcon: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: 'rgba(229,9,20,0.2)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 16,
  },
  libraryInfo: {
    flex: 1,
  },
  libraryTitle: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 16,
  },
  libraryType: {
    color: '#888',
    fontSize: 13,
    marginTop: 2,
  },
});
