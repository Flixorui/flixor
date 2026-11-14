/**
 * Logos for ratings and external links. Bitmaps for IMDb and Rotten Tomatoes;
 * transparent SVGs for the rest (the Letterboxd decal PNG had a white disc,
 * so this is the three-dot mark rebuilt from letterboxd.com/about/brand, as on
 * macOS). Metacritic is tinted by score: green from 61, yellow from 40, red below.
 */
import React from 'react';
import { Image } from 'react-native';
import { SvgXml } from 'react-native-svg';
import type { RatingKind } from '../core/ratings/merged';

const LETTERBOXD = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"378\" height=\"140\" viewBox=\"0 0 378 140\"> <circle fill=\"#00E054\" cx=\"189\" cy=\"69.9732824\" r=\"70.0786517\"/> <circle fill=\"#40BCF4\" cx=\"307.9213486\" cy=\"69.9732824\" r=\"70.0786517\"/> <circle fill=\"#FF8000\" cx=\"70.0786517\" cy=\"69.9732824\" r=\"70.0786517\"/> <path fill=\"#556677\" d=\"M129.539326,107.022244 C122.810493,96.2781677 118.921348,83.5792213 118.921348,69.9732824 C118.921348,56.3673435 122.810493,43.6683972 129.539326,32.9243209 C136.268159,43.6683972 140.157303,56.3673435 140.157303,69.9732824 C140.157303,83.5792213 136.268159,96.2781677 129.539326,107.022244 Z\"/> <path fill=\"#556677\" d=\"M248.460674,32.9243209 C255.189507,43.6683972 259.078652,56.3673435 259.078652,69.9732824 C259.078652,83.5792213 255.189507,96.2781677 248.460674,107.022244 C241.731841,96.2781677 237.842697,83.5792213 237.842697,69.9732824 C237.842697,56.3673435 241.731841,43.6683972 248.460674,32.9243209 Z\"/> </svg>";
const METACRITIC = "<svg role=\"img\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M11.99 0A12 12 0 1 0 24 12v-.014A12 12 0 0 0 11.99 0Zm-.055 2.564a9.399 9.399 0 0 1 9.407 9.389v.01a9.399 9.399 0 1 1-9.408-9.399Zm-1.61 17.198 2.046-2.046-3.94-3.94c-.165-.166-.345-.373-.442-.608-.221-.47-.318-1.203.221-1.742.664-.664 1.548-.387 2.406.47l3.788 3.788 2.046-2.046-3.954-3.954a2.48 2.48 0 0 1-.456-.622c-.263-.539-.25-1.216.235-1.7.677-.678 1.562-.429 2.544.553l3.677 3.677 2.046-2.046-3.982-3.982c-2.018-2.018-3.912-1.949-5.212-.65-.498.499-.802 1.024-.954 1.618a4.026 4.026 0 0 0-.055 1.686l-.027.028c-.996-.414-2.13-.166-3 .705-1.162 1.161-1.12 2.392-.982 3.11l-.042.043-1.009-.816-1.77 1.77a64.1 64.1 0 0 1 2.213 2.1z\"/></svg>";
const TMDB = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 185.04 133.4\"><defs><linearGradient id=\"linear-gradient\" y1=\"66.7\" x2=\"185.04\" y2=\"66.7\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0\" stop-color=\"#90cea1\"/><stop offset=\"0.56\" stop-color=\"#3cbec9\"/><stop offset=\"1\" stop-color=\"#00b3e5\"/></linearGradient></defs><g id=\"Layer_2\" data-name=\"Layer 2\"><g id=\"Layer_1-2\" data-name=\"Layer 1\"><path fill=\"url(#linear-gradient)\" d=\"M51.06,66.7h0A17.67,17.67,0,0,1,68.73,49h-.1A17.67,17.67,0,0,1,86.3,66.7h0A17.67,17.67,0,0,1,68.63,84.37h.1A17.67,17.67,0,0,1,51.06,66.7Zm82.67-31.33h32.9A17.67,17.67,0,0,0,184.3,17.7h0A17.67,17.67,0,0,0,166.63,0h-32.9A17.67,17.67,0,0,0,116.06,17.7h0A17.67,17.67,0,0,0,133.73,35.37Zm-113,98h63.9A17.67,17.67,0,0,0,102.3,115.7h0A17.67,17.67,0,0,0,84.63,98H20.73A17.67,17.67,0,0,0,3.06,115.7h0A17.67,17.67,0,0,0,20.73,133.37Zm83.92-49h6.25L125.5,49h-8.35l-8.9,23.2h-.1L99.4,49H90.5Zm32.45,0h7.8V49h-7.8Zm22.2,0h24.95V77.2H167.1V70h15.35V62.8H167.1V56.2h16.25V49h-24ZM10.1,35.4h7.8V6.9H28V0H0V6.9H10.1ZM39,35.4h7.8V20.1H61.9V35.4h7.8V0H61.9V13.2H46.75V0H39Zm41.25,0h25V28.2H88V21h15.35V13.8H88V7.2h16.25V0h-24Zm-79,49H9V57.25h.1l9,27.15H24l9.3-27.15h.1V84.4h7.8V49H29.45l-8.2,23.1h-.1L13,49H1.2Zm112.09,49H126a24.59,24.59,0,0,0,7.56-1.15,19.52,19.52,0,0,0,6.35-3.37,16.37,16.37,0,0,0,4.37-5.5A16.91,16.91,0,0,0,146,115.8a18.5,18.5,0,0,0-1.68-8.25,15.1,15.1,0,0,0-4.52-5.53A18.55,18.55,0,0,0,133.07,99,33.54,33.54,0,0,0,125,98H113.29Zm7.81-28.2h4.6a17.43,17.43,0,0,1,4.67.62,11.68,11.68,0,0,1,3.88,1.88,9,9,0,0,1,2.62,3.18,9.87,9.87,0,0,1,1,4.52,11.92,11.92,0,0,1-1,5.08,8.69,8.69,0,0,1-2.67,3.34,10.87,10.87,0,0,1-4,1.83,21.57,21.57,0,0,1-5,.55H121.1Zm36.14,28.2h14.5a23.11,23.11,0,0,0,4.73-.5,13.38,13.38,0,0,0,4.27-1.65,9.42,9.42,0,0,0,3.1-3,8.52,8.52,0,0,0,1.2-4.68,9.16,9.16,0,0,0-.55-3.2,7.79,7.79,0,0,0-1.57-2.62,8.38,8.38,0,0,0-2.45-1.85,10,10,0,0,0-3.18-1v-.1a9.28,9.28,0,0,0,4.43-2.82,7.42,7.42,0,0,0,1.67-5,8.34,8.34,0,0,0-1.15-4.65,7.88,7.88,0,0,0-3-2.73,12.9,12.9,0,0,0-4.17-1.3,34.42,34.42,0,0,0-4.63-.32h-13.2Zm7.8-28.8h5.3a10.79,10.79,0,0,1,1.85.17,5.77,5.77,0,0,1,1.7.58,3.33,3.33,0,0,1,1.23,1.13,3.22,3.22,0,0,1,.47,1.82,3.63,3.63,0,0,1-.42,1.8,3.34,3.34,0,0,1-1.13,1.2,4.78,4.78,0,0,1-1.57.65,8.16,8.16,0,0,1-1.78.2H165Zm0,14.15h5.9a15.12,15.12,0,0,1,2.05.15,7.83,7.83,0,0,1,2,.55,4,4,0,0,1,1.58,1.17,3.13,3.13,0,0,1,.62,2,3.71,3.71,0,0,1-.47,1.95,4,4,0,0,1-1.23,1.3,4.78,4.78,0,0,1-1.67.7,8.91,8.91,0,0,1-1.83.2h-7Z\"/></g></g></svg>";
const TRAKT = "<svg enable-background=\"new 0 0 144.8 144.8\" viewBox=\"0 0 144.8 144.8\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"m29.5 111.8c10.6 11.6 25.9 18.8 42.9 18.8 8.7 0 16.9-1.9 24.3-5.3l-40.4-40.3z\" fill=\"#ed2224\"/><path d=\"m56.1 60.6-30.6 30.5-4.1-4.1 32.2-32.2 37.6-37.6c-5.9-2-12.2-3.1-18.8-3.1-32.2 0-58.3 26.1-58.3 58.3 0 13.1 4.3 25.2 11.7 35l30.5-30.5 2.1 2 43.7 43.7c.9-.5 1.7-1 2.5-1.6l-48.3-48.3-29.3 29.3-4.1-4.1 33.4-33.4 2.1 2 51 50.9c.8-.6 1.5-1.3 2.2-1.9l-55-55z\" fill=\"#ed2224\"/><path d=\"m115.7 111.4c9.3-10.3 15-24 15-39 0-23.4-13.8-43.5-33.6-52.8l-36.7 36.6zm-41.2-44.6-4.1-4.1 28.9-28.9 4.1 4.1zm27.4-39.7-33.3 33.3-4.1-4.1 33.3-33.3z\" fill=\"#ed1c24\"/><path d=\"m72.4 144.8c-39.9 0-72.4-32.5-72.4-72.4s32.5-72.4 72.4-72.4 72.4 32.5 72.4 72.4-32.5 72.4-72.4 72.4zm0-137.5c-35.9 0-65.1 29.2-65.1 65.1s29.2 65.1 65.1 65.1 65.1-29.2 65.1-65.1-29.2-65.1-65.1-65.1z\" fill=\"#ed2224\"/></svg>";

