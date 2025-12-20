import React, { useEffect, useState, useRef } from 'react';
import { View, Text, ActivityIndicator, ScrollView, Pressable, Animated, PanResponder, Dimensions, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Row from '../components/Row';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import BadgePill from '../components/BadgePill';
import { useNavigation } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { useFlixor } from '../core/FlixorContext';
import {
  fetchPlexMetadata,
  fetchPlexSeasons,
  fetchPlexSeasonEpisodes,
  fetchTmdbDetails,
  fetchTmdbLogo,
  fetchTmdbCredits,
  fetchTmdbSeasonsList,
  fetchTmdbSeasonEpisodes,
  fetchTmdbRecommendations,
  fetchTmdbSimilar,
  mapTmdbToPlex,
  getPlexImageUrl,
  getTmdbImageUrl,
  getTmdbProfileUrl,
  extractTmdbIdFromGuids,
  RowItem,
} from '../core/DetailsData';

let ExpoImage: any = null;
try { ExpoImage = require('expo-image').Image; } catch {}

type DetailsParams = {
  type: 'plex' | 'tmdb';
  ratingKey?: string;
  mediaType?: 'movie' | 'tv';
  id?: string;
};

type RouteParams = {
  route?: { params?: DetailsParams };
};

export default function Details({ route }: RouteParams) {
  const params: Partial<DetailsParams> = route?.params || {};
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const [loading, setLoading] = useState(true);
  const [meta, setMeta] = useState<any>(null);
  const [episodes, setEpisodes] = useState<any[]>([]);
  const [seasons, setSeasons] = useState<any[]>([]);
  const [seasonKey, setSeasonKey] = useState<string | null>(null);
  const [seasonSource, setSeasonSource] = useState<'plex'|'tmdb'|null>(null);
  const [tab, setTab] = useState<'episodes'|'suggested'|'details'>('suggested');
  const [tmdbCast, setTmdbCast] = useState<Array<{ name: string; profile_path?: string }>>([]);
  const [tmdbCrew, setTmdbCrew] = useState<Array<{ name: string; job?: string }>>([]);
  const [matchedPlex, setMatchedPlex] = useState<boolean>(false);
  const [mappedRk, setMappedRk] = useState<string | null>(null);
  const [noLocalSource, setNoLocalSource] = useState<boolean>(false);
  const [episodesLoading, setEpisodesLoading] = useState<boolean>(false);
  const [onDeck, setOnDeck] = useState<any | null>(null);
  const [closing, setClosing] = useState(false);
  const [dragging, setDragging] = useState(false);
  const y = useRef(new Animated.Value(0)).current;
  const panY = useRef(new Animated.Value(0)).current;
  const appear = useRef(new Animated.Value(0)).current;
  const overlayOpacity = useRef(new Animated.Value(1)).current;
  const scrollRef = useRef<ScrollView | null>(null);
  const nav: any = useNavigation();
  const screenH = Dimensions.get('window').height;
  const scrollYRef = useRef(0);
  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onStartShouldSetPanResponderCapture: () => false,
      onMoveShouldSetPanResponder: (_, g) => (!closing && scrollYRef.current <= 0 && Math.abs(g.dy) > 6),
      onMoveShouldSetPanResponderCapture: () => false,
      onPanResponderGrant: () => {
        setDragging(true);
      },
      onPanResponderMove: (_, g) => {
        if (closing) return;
        if (g.dy > 0) panY.setValue(g.dy);
      },
      onPanResponderRelease: (_, g) => {
        if (closing) return;
        const shouldClose = g.dy > 120 || g.vy > 1.0;
        if (shouldClose) {
          setClosing(true);
          // Fade overlay while sliding down the sheet together
          Animated.parallel([
            Animated.timing(panY, { toValue: screenH, duration: 180, useNativeDriver: true }),
            Animated.timing(overlayOpacity, { toValue: 0, duration: 180, useNativeDriver: true })
          ]).start(() => nav.goBack());
        } else {
          Animated.parallel([
            Animated.spring(panY, { toValue: 0, useNativeDriver: true, stiffness: 220, damping: 24, mass: 1 }),
            Animated.timing(overlayOpacity, { toValue: 1, duration: 120, useNativeDriver: true })
          ]).start(() => { setDragging(false); });
        }
      },
      onPanResponderTerminationRequest: () => false,
      onPanResponderTerminate: () => {
        setDragging(false);
        Animated.parallel([
          Animated.spring(panY, { toValue: 0, useNativeDriver: true, stiffness: 220, damping: 24, mass: 1 }),
          Animated.timing(overlayOpacity, { toValue: 1, duration: 120, useNativeDriver: true })
        ]).start();
      },
    })
  ).current;

  useEffect(() => {
    Animated.timing(appear, { toValue: 1, duration: 200, useNativeDriver: true }).start();
    // Hide TopBar and TabBar when Details screen is shown
    TopBarStore.setVisible(false);
    TopBarStore.setTabBarVisible(false);
    return () => {
      // Restore TopBar and TabBar when Details screen is closed
      TopBarStore.setVisible(true);
      TopBarStore.setTabBarVisible(true);
    };
  }, []);

  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      console.log('[Details] useEffect starting...');

      // Handle Plex type (direct ratingKey)
      if (params.type === 'plex' && params.ratingKey) {
        try {
          const m = await fetchPlexMetadata(params.ratingKey);
          if (!m) {
            setLoading(false);
            return;
          }
          const next: any = { ...m };
          setMatchedPlex(true);
          setMappedRk(String(params.ratingKey));

          // Try to fetch TMDB logo
          const tmdbId = extractTmdbIdFromGuids(m?.Guid || []);
          if (tmdbId) {
            const mediaType = m?.type === 'movie' ? 'movie' : 'tv';
            const logo = await fetchTmdbLogo(mediaType, Number(tmdbId));
            if (logo) next.logoUrl = logo;
          }

          setMeta(next);
          setTab(next?.type === 'show' ? 'episodes' : 'suggested');

          if (next?.type === 'show') {
            const seas = await fetchPlexSeasons(params.ratingKey);
            setSeasons(seas);
            setSeasonSource('plex');
            if (seas[0]?.ratingKey) {
              setSeasonKey(String(seas[0].ratingKey));
              setEpisodes(await fetchPlexSeasonEpisodes(String(seas[0].ratingKey)));
            }
          }
        } catch (e) {
          console.log('[Details] Plex metadata error:', e);
        }
      }

      // Handle TMDB type with Plex mapping fallback
      if (params.type === 'tmdb' && params.id && params.mediaType) {
        try {
          // Get TMDB details first
          const det = await fetchTmdbDetails(params.mediaType, Number(params.id));

          // Try to map TMDB to Plex
          const title = det?.title || det?.name;
          const year = (det?.release_date || det?.first_air_date || '').slice(0, 4);
          const mapped = await mapTmdbToPlex(params.mediaType, String(params.id), title, year);

          if (mapped?.ratingKey) {
            // Found in Plex - use Plex metadata
            const m = await fetchPlexMetadata(String(mapped.ratingKey));
            const next: any = { ...m };
            setMatchedPlex(true);
            setMappedRk(String(mapped.ratingKey));

            // Get TMDB logo
            const tmdbId = extractTmdbIdFromGuids(m?.Guid || []) || params.id;
            if (tmdbId) {
              const mediaType = m?.type === 'movie' ? 'movie' : 'tv';
              const logo = await fetchTmdbLogo(mediaType, Number(tmdbId));
              if (logo) next.logoUrl = logo;
            }

            setMeta(next);
            setTab(next?.type === 'show' ? 'episodes' : 'suggested');

            if (next?.type === 'show') {
              const seas = await fetchPlexSeasons(String(mapped.ratingKey));
              setSeasons(seas);
              setSeasonSource('plex');
              if (seas[0]?.ratingKey) {
                setSeasonKey(String(seas[0].ratingKey));
                setEpisodes(await fetchPlexSeasonEpisodes(String(seas[0].ratingKey)));
              }
            }
          } else {
            // Not in Plex - show TMDB details
            const back = det?.backdrop_path
              ? getTmdbImageUrl(det.backdrop_path, 'w1280')
              : det?.poster_path
                ? getTmdbImageUrl(det.poster_path, 'w780')
                : undefined;
            const genres = Array.isArray(det?.genres)
              ? det.genres.map((g: any) => ({ tag: g.name }))
              : [];

            setMeta({
              title: det?.title || det?.name || 'Title',
              summary: det?.overview,
              year: year,
              type: params.mediaType === 'movie' ? 'movie' : 'show',
              backdropUrl: back,
              Genre: genres,
            });
            setNoLocalSource(true);
            setMatchedPlex(false);
            setMappedRk(null);

            // Fetch TMDB credits
            const credits = await fetchTmdbCredits(params.mediaType, Number(params.id));
            setTmdbCast(credits.cast.map((c: any) => ({ name: c.name, profile_path: c.profile_path })));
            setTmdbCrew(credits.crew.map((c: any) => ({ name: c.name, job: c.job })));

            // For TV shows, populate seasons + episodes
            if (params.mediaType === 'tv') {
              const ss = await fetchTmdbSeasonsList(Number(params.id));
              if (ss.length) {
                setSeasons(ss.map((s) => ({ key: s.key, title: s.title })) as any);
                setSeasonKey(ss[0].key);
                const eps = await fetchTmdbSeasonEpisodes(Number(params.id), Number(ss[0].key));
                setEpisodes(eps);
                setSeasonSource('tmdb');
              }
            }
            setTab('suggested');
          }
        } catch {}
      }
      setLoading(false);
    })();
  }, []);

  console.log('[Details] Render - loading:', loading, 'isConnected:', isConnected, 'meta:', !!meta);

  if (flixorLoading || !isConnected || loading) {
    return (
      <View style={{ flex:1, backgroundColor:'#0b0b0b', alignItems:'center', justifyContent:'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  if (!meta) {
    return (
      <View style={{ flex:1, backgroundColor:'#0b0b0b', alignItems:'center', justifyContent:'center' }}>
        <Text style={{ color:'#fff' }}>No metadata available</Text>
      </View>
    );
  }

  console.log('[Details] Rendering full UI for:', meta?.title);

  const backdrop = () => {
    if (meta?.backdropUrl) return String(meta.backdropUrl);
    const path = meta?.art || meta?.thumb;
    return path ? getPlexImageUrl(path, 1080) : undefined;
  };
  const title = meta?.title || meta?.grandparentTitle || 'Title';
  const contentRating = meta?.contentRating || 'PG';
  // Badges parsing from Plex streams
  const media = (meta?.Media || [])[0] || {};
  const videoRes = media?.videoResolution;
  const isHD = videoRes && Number(videoRes) >= 720;
  const audioChannels = media?.audioChannels || 2;
  const streams = ((media?.Part || [])[0]?.Stream || []) as any[];
  const subtitleStreams = streams.filter(s => s.streamType === 3);
  const audioStreams = streams.filter(s => s.streamType === 2);
  const hasCC = subtitleStreams.some(s => String(s?.displayTitle || '').toLowerCase().includes('cc'));
  const hasAD = audioStreams.some(s => String(s?.displayTitle || '').toLowerCase().includes('description'));
  const hasDV = streams.some(s =>
    /dolby.?vision|dovi/i.test(String(s?.displayTitle || '')) ||
    /smpte2084|pq|hdr10/i.test(String(s?.colorTrc || ''))
  );

  // Keep overlay fully visible until the sheet is mostly offscreen, then fade.
  const backdropOpacity = panY.interpolate({ inputRange: [0, screenH * 0.8, screenH], outputRange: [1, 1, 0], extrapolate: 'clamp' });

  return (
    <SafeAreaView edges={['top']} style={{ flex:1, backgroundColor:'transparent' }}>
      <Animated.View style={{ flex:1, transform:[{ translateY: panY }] }} {...panResponder.panHandlers}>
        {/* Dim + blur backdrop under the modal so swiping reveals content behind, not black */}
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { opacity: backdropOpacity }]}>
          <BlurOverlay />
        </Animated.View>

        {/* Shadow under the sheet so any reveal looks natural, not a black jump */}
        <View style={{ position:'absolute', top:0, left:0, right:0, height:16, backgroundColor:'transparent', shadowColor:'#000', shadowOpacity:0.35, shadowRadius:14, shadowOffset:{ width:0, height:6 }, zIndex:1 }} />
        <View style={{ flex:1, backgroundColor:'#0d0d0f', borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden' }}>
      <ScrollView ref={ref => { scrollRef.current = ref; }}
        scrollEventThrottle={16}
        onScroll={(e:any) => { scrollYRef.current = e.nativeEvent.contentOffset.y; }}
        scrollEnabled={!closing}
        bounces={false}
        contentContainerStyle={{ paddingBottom: 32 }}
      >
        {/* Hero backdrop with rounded bottom corners */}
        <View style={{
          marginBottom: 12,
          borderBottomLeftRadius: 28,
          borderBottomRightRadius: 28,
          overflow: 'hidden',
        }}>
          <View style={{ width:'100%', aspectRatio: 16/9, backgroundColor:'#111' }}>
            {backdrop() && ExpoImage ? (
              <ExpoImage source={{ uri: backdrop() }} style={{ width:'100%', height:'100%' }} contentFit="cover" />
            ) : null}
            {/* Top-right actions over image */}
            <View style={{ position:'absolute', right: 12, top: 12, flexDirection:'row' }}>
              <Feather name="cast" size={25} color="#fff" style={{ marginHorizontal: 20 }} />
              <Pressable onPress={() => { nav.goBack(); }} style={{ width: 25, height: 25, borderRadius: 18, borderWidth: 1, borderColor: 'rgba(27,10,16,0.12)', backgroundColor: 'rgba(27,10,16,0.12)', alignItems: 'center', justifyContent: 'center', marginRight: 8 }}>
                <Ionicons name="close" color="#fff" size={18} />
              </Pressable>
            </View>
            {/* Gradient from image into content */}
            <LinearGradient
              colors={[ 'rgba(0,0,0,0.0)', 'rgba(13,13,15,0.85)', '#0d0d0f' ]}
              start={{ x: 0.5, y: 0.4 }} end={{ x: 0.5, y: 1.0 }}
              style={{ position:'absolute', left:0, right:0, bottom:0, height:'55%' }}
            />
            {/* TMDB logo overlay (center) if available */}
            {meta?.logoUrl && ExpoImage ? (
              <ExpoImage source={{ uri: meta.logoUrl }} style={{ position:'absolute', bottom: 24, left:'10%', right:'10%', height: 48 }} contentFit="contain" />
            ) : null}
          </View>
        </View>

        {/* Title */}
        <Text style={{ color:'#fff', fontSize:28, fontWeight:'800', marginHorizontal:16 }}>{title}</Text>

        {/* Badges */}
        <View style={{ flexDirection:'row', flexWrap:'wrap', gap:8, marginTop:12, marginHorizontal:16 }}>
          <BadgePill label={contentRating} />
          {isHD ? <BadgePill icon="hd" /> : null}
          <BadgePill icon="5.1" />
          {hasDV ? <BadgePill icon="dolby" /> : null}
          {hasCC ? <BadgePill icon="cc" /> : null}
          {hasAD ? <BadgePill icon="ad" /> : null}
          {matchedPlex ? <BadgePill label="Plex" /> : null}
          {!matchedPlex && params.type === 'tmdb' ? <BadgePill label="No local source" /> : null}
        </View>

        {/* Meta line */}
        <Text style={{ color:'#bbb', marginHorizontal:16, marginTop:8 }}>
          {meta?.year ? `${meta.year} • ` : ''}
          {meta?.type === 'show' ? `${meta?.leafCount || 0} Episodes` : (meta?.duration ? `${Math.round(meta.duration/60000)}m` : '')}
          {meta?.Genre?.length ? ` • ${meta.Genre.map((g:any)=>g.tag).slice(0,3).join(', ')}` : ''}
        </Text>

        {/* Play */}
        <Pressable
          disabled={!matchedPlex}
          onPress={() => {
            if (matchedPlex || params.type === 'plex') {
              const rk = mappedRk || params.ratingKey;
              if (rk) {
                console.log('[Details] Playing ratingKey:', rk);
                nav.navigate('Player', { type: 'plex', ratingKey: rk });
              }
            }
          }}
          style={{ marginHorizontal:16, marginTop:12, backgroundColor:'#fff', paddingVertical:12, borderRadius:12, alignItems:'center' }}
        >
          <Text style={{ color:'#000', fontWeight:'900', letterSpacing:2 }}>▶  PLAY</Text>
        </Pressable>

        {/* Actions */}
        <View style={{ flexDirection:'row', justifyContent:'space-around', marginTop:14 }}>
          <ActionIcon icon="play-circle-outline" label="TRAILER" />
          <ActionIcon icon="add" label="WATCHLIST" />
          <ActionIcon icon="download-outline" label="DOWNLOAD" />
        </View>

        {/* Synopsis */}
        {meta?.summary ? (
          <Text style={{ color:'#ddd', marginHorizontal:16, marginTop:16, lineHeight:20 }}>{meta.summary}</Text>
        ) : null}

        {/* Tabs (TV shows include Episodes; Movies omit Episodes) */}
        <Tabs tab={tab} setTab={setTab} showEpisodes={meta?.type === 'show' && (seasons.length > 0)} />

        {/* Content area */}
        <View style={{ marginTop:8 }}>
          {meta?.type === 'show' && tab === 'episodes' ? (
            <>
              <SeasonSelector seasons={seasons} seasonKey={seasonKey} onChange={async (key)=> {
                setSeasonKey(key);
                setEpisodesLoading(true);
                try {
                  if (seasonSource === 'plex') {
                    setEpisodes(await fetchPlexSeasonEpisodes(key));
                  } else if (seasonSource === 'tmdb') {
                    const tvId = route?.params?.id ? String(route?.params?.id) : undefined;
                    if (tvId) setEpisodes(await fetchTmdbSeasonEpisodes(Number(tvId), Number(key)));
                  }
                } finally {
                  setEpisodesLoading(false);
                }
              }} />
              <EpisodeList season={seasonKey} episodes={episodes} tmdbMode={seasonSource==='tmdb'} tmdbId={route?.params?.id ? String(route?.params?.id) : undefined} loading={episodesLoading} />
            </>
          ) : null}
          {tab === 'suggested' ? (
            <SuggestedRows meta={meta} routeParams={route?.params} />
          ) : null}
          {tab === 'details' ? (
            <DetailsTab meta={meta} tmdbCast={tmdbCast} tmdbCrew={tmdbCrew} />
          ) : null}
        </View>
      </ScrollView>
        </View>
      </Animated.View>
    </SafeAreaView>
  );
}

function BlurOverlay() {
  return (
    <View style={StyleSheet.absoluteFillObject}>
      <BlurView intensity={60} tint="dark" style={StyleSheet.absoluteFillObject} />
      <LinearGradient
        colors={[ 'rgba(10,10,10,0.22)', 'rgba(10,10,10,0.10)' ]}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
    </View>
  );
}

function Badge({ label }: { label: string }) {
  return (
    <View style={{ backgroundColor:'#262626', paddingHorizontal:10, paddingVertical:6, borderRadius:8 }}>
      <Text style={{ color:'#fff', fontWeight:'700' }}>{label}</Text>
    </View>
  );
}

function ActionIcon({ icon, label }: { icon: any; label: string }) {
  return (
    <View style={{ alignItems:'center' }}>
      <Ionicons name={icon} size={22} color="#fff" />
      <Text style={{ color:'#fff', marginTop:4, fontWeight:'600' }}>{label}</Text>
    </View>
  );
}

function EpisodeList({ season, episodes, tmdbMode, tmdbId, loading }: { season: string | null; episodes: any[]; tmdbMode?: boolean; tmdbId?: string; loading?: boolean }) {
  const nav: any = useNavigation();

  if (loading) {
    return (
      <View style={{ marginTop: 12, alignItems: 'center', paddingVertical: 20 }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  return (
    <View style={{ marginTop: 12 }}>
      <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginHorizontal:16, marginBottom:8 }}>Season {season}</Text>
      {episodes.map((ep:any, idx:number) => {
        const path = tmdbMode ? undefined : (ep.thumb || ep.art);
        const img = tmdbMode
          ? (ep.still_path ? getTmdbImageUrl(ep.still_path, 'w780') : undefined)
          : (path ? getPlexImageUrl(path, 640) : undefined);
        // Compute progress (Plex episodes only)
        let progress: number | undefined = undefined;
        if (!tmdbMode) {
          try {
            const dur = (ep.duration||0)/1000; const vo = (ep.viewOffset||0)/1000; const vc = ep.viewCount||0;
            if (vc > 0) progress = 100;
            else if (dur > 0 && vo/dur >= 0.95) progress = 100;
            else if (dur > 0) progress = Math.round((vo/dur)*100);
          } catch {}
        }
        return (
          <Pressable
            key={idx}
            onPress={() => {
              if (!tmdbMode && ep.ratingKey) {
                console.log('[Details] Playing episode:', ep.ratingKey);
                nav.navigate('Player', { type: 'plex', ratingKey: String(ep.ratingKey) });
              }
            }}
            style={{ flexDirection:'row', marginHorizontal:16, marginBottom:12 }}
          >
            <View style={{ width:140, height:78, borderRadius:10, overflow:'hidden', backgroundColor:'#222' }}>
              {img && ExpoImage ? (
                <ExpoImage source={{ uri: img }} style={{ width:'100%', height:'100%' }} contentFit="cover" />
              ) : null}
              {typeof progress === 'number' && progress > 0 ? (
                <View style={{ position:'absolute', left:0, right:0, bottom:0, height:4, backgroundColor:'#ffffff33' }}>
                  <View style={{ width: `${Math.min(100, Math.max(0, progress))}%`, height:'100%', backgroundColor:'#fff' }} />
                </View>
              ) : null}
            </View>
            <View style={{ flex:1, marginLeft:12, justifyContent:'center' }}>
              <Text style={{ color:'#fff', fontWeight:'800' }}>{idx+1}. {ep.title || ep.name || 'Episode'}</Text>
              <Text style={{ color:'#bbb', marginTop:2 }}>
                {tmdbMode ? (ep.runtime ? `${ep.runtime}m` : '') : (ep.duration ? `${Math.round(ep.duration/60000)}m` : '')}
              </Text>
            </View>
            <Ionicons name="download-outline" size={18} color="#fff" style={{ alignSelf:'center' }} />
          </Pressable>
        );
      })}
    </View>
  );
}

function Tabs({ tab, setTab, showEpisodes }: { tab: 'episodes'|'suggested'|'details'; setTab: (t:any)=>void; showEpisodes: boolean }) {
  const tabs: Array<{ key: any; label: string }> = showEpisodes
    ? [ { key:'episodes', label:'EPISODES' }, { key:'suggested', label:'SUGGESTED' }, { key:'details', label:'DETAILS' } ]
    : [ { key:'suggested', label:'SUGGESTED' }, { key:'details', label:'DETAILS' } ];
  return (
    <View style={{ marginTop:18 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal:16 }}>
        {tabs.map(t => (
          <Pressable key={t.key} onPress={()=> setTab(t.key)} style={{ marginRight:28 }}>
            <Text style={{ color:'#fff', fontWeight:'900', letterSpacing:1.2, fontSize:14 }}>{t.label}</Text>
            {tab===t.key ? <View style={{ height:4, backgroundColor:'#fff', marginTop:6, borderRadius:2 }} /> : <View style={{ height:4, backgroundColor:'transparent', marginTop:6 }} />}
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

function SuggestedRows({ meta, routeParams }: { meta: any; routeParams?: any }) {
  const [recs, setRecs] = React.useState<RowItem[]>([]);
  const [similar, setSimilar] = React.useState<RowItem[]>([]);
  const [loading, setLoading] = React.useState(true);
  const tmdbId = React.useMemo(() => {
    try {
      // Prefer Plex GUID (meta) if available
      const guids: string[] = Array.isArray(meta?.Guid) ? meta.Guid.map((g:any)=> String(g.id||'')) : [];
      const tmdbGuid = guids.find(g=> g.includes('tmdb://') || g.includes('themoviedb://'));
      if (tmdbGuid) return tmdbGuid.split('://')[1];
      // Fallback to route param for TMDB-only details
      const pid = routeParams?.id; return pid ? String(pid) : null;
    } catch { return null; }
  }, [meta, routeParams]);
  const mediaType: 'movie'|'tv' = React.useMemo(() => {
    if (meta?.type === 'movie' || meta?.type === 'show') return (meta.type === 'movie') ? 'movie' : 'tv';
    const rt = routeParams?.mediaType; return rt === 'movie' ? 'movie' : 'tv';
  }, [meta, routeParams]);

  React.useEffect(() => {
    (async () => {
      try {
        if (!tmdbId) return setLoading(false);
        const [r, s] = await Promise.all([
          fetchTmdbRecommendations(mediaType, Number(tmdbId)),
          fetchTmdbSimilar(mediaType, Number(tmdbId))
        ]);
        setRecs(r);
        setSimilar(s);
      } finally {
        setLoading(false);
      }
    })();
  }, [tmdbId, mediaType]);

  const getUri = (it: RowItem) => it.image;
  const getTitle = (it: RowItem) => it.title;
  const nav: any = useNavigation();
  const onPress = (it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      nav.navigate('Details', { type:'plex', ratingKey: rk });
    } else if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      nav.navigate('Details', { type:'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  };

  if (loading) return <Text style={{ color:'#888', marginHorizontal:16 }}>Loading…</Text>;
  if (!recs.length && !similar.length) return <Text style={{ color:'#888', marginHorizontal:16 }}>No suggestions</Text>;
  return (
    <View style={{ marginLeft: 12 }}>
      {recs.length > 0 && (
        <Row title="Recommended" items={recs}
          getImageUri={getUri} getTitle={getTitle}
          onItemPress={onPress}
          onTitlePress={() => recs[0] && onPress(recs[0])}
        />
      )}
      {similar.length > 0 && (
        <Row title="More Like This" items={similar}
          getImageUri={getUri} getTitle={getTitle}
          onItemPress={onPress}
          onTitlePress={() => similar[0] && onPress(similar[0])}
        />
      )}
    </View>
  );
}

function SectionHeader({ title }: { title: string }) {
  return (
    <Text style={{ color:'#fff', fontSize:18, fontWeight:'800', marginHorizontal:16, marginTop:18 }}>{title}</Text>
  );
}

function KeyValue({ k, v }: { k: string; v?: string }) {
  if (!v) return null;
  return (
    <View style={{ flexDirection:'row', justifyContent:'space-between', paddingHorizontal:16, paddingVertical:8 }}>
      <Text style={{ color:'#aaa' }}>{k}</Text>
      <Text style={{ color:'#eee', marginLeft:12, flexShrink:1, textAlign:'right' }}>{v}</Text>
    </View>
  );
}

function RatingsRow({ meta }: { meta: any }) {
  // Parse ratings from Plex metadata if available
  const ratings: any[] = Array.isArray(meta?.Rating) ? meta.Rating : [];
  let imdb: number | undefined;
  let rtCritic: number | undefined;
  let rtAudience: number | undefined;
  try {
    ratings.forEach((r:any) => {
      const img = String(r?.image || '').toLowerCase();
      const val = typeof r?.value === 'number' ? r.value : Number(r?.value);
      if (img.includes('imdb://image.rating')) imdb = val;
      if (img.includes('rottentomatoes://image.rating.ripe') || img.includes('rottentomatoes://image.rating.rotten')) rtCritic = val ? Math.round(val * 10) : undefined;
      if (img.includes('rottentomatoes://image.rating.upright')) rtAudience = val ? Math.round(val * 10) : undefined;
    });
  } catch {}

  // Fallbacks from top-level fields if present
  if (!imdb && typeof meta?.rating === 'number') imdb = meta.rating;
  if (!rtAudience && typeof meta?.audienceRating === 'number') rtAudience = Math.round(meta.audienceRating * 10);

  if (!imdb && !rtCritic && !rtAudience) return null;
  return (
    <View style={{ flexDirection:'row', alignItems:'center', marginTop:8, marginHorizontal:16 }}>
      {typeof imdb === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center', marginRight:16 }}>
          <Ionicons name="star" size={16} color="#f5c518" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>IMDb {imdb.toFixed(1)}</Text>
        </View>
      ) : null}
      {typeof rtCritic === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center', marginRight:16 }}>
          <Ionicons name="leaf-outline" size={16} color="#66bb6a" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>Tomatometer {rtCritic}%</Text>
        </View>
      ) : null}
      {typeof rtAudience === 'number' ? (
        <View style={{ flexDirection:'row', alignItems:'center' }}>
          <Ionicons name="people-outline" size={16} color="#90caf9" />
          <Text style={{ color:'#fff', fontWeight:'700', marginLeft:6 }}>Audience {rtAudience}%</Text>
        </View>
      ) : null}
    </View>
  );
}

function CastScroller({ meta, tmdbCast }: { meta:any; tmdbCast?: Array<{ name: string; profile_path?: string }> }) {
  const roles: any[] = Array.isArray(meta?.Role) ? meta.Role.slice(0, 16) : [];
  const useTmdb = !roles.length && Array.isArray(tmdbCast) && tmdbCast.length > 0;
  if (!roles.length && !useTmdb) return null;
  return (
    <View style={{ marginTop:8 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal:12 }}>
        {(useTmdb ? tmdbCast! : roles).map((r:any, idx:number) => {
          const src = useTmdb
            ? (r.profile_path ? getTmdbProfileUrl(r.profile_path) : undefined)
            : (r.thumb ? getPlexImageUrl(r.thumb, 200) : undefined);
          const name = useTmdb ? r.name : (r.tag || r.title);
          return (
            <View key={idx} style={{ width:96, marginHorizontal:4, alignItems:'center' }}>
              <View style={{ width:72, height:72, borderRadius:36, overflow:'hidden', backgroundColor:'#1a1a1a' }}>
                {src && ExpoImage ? <ExpoImage source={{ uri: src }} style={{ width:'100%', height:'100%' }} contentFit="cover" /> : null}
              </View>
              <Text style={{ color:'#eee', marginTop:6 }} numberOfLines={1}>{name}</Text>
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
}

function CrewList({ meta, tmdbCrew }: { meta:any; tmdbCrew?: Array<{ name: string; job?: string }> }) {
  const directors: any[] = Array.isArray(meta?.Director) ? meta.Director : [];
  const writers: any[] = Array.isArray(meta?.Writer) ? meta.Writer : [];
  let dirNames: string[] = directors.map((d:any)=> d.tag || d.title);
  let writerNames: string[] = writers.map((w:any)=> w.tag || w.title);
  if (!dirNames.length && Array.isArray(tmdbCrew)) dirNames = tmdbCrew.filter(c=> /director/i.test(String(c.job||''))).map(c=> c.name);
  if (!writerNames.length && Array.isArray(tmdbCrew)) writerNames = tmdbCrew.filter(c=> /(writer|screenplay)/i.test(String(c.job||''))).map(c=> c.name);
  if (!dirNames.length && !writerNames.length) return null;
  return (
    <View style={{ marginTop:4, paddingHorizontal:16 }}>
      {dirNames.length ? (
        <View style={{ marginBottom:8 }}>
          <Text style={{ color:'#aaa', marginBottom:6 }}>Directors</Text>
          <Text style={{ color:'#eee' }}>{dirNames.join(', ')}</Text>
        </View>
      ) : null}
      {writerNames.length ? (
        <View style={{ marginBottom:8 }}>
          <Text style={{ color:'#aaa', marginBottom:6 }}>Writers</Text>
          <Text style={{ color:'#eee' }}>{writerNames.join(', ')}</Text>
        </View>
      ) : null}
    </View>
  );
}

function TechSpecs({ meta }: { meta:any }) {
  const m = (meta?.Media || [])[0] || {};
  if (!m) return null;
  const container = m?.container;
  const vCodec = m?.videoCodec || (m as any)?.videoCodecTag;
  const aCodec = m?.audioCodec;
  const res = m?.width && m?.height ? `${m.width}x${m.height}` : (m?.videoResolution ? `${m.videoResolution}p` : undefined);
  const bitrate = m?.bitrate ? `${m.bitrate} kbps` : undefined;
  const hdr = (() => {
    if (!Array.isArray(m?.Part)) return undefined;
    const streams = (m.Part[0]?.Stream || []) as any[];
    const s = streams.find(s => /dolby.?vision|dovi/i.test(String(s?.displayTitle||'')) || /smpte2084|pq|hdr10/i.test(String(s?.colorTrc||'')));
    if (!s) return undefined;
    if (/dolby.?vision|dovi/i.test(String(s?.displayTitle||''))) return 'Dolby Vision';
    return 'HDR10';
  })();

  return (
    <View style={{ marginTop:8 }}>
      <KeyValue k="Resolution" v={res} />
      <KeyValue k="Video" v={vCodec} />
      <KeyValue k="Audio" v={aCodec} />
      <KeyValue k="Container" v={container} />
      <KeyValue k="Bitrate" v={bitrate} />
      <KeyValue k="HDR" v={hdr} />
    </View>
  );
}

function Collections({ meta }: { meta:any }) {
  const cols: any[] = Array.isArray(meta?.Collection) ? meta.Collection : [];
  if (!cols.length) return null;
  return (
    <View style={{ flexDirection:'row', flexWrap:'wrap', paddingHorizontal:12, marginTop:8 }}>
      {cols.map((c:any, idx:number) => (
        <View key={idx} style={{ margin:4, paddingHorizontal:10, paddingVertical:6, borderRadius:999, backgroundColor:'#1a1b20', borderWidth:1, borderColor:'#2a2b30' }}>
          <Text style={{ color:'#fff', fontWeight:'700' }}>{c.tag || c.title}</Text>
        </View>
      ))}
    </View>
  );
}

function DetailsTab({ meta, tmdbCast, tmdbCrew }: { meta:any; tmdbCast?: Array<{ name: string; profile_path?: string }>; tmdbCrew?: Array<{ name: string; job?: string }> }) {
  const guids: string[] = Array.isArray(meta?.Guid) ? meta.Guid.map((g:any)=> String(g.id||'')) : [];
  const imdbId = guids.find(x=> x.startsWith('imdb://'))?.split('://')[1];
  const tmdbId = guids.find(x=> x.includes('tmdb://') || x.includes('themoviedb://'))?.split('://')[1];

  return (
    <View>
      <SectionHeader title="Ratings" />
      <RatingsRow meta={meta} />

      <SectionHeader title="Cast" />
      <CastScroller meta={meta} tmdbCast={tmdbCast} />

      <SectionHeader title="Crew" />
      <CrewList meta={meta} tmdbCrew={tmdbCrew} />

      <SectionHeader title="Technical" />
      <TechSpecs meta={meta} />

      <SectionHeader title="Collections" />
      <Collections meta={meta} />

      <SectionHeader title="Info" />
      <KeyValue k="Studio" v={meta?.studio} />
      <KeyValue k="Year" v={meta?.year ? String(meta.year) : undefined} />
      <KeyValue k="Content Rating" v={meta?.contentRating} />
      <KeyValue k="IMDb" v={imdbId ? `https://www.imdb.com/title/${imdbId}` : undefined} />
      <KeyValue k="TMDB" v={tmdbId ? `https://www.themoviedb.org/${meta?.type==='movie'?'movie':'tv'}/${tmdbId}` : undefined} />
      <View style={{ height:12 }} />
    </View>
  );
}

function SeasonSelector({ seasons, seasonKey, onChange }: { seasons:any[]; seasonKey:string|null; onChange:(key:string)=>void }) {
  if (!seasons?.length) return null;
  return (
    <View style={{ flexDirection:'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal:16, marginBottom:8 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        {seasons.map((s:any, idx:number) => {
          const key = String(s.ratingKey || s.key || idx);
          const active = key === seasonKey;
          return (
            <Pressable key={key} onPress={()=> onChange(key)} style={{ marginRight:10, paddingHorizontal:12, paddingVertical:8, borderRadius:999, backgroundColor: active? '#ffffff22' : '#1a1b20', borderWidth:1, borderColor: active? '#ffffff' : '#2a2b30' }}>
              <Text style={{ color:'#fff', fontWeight:'700' }}>{s.title || `Season ${s.index || (idx+1)}`}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
      
    </View>
  );
}
