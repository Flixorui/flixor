import React from 'react';
import { createRoot } from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import './styles/index.css';
import App from './App';
import Home from './routes/Home';
import Library from './routes/Library';
import Details from './routes/Details';
import Person from './routes/Person';
import Player from './routes/Player';
import Settings from './routes/Settings';
import Login from './routes/Login';
import NewPopular from './routes/NewPopular';
import MyList from './routes/MyList';
import Search from './routes/Search';
import Onboarding from './routes/Onboarding';
import Collection from './routes/Collection';
import EntityBrowse from './routes/EntityBrowse';
import StremioSettings from './components/settings/StremioSettings';
import PlayerSettings from './components/settings/PlayerSettings';
import AppearanceSettings from './components/settings/AppearanceSettings';
import NavigationSettings from './components/settings/NavigationSettings';
import SearchSettings from './components/settings/SearchSettings';
import RowsSettings from './components/settings/RowsSettings';
import AdvancedSettings from './components/settings/AdvancedSettings';
import Profiles from './routes/Profiles';
import LogsSettings from './components/settings/LogsSettings';
import SettingsSubpage from './routes/SettingsSubpage';
import PlexSettings from './components/settings/PlexSettings';
import HomeScreenSettings from './components/settings/HomeScreenSettings';
import DetailsScreenSettings from './components/settings/DetailsScreenSettings';
import MDBListSettings from './components/settings/MDBListSettings';
import OverseerrSettings from './components/settings/OverseerrSettings';
import CatalogSettings from './components/settings/CatalogSettings';
import ContinueWatchingSettings from './components/settings/ContinueWatchingSettings';
import TMDBSettings from './components/settings/TMDBSettings';
import TraktSettings from './components/settings/TraktSettings';
import { initAccent } from './state/accent';
import { initLogger } from './services/logger';
import { initProfiles } from './services/profiles';

const router = createBrowserRouter([
  {
    path: '/',
    element: <App />,
    children: [
      { index: true, element: <Home /> },
      { path: 'library', element: <Library /> },
      { path: 'details/:id', element: <Details /> },
      { path: 'person/:id', element: <Person /> },
      { path: 'player/:id', element: <Player /> },
      { path: 'settings', element: <Settings /> },
      { path: 'settings/plex', element: <SettingsSubpage page={PlexSettings} /> },
      { path: 'settings/home', element: <SettingsSubpage page={HomeScreenSettings} /> },
      { path: 'settings/details', element: <SettingsSubpage page={DetailsScreenSettings} /> },
      { path: 'settings/mdblist', element: <SettingsSubpage page={MDBListSettings} /> },
      { path: 'settings/overseerr', element: <SettingsSubpage page={OverseerrSettings} /> },
      { path: 'settings/catalogs', element: <SettingsSubpage page={CatalogSettings} /> },
      { path: 'settings/continue-watching', element: <SettingsSubpage page={ContinueWatchingSettings} /> },
      { path: 'settings/tmdb', element: <SettingsSubpage page={TMDBSettings} /> },
      { path: 'settings/trakt', element: <SettingsSubpage page={TraktSettings} /> },
      { path: 'settings/stremio', element: <StremioSettings /> },
      { path: 'settings/player', element: <PlayerSettings /> },
      { path: 'settings/appearance', element: <AppearanceSettings /> },
      { path: 'settings/navigation', element: <NavigationSettings /> },
      { path: 'settings/search', element: <SearchSettings /> },
      { path: 'settings/rows', element: <RowsSettings /> },
      { path: 'settings/advanced', element: <AdvancedSettings /> },
      { path: 'settings/advanced/logs', element: <LogsSettings /> },
      { path: 'collections/:id', element: <Collection /> },
      { path: 'browse/:kind/:id', element: <EntityBrowse /> },
      { path: 'login', element: <Login /> },
      { path: 'new-popular', element: <NewPopular /> },
      { path: 'my-list', element: <MyList /> },
      { path: 'search', element: <Search /> },
      { path: 'onboarding', element: <Onboarding /> },
      { path: 'profiles', element: <Profiles /> },
    ],
  },
]);

// Log feature flag(s) at startup for verification
if (typeof window !== 'undefined') {
  // eslint-disable-next-line no-console
  console.info('[App] MODE:', (import.meta as any).env?.MODE);
}

initAccent();
initLogger();
initProfiles();

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