export const RATING_BITMAPS = {
  imdb: require('../../assets/ratings/imdb.png'),
  tomatoFresh: require('../../assets/ratings/tomato-fresh.png'),
  tomatoRotten: require('../../assets/ratings/tomato-rotten.png'),
  popcornFull: require('../../assets/ratings/popcorn-full.png'),
  popcornFallen: require('../../assets/ratings/popcorn-fallen.png'),
};

export function metacriticColor(score: number): string {
  if (score >= 61) return '#66CC33';
  if (score >= 40) return '#FFCC33';
  return '#FF0000';
}

/** A rating's mark at the given height (IMDb is drawn twice as wide). */
export default function RatingLogo({ kind, value, size = 11 }: { kind: RatingKind; value?: number; size?: number }) {
  switch (kind) {
    case 'imdb':
      return <Image source={RATING_BITMAPS.imdb} style={{ width: size * 2, height: size }} resizeMode="contain" />;
    case 'rtCritics':
      return <Image source={(value ?? 0) >= 60 ? RATING_BITMAPS.tomatoFresh : RATING_BITMAPS.tomatoRotten} style={{ width: size, height: size }} resizeMode="contain" />;
    case 'rtAudience':
      return <Image source={(value ?? 0) >= 60 ? RATING_BITMAPS.popcornFull : RATING_BITMAPS.popcornFallen} style={{ width: size, height: size }} resizeMode="contain" />;
    case 'letterboxd':
      return <SvgXml xml={LETTERBOXD} width={size * 2.7} height={size} />;
    case 'metacritic':
      return <SvgXml xml={METACRITIC} width={size} height={size} color={metacriticColor(value ?? 0)} fill={metacriticColor(value ?? 0)} />;
    case 'tmdb':
      return <SvgXml xml={TMDB} width={size * 1.39} height={size} />;
    case 'trakt':
      return <SvgXml xml={TRAKT} width={size} height={size} />;
  }
}

export function LetterboxdMark({ size = 14 }: { size?: number }) {
  return <SvgXml xml={LETTERBOXD} width={size * 2.7} height={size} />;
}

export function TmdbMark({ size = 14 }: { size?: number }) {
  return <SvgXml xml={TMDB} width={size * 1.39} height={size} />;
}
