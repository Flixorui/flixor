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
      { path: 'login', element: <Login /> },
      { path: 'new-popular', element: <NewPopular /> },
      { path: 'my-list', element: <MyList /> },
      { path: 'search', element: <Search /> },
      { path: 'onboarding', element: <Onboarding /> },
    ],
  },
]);

// Log feature flag(s) at startup for verification
if (typeof window !== 'undefined') {
  // eslint-disable-next-line no-console
  console.info('[App] MODE:', (import.meta as any).env?.MODE);
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
