/**
 * Trakt comments for the title on screen: a horizontal row, sort, paging, and a popup
 * with previous/next. Spoilers stay hidden until tapped. Works without a Trakt login.
 * macOS reference: Views/Details/DetailsCommentsSection.swift
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { TraktComment } from '@flixor/core';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import { useTheme } from '../../hooks/useTheme';
import type { FlixorTheme } from '../../core/theme';
import type { WatchStateTarget } from '../../core/WatchState';
import {
  COMMENTS_NOT_FOUND,
  commentAuthor,
  commentDisplayText,
  commentHasSpoiler,
  commentLikesLabel,
  commentRating,
  fetchTraktComments,
} from '../../core/TraktCommentsData';

type Phase = 'loading' | 'loaded' | 'failed';
type CommentSort = 'likes' | 'newest';

const PAGE_SIZE = 10;
const CARD_HEIGHT = 190;
const CARD_GAP = 12;

const SORT_OPTIONS: Array<{ value: CommentSort; label: string }> = [
  { value: 'likes', label: 'Most Liked' },
  { value: 'newest', label: 'Newest' },
];

export default function DetailsComments({ target }: { target: WatchStateTarget | null }) {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const cardWidth = Math.min(width * 0.8, 320);

  const [comments, setComments] = useState<TraktComment[]>([]);
  const [phase, setPhase] = useState<Phase>('loading');
  const [error, setError] = useState<string | null>(null);
  const [sort, setSort] = useState<CommentSort>('likes');
  const [total, setTotal] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [loadMoreFailed, setLoadMoreFailed] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [revealed, setRevealed] = useState<Set<number>>(new Set());

  // Late responses for an older title or sort are dropped
  const generation = useRef(0);
  const page = useRef(1);
  // Lets "next" see a page that arrived before React has re-rendered
  const loaded = useRef<TraktComment[]>([]);

  const loadFirstPage = useCallback(async () => {
    const current = ++generation.current;
    setPhase('loading');
    setError(null);
    loaded.current = [];
    setComments([]);
    setTotal(0);
    setHasMore(false);
    setLoadingMore(false);
    setLoadMoreFailed(false);
    setSelectedIndex(null);
    setRevealed(new Set());
    page.current = 1;
    if (!target) {
      setPhase('failed');
      setError(COMMENTS_NOT_FOUND);
      return;
    }
    try {
      const result = await fetchTraktComments(target, sort, 1, PAGE_SIZE);
      if (current !== generation.current) return;
      loaded.current = result.items;
      setComments(result.items);
      setTotal(result.itemCount);
      setHasMore(result.page < result.pageCount);
      setPhase('loaded');
    } catch (e) {
      if (current !== generation.current) return;
      setError(e instanceof Error && e.message === COMMENTS_NOT_FOUND ? e.message : "Couldn't load comments from Trakt.");
      setPhase('failed');
    }
  }, [target, sort]);

  useEffect(() => {
    loadFirstPage();
  }, [loadFirstPage]);

  /** Resolves to how many comments are loaded afterwards. */
  const loadMore = useCallback(async (): Promise<number> => {
    if (!target || !hasMore || loadingMore || phase !== 'loaded') return loaded.current.length;
    const current = generation.current;
    setLoadingMore(true);
    setLoadMoreFailed(false);
    try {
      const result = await fetchTraktComments(target, sort, page.current + 1, PAGE_SIZE);
      if (current !== generation.current) return loaded.current.length;
      page.current = result.page;
      const known = new Set(loaded.current.map((comment) => comment.id));
      loaded.current = [...loaded.current, ...result.items.filter((comment) => !known.has(comment.id))];
      setComments(loaded.current);
      setHasMore(result.page < result.pageCount);
      setTotal((count) => Math.max(count, result.itemCount));
    } catch {
      if (current === generation.current) setLoadMoreFailed(true);
    } finally {
      if (current === generation.current) setLoadingMore(false);
    }
    return loaded.current.length;
  }, [target, sort, hasMore, loadingMore, phase]);

  const selectNext = useCallback(async () => {
    if (selectedIndex == null) return;
    const from = selectedIndex;
    const count = from + 1 >= loaded.current.length ? await loadMore() : loaded.current.length;
    // Stays put if the next page failed, or the popup moved or closed during the load
    if (from + 1 < count) setSelectedIndex((index) => (index === from ? from + 1 : index));
  }, [selectedIndex, loadMore]);

  const selected = selectedIndex != null ? comments[selectedIndex] ?? null : null;

  const sortControl = (
    <View style={[styles.sortRow, { backgroundColor: theme.surfaceOverlay }]}>
      {SORT_OPTIONS.map((option) => {
        const active = option.value === sort;
        return (
          <Pressable
            key={option.value}
            disabled={phase === 'loading'}
            onPress={() => setSort(option.value)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            style={[styles.sortChip, active && { backgroundColor: 'rgba(255,255,255,0.16)' }]}
          >
            <Text style={[styles.sortText, { color: active ? theme.textPrimary : theme.textSecondary }]}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );

  return (
    <View>
      <DetailsSectionHeading title="Comments" detail={total > 0 ? String(total) : undefined} right={sortControl} />

      {phase === 'loading' ? (
        <FlatList
          horizontal
          scrollEnabled={false}
          data={[0, 1, 2]}
          keyExtractor={(item) => String(item)}
          renderItem={() => <PlaceholderCard width={cardWidth} theme={theme} />}
          contentContainerStyle={styles.rowContent}
          ItemSeparatorComponent={Separator}
        />
      ) : phase === 'failed' ? (
        <StateMessage
          theme={theme}
          icon="alert-circle-outline"
          message={error ?? "Couldn't load comments from Trakt."}
          actionLabel={error === COMMENTS_NOT_FOUND ? undefined : 'Try Again'}
          onAction={loadFirstPage}
        />
      ) : comments.length === 0 ? (
        <StateMessage theme={theme} icon="chatbubble-outline" message="No comments on Trakt yet." />
      ) : (
        <FlatList
          horizontal
          data={comments}
          keyExtractor={(comment) => String(comment.id)}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.rowContent}
          ItemSeparatorComponent={Separator}
          onEndReached={() => loadMore()}
          onEndReachedThreshold={0.6}
          renderItem={({ item, index }) => (
            <CommentCard comment={item} width={cardWidth} theme={theme} onPress={() => setSelectedIndex(index)} />
          )}
          ListFooterComponent={
            loadingMore ? (
              <View style={[styles.footer, { width: cardWidth }]}>
                <ActivityIndicator color={theme.textSecondary} />
              </View>
            ) : loadMoreFailed ? (
              <Pressable onPress={() => loadMore()} style={[styles.footer, { width: cardWidth }]} accessibilityRole="button">
                <Text style={[styles.retryError, { color: theme.danger }]}>Couldn't load more</Text>
                <Text style={[styles.retry, { color: theme.textPrimary }]}>Retry</Text>
              </Pressable>
            ) : null
          }
        />
      )}

      <CommentPopup
        comment={selected}
        index={selectedIndex}
        total={Math.max(total, comments.length)}
        canNext={selectedIndex != null && (selectedIndex + 1 < comments.length || hasMore)}
        loadingNext={loadingMore}
        revealed={selected ? revealed.has(selected.id) : false}
        theme={theme}
        onReveal={() => selected && setRevealed((existing) => new Set(existing).add(selected.id))}
        onPrevious={() => setSelectedIndex((index) => (index != null && index > 0 ? index - 1 : index))}
        onNext={selectNext}
        onClose={() => setSelectedIndex(null)}
      />
    </View>
  );
}

function Separator() {
  return <View style={{ width: CARD_GAP }} />;
}

function PlaceholderCard({ width, theme }: { width: number; theme: FlixorTheme }) {
  return (
    <View accessibilityElementsHidden style={[styles.card, { width, backgroundColor: theme.surfaceOverlay, borderColor: theme.separator }]}>
      <View style={[styles.placeholderLine, { width: 96, backgroundColor: theme.pressedFill }]} />
      <View style={[styles.placeholderLine, { marginTop: 14, backgroundColor: theme.pressedFill }]} />
      <View style={[styles.placeholderLine, { backgroundColor: theme.pressedFill }]} />
      <View style={[styles.placeholderLine, { width: '70%', backgroundColor: theme.pressedFill }]} />
    </View>
  );
}

function CommentMeta({ comment, theme }: { comment: TraktComment; theme: FlixorTheme }) {
  const rating = commentRating(comment);
  return (
    <Text numberOfLines={1} style={[styles.meta, { color: theme.textTertiary }]}>
      {rating != null ? `${rating}/10  ·  ` : ''}
      {commentLikesLabel(comment)}
    </Text>
  );
}

function ReviewChip({ theme }: { theme: FlixorTheme }) {
  return (
    <View style={[styles.chip, { backgroundColor: theme.pressedFill }]}>
      <Text style={[styles.chipText, { color: theme.textSecondary }]}>Review</Text>
    </View>
  );
}

function CommentCard({
  comment,
  width,
  theme,
  onPress,
}: {
  comment: TraktComment;
  width: number;
  theme: FlixorTheme;
  onPress: () => void;
}) {
  const author = commentAuthor(comment);
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`Open comment by ${author}`}
      style={({ pressed }) => [
        styles.card,
        {
          width,
          backgroundColor: pressed ? theme.pressedFill : theme.surfaceOverlay,
          borderColor: theme.separator,
        },
      ]}
    >
      <Text numberOfLines={1} style={[styles.author, { color: theme.textPrimary }]}>
        {author}
      </Text>
      {comment.review ? <ReviewChip theme={theme} /> : null}
      <Text
        numberOfLines={comment.review ? 4 : 5}
        style={[styles.body, { color: commentHasSpoiler(comment) ? theme.warning : theme.textSecondary }]}
      >
        {commentHasSpoiler(comment) ? 'This comment contains spoilers.' : commentDisplayText(comment)}
      </Text>
      <View style={styles.cardSpacer} />
      <CommentMeta comment={comment} theme={theme} />
    </Pressable>
  );
}

function StateMessage({
  theme,
  icon,
  message,
  actionLabel,
  onAction,
}: {
  theme: FlixorTheme;
  icon: keyof typeof Ionicons.glyphMap;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={[styles.state, { backgroundColor: theme.surfaceOverlay }]}>
      <Ionicons name={icon} size={20} color={theme.textTertiary} />
      <Text style={[styles.stateText, { color: theme.textSecondary }]}>{message}</Text>
      {actionLabel ? (
        <Pressable onPress={onAction} hitSlop={8} accessibilityRole="button">
          <Text style={[styles.stateAction, { color: theme.textPrimary }]}>{actionLabel}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function PagerButton({
  icon,
  label,
  enabled,
  onPress,
  theme,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  enabled: boolean;
  onPress: () => void;
  theme: FlixorTheme;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={!enabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={[styles.pager, { backgroundColor: theme.pressedFill, opacity: enabled ? 1 : 0.4 }]}
    >
      <Ionicons name={icon} size={18} color={enabled ? theme.textPrimary : theme.textTertiary} />
    </Pressable>
  );
}

function CommentPopup({
  comment,
  index,
  total,
  canNext,
  loadingNext,
  revealed,
  theme,
  onReveal,
  onPrevious,
  onNext,
  onClose,
}: {
  comment: TraktComment | null;
  index: number | null;
  total: number;
  canNext: boolean;
  loadingNext: boolean;
  revealed: boolean;
  theme: FlixorTheme;
  onReveal: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onClose: () => void;
}) {
  const insets = useSafeAreaInsets();
  if (index == null) return null;
  const spoilerHidden = comment != null && commentHasSpoiler(comment) && !revealed;
  const username = comment?.user?.username;
  return (
    <Modal visible transparent animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <Pressable style={styles.scrim} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close">
        <Pressable
          onPress={() => undefined}
          style={[styles.panel, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 20 }]}
        >
          <View style={[styles.handle, { backgroundColor: theme.separatorStrong }]} />
          <View style={styles.popupHeader}>
            <View style={styles.popupAuthor}>
              <Text numberOfLines={1} style={[styles.popupName, { color: theme.textPrimary }]}>
                {comment ? commentAuthor(comment) : ''}
              </Text>
              {username ? (
                <Text numberOfLines={1} style={[styles.popupUser, { color: theme.textSecondary }]}>
                  @{username}
                </Text>
              ) : null}
            </View>
            <PagerButton icon="chevron-back" label="Previous comment" enabled={index > 0} onPress={onPrevious} theme={theme} />
            <Text style={[styles.pagerCount, { color: theme.textSecondary }]}>
              {index + 1} / {total}
            </Text>
            <PagerButton icon="chevron-forward" label="Next comment" enabled={canNext && !loadingNext} onPress={onNext} theme={theme} />
          </View>

          {comment?.review ? <ReviewChip theme={theme} /> : null}

          <ScrollView style={styles.popupBody} key={comment?.id ?? 'loading'}>
            {!comment ? null : spoilerHidden ? (
              <Pressable onPress={onReveal} accessibilityRole="button" accessibilityLabel="Reveal spoiler comment">
                <Text style={[styles.popupText, { color: theme.warning }]}>
                  This comment contains spoilers. Tap to reveal.
                </Text>
              </Pressable>
            ) : (
              <Text selectable style={[styles.popupText, { color: theme.textPrimary }]}>
                {commentDisplayText(comment)}
              </Text>
            )}
          </ScrollView>

          {comment ? (
            <View style={styles.popupFooter}>
              <CommentMeta comment={comment} theme={theme} />
              {comment.created_at ? (
                <Text style={[styles.meta, { color: theme.textTertiary }]}>{comment.created_at.slice(0, 10)}</Text>
              ) : null}
            </View>
          ) : null}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  rowContent: {
    paddingHorizontal: DetailsSectionStyle.inset,
  },
  sortRow: {
    flexDirection: 'row',
    borderRadius: 8,
    padding: 2,
  },
  sortChip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 6,
  },
  sortText: {
    fontSize: 12,
    fontWeight: '600',
  },
  card: {
    height: CARD_HEIGHT,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    gap: 8,
    overflow: 'hidden',
  },
  cardSpacer: {
    flex: 1,
  },
  author: {
    fontSize: 15,
    fontWeight: '600',
  },
  chip: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  chipText: {
    fontSize: 11,
    fontWeight: '600',
  },
  body: {
    fontSize: 14,
    lineHeight: 20,
  },
  meta: {
    fontSize: 12,
    fontWeight: '500',
  },
  placeholderLine: {
    height: 12,
    borderRadius: 4,
    width: '100%',
  },
  state: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginHorizontal: DetailsSectionStyle.inset,
    padding: 14,
    borderRadius: 12,
  },
  stateText: {
    flex: 1,
    fontSize: 14,
  },
  stateAction: {
    fontSize: 14,
    fontWeight: '700',
  },
  footer: {
    height: CARD_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: CARD_GAP,
    gap: 6,
  },
  retryError: {
    fontSize: 13,
  },
  retry: {
    fontSize: 14,
    fontWeight: '700',
  },
  scrim: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  panel: {
    maxHeight: '75%',
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    paddingTop: 10,
    paddingHorizontal: 20,
    gap: 12,
  },
  handle: {
    alignSelf: 'center',
    width: 40,
    height: 4,
    borderRadius: 2,
  },
  popupHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  popupAuthor: {
    flex: 1,
  },
  popupName: {
    fontSize: 17,
    fontWeight: '700',
  },
  popupUser: {
    fontSize: 13,
    marginTop: 1,
  },
  pager: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pagerCount: {
    fontSize: 13,
    fontWeight: '500',
    fontVariant: ['tabular-nums'],
  },
  popupBody: {
    flexGrow: 0,
  },
  popupText: {
    fontSize: 16,
    lineHeight: 24,
  },
  popupFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
});
