/** Which TMDB image a Details card uses. Run: npm test (in web_frontend). */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { pickTitledArtwork } from './useTitledArtwork';

const images = {
  backdrops: [
    { file_path: '/textless.jpg', iso_639_1: null, vote_average: 9 },
    { file_path: '/fr-title.jpg', iso_639_1: 'fr', vote_average: 8 },
    { file_path: '/en-low.jpg', iso_639_1: 'en', vote_average: 4 },
    { file_path: '/en-high.jpg', iso_639_1: 'en', vote_average: 6 },
  ],
  posters: [
    { file_path: '/poster-textless.jpg', iso_639_1: null, vote_average: 9 },
    { file_path: '/poster-en.jpg', iso_639_1: 'en', vote_average: 5 },
  ],
};

test('landscape uses the best-rated English backdrop, with the title in it', () => {
  assert.equal(pickTitledArtwork(images, 'landscape'), '/en-high.jpg');
});

test('portrait uses the English poster over a better-rated textless one', () => {
  assert.equal(pickTitledArtwork(images, 'portrait'), '/poster-en.jpg');
});

test('falls back to other titled art, then textless art, then nothing', () => {
  assert.equal(pickTitledArtwork({ backdrops: images.backdrops.slice(0, 2) }, 'landscape'), '/fr-title.jpg');
  assert.equal(pickTitledArtwork({ backdrops: images.backdrops.slice(0, 1) }, 'landscape'), '/textless.jpg');
  assert.equal(pickTitledArtwork({}, 'portrait'), undefined);
});
