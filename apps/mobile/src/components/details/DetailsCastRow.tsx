/**
 * Cast & Crew row: cast (or an episode's guest stars) with character names, then key crew
 * with their jobs, as round photo cards.
 * macOS reference: Views/Details/DetailsCastAndTechnical.swift (CastCrewCircleCard)
 */

import React, { useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import { findTmdbPersonIdByName, getPlexImageUrl, getTmdbProfileUrl } from '../../core/DetailsData';

export interface DetailsCastMember {
  id?: number;
  name: string;
  character?: string;
  profile_path?: string | null;
}

export interface DetailsCrewMember {
  id?: number;
  name: string;
  job?: string;
  department?: string;
  profile_path?: string | null;
}

interface CardPerson {
  id?: number;
  name: string;
  role?: string;
  image?: string;
}

const CAST_LIMIT = 12;
const CREW_LIMIT = 4;

/** Directors first, then writers: the crew a viewer recognises. */
function keyCrew(crew: DetailsCrewMember[], plexDirectors: string[], plexWriters: string[], creators: string[]): CardPerson[] {
  const people: CardPerson[] = [];
  const seen = new Set<string>();
  const add = (person: CardPerson) => {
    const key = person.name.trim().toLowerCase();
    if (!key || seen.has(key) || people.length >= CREW_LIMIT) return;
    seen.add(key);
    people.push(person);
  };
  const fromTmdb = (match: (c: DetailsCrewMember) => boolean) =>
    crew.filter(match).forEach((c) =>
      add({ id: c.id, name: c.name, role: c.job, image: c.profile_path ? getTmdbProfileUrl(c.profile_path) : undefined })
    );

  creators.forEach((name) => add({ name, role: 'Creator' }));
  fromTmdb((c) => c.job === 'Director');
  plexDirectors.forEach((name) => add({ name, role: 'Director' }));
  fromTmdb((c) => /^(screenplay|writer|story|novel|teleplay)$/i.test(String(c.job || '')));
  plexWriters.forEach((name) => add({ name, role: 'Writer' }));
  return people;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  return (parts.length >= 2 ? parts[0][0] + parts[1][0] : name.slice(0, 2)).toUpperCase();
}

export default function DetailsCastRow({
  meta,
  tmdbCast,
  tmdbCrew,
  creators = [],
  guestStars = [],
  onPersonPress,
}: {
  meta: any;
  tmdbCast: DetailsCastMember[];
  tmdbCrew: DetailsCrewMember[];
  creators?: string[];
  guestStars?: DetailsCastMember[];
  onPersonPress: (id: number, name: string) => void;
}) {
  const [resolving, setResolving] = useState<string | null>(null);

  const showGuests = meta?.type === 'episode' && guestStars.length > 0;
  const plexRoles: any[] = Array.isArray(meta?.Role) ? meta.Role : [];

  const tmdbByName = new Map(tmdbCast.map((c) => [c.name.trim().toLowerCase(), c]));
  const toCard = (c: DetailsCastMember): CardPerson => ({
    id: c.id,
    name: c.name,
    role: c.character || undefined,
    image: c.profile_path ? getTmdbProfileUrl(c.profile_path) : undefined,
  });

  let cast: CardPerson[];
  if (showGuests) {
    cast = guestStars.slice(0, CAST_LIMIT).map(toCard);
  } else if (plexRoles.length) {
    // Plex cast in library order, with the TMDB id and character filled in by name
    cast = plexRoles.slice(0, CAST_LIMIT).map((r) => {
      const name = String(r.tag || r.title || '');
      const match = tmdbByName.get(name.trim().toLowerCase());
      return {
        id: match?.id,
        name,
        role: r.role || match?.character || undefined,
        image: r.thumb ? getPlexImageUrl(r.thumb, 240) : match?.profile_path ? getTmdbProfileUrl(match.profile_path) : undefined,
      };
    });
  } else {
    cast = tmdbCast.slice(0, CAST_LIMIT).map(toCard);
  }

  const names = (list: any[]) => (Array.isArray(list) ? list.map((d) => String(d.tag || d.title || '')).filter(Boolean) : []);
  const crew = showGuests
    ? []
    : keyCrew(tmdbCrew, names(meta?.Director), names(meta?.Writer), meta?.type === 'show' ? creators : []);
  const people = [...cast, ...crew];
  if (!people.length) return null;

  const open = async (person: CardPerson, key: string) => {
    if (person.id) {
      onPersonPress(person.id, person.name);
      return;
    }
    // No TMDB match: look the person up by name, as macOS does
    setResolving(key);
    const id = await findTmdbPersonIdByName(person.name);
    setResolving(null);
    if (id) onPersonPress(id, person.name);
  };

  return (
    <View>
      <DetailsSectionHeading title={showGuests ? 'Guest Stars' : 'Cast & Crew'} />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.row}>
        {people.map((person, index) => {
          // Index keys: a person can appear as both cast and crew
          const key = `${index}-${person.name}`;
          return (
            <Pressable
              key={key}
              onPress={() => open(person, key)}
              style={styles.card}
              accessibilityRole="button"
              accessibilityLabel={person.role ? `${person.name}, ${person.role}` : person.name}
            >
              <View style={styles.circle}>
                {person.image ? (
                  <FastImage source={{ uri: person.image }} style={StyleSheet.absoluteFill} resizeMode="cover" />
                ) : (
                  <Text style={styles.initials}>{initials(person.name)}</Text>
                )}
                {resolving === key ? (
                  <View style={styles.busy}>
                    <ActivityIndicator color="#fff" />
                  </View>
                ) : null}
              </View>
              <Text style={styles.name} numberOfLines={1}>{person.name}</Text>
              {person.role ? <Text style={styles.role} numberOfLines={1}>{person.role}</Text> : null}
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const CIRCLE = 88;

const styles = StyleSheet.create({
  row: { paddingHorizontal: DetailsSectionStyle.inset, gap: 14 },
  card: { width: 96, alignItems: 'center' },
  circle: {
    width: CIRCLE,
    height: CIRCLE,
    borderRadius: CIRCLE / 2,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  initials: { color: 'rgba(255,255,255,0.6)', fontSize: 28, fontWeight: '500' },
  busy: { ...StyleSheet.absoluteFill, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center' },
  name: { color: '#fff', fontSize: 14, fontWeight: '500', marginTop: 8 },
  role: { color: 'rgba(255,255,255,0.5)', fontSize: 12, marginTop: 2 },
});
