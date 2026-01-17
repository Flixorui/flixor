import React, { useEffect } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs';
import { View, ActivityIndicator, Text, Pressable, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import ConditionalBlurView from './src/components/ConditionalBlurView';
import { useTopBarStore } from './src/components/TopBarStore';
import { useAppSettings } from './src/hooks/useAppSettings';
import GlobalTopAppBar from './src/components/GlobalTopAppBar';
import { useSafeAreaInsets, SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { memoryManager } from './src/core/MemoryManager';

// Native iOS bottom tabs for liquid glass effect
let createNativeBottomTabNavigator: any = null;
if (Platform.OS === 'ios') {
  try {
    const bottomTabs = require('@bottom-tabs/react-navigation');
    createNativeBottomTabNavigator = bottomTabs.createNativeBottomTabNavigator;
  } catch {
    createNativeBottomTabNavigator = null;
  }
}

// Silence Reanimated warning about reading shared value during render
// This is caused by third-party libraries and is a known issue
import { configureReanimatedLogger, ReanimatedLogLevel } from 'react-native-reanimated';
configureReanimatedLogger({
  level: ReanimatedLogLevel.warn,
  strict: false, // Disable strict mode warnings
});

import Home from './src/screens/Home';
import Library from './src/screens/Library';
import Collections from './src/screens/Collections';
import Details from './src/screens/Details';
import Player from './src/screens/Player';
import Search from './src/screens/Search';
import Browse from './src/screens/Browse';
import NewHot from './src/screens/NewHot';
import MyList from './src/screens/MyList';
import Settings from './src/screens/Settings';
import CatalogSettings from './src/screens/settings/CatalogSettings';
import HomeScreenSettings from './src/screens/settings/HomeScreenSettings';
import DetailsScreenSettings from './src/screens/settings/DetailsScreenSettings';
import ContinueWatchingSettings from './src/screens/settings/ContinueWatchingSettings';
import BottomAppBarSettings from './src/screens/settings/BottomAppBarSettings';
import SearchSettings from './src/screens/settings/SearchSettings';
import TMDBSettings from './src/screens/settings/TMDBSettings';
import TraktSettings from './src/screens/settings/TraktSettings';
import MDBListSettings from './src/screens/settings/MDBListSettings';
import OverseerrSettings from './src/screens/settings/OverseerrSettings';
import PlexSettings from './src/screens/settings/PlexSettings';
import UpdateSettings from './src/screens/settings/UpdateSettings';
import * as Haptics from 'expo-haptics';
import UpdatePopup from './src/components/UpdatePopup';
import { useUpdateCheck } from './src/hooks/useUpdateCheck';

let GlassViewComp: any = null;
let liquidGlassAvailable = false;
if (Platform.OS === 'ios') {
  try {
    const glass = require('expo-glass-effect');
    GlassViewComp = glass.GlassView;
    liquidGlassAvailable = typeof glass.isLiquidGlassAvailable === 'function'
      ? glass.isLiquidGlassAvailable()
      : false;
  } catch {
    liquidGlassAvailable = false;
  }
}

// New standalone imports
import { FlixorProvider, useFlixor } from './src/core';
import PlexLogin from './src/screens/PlexLogin';
import ServerSelect from './src/screens/ServerSelect';
import OnboardingScreen from './src/screens/Onboarding';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { resetAppSettings } from './src/core/SettingsData';

const ONBOARDING_KEY = 'flixor:hasCompletedOnboarding';

// Note: expo-image uses disk cache by default (cachePolicy="disk" or "memory-disk")
// Cache limits are managed by the OS and expo-image internally

type RootStackParamList = {
  Onboarding: undefined;
  PlexLogin: undefined;
  ServerSelect: undefined;
  Main: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator();
const HomeStack = createNativeStackNavigator();
const SearchStack = createNativeStackNavigator();
const NewHotStack = createNativeStackNavigator();
const MyListStack = createNativeStackNavigator();
const SettingsStack = createNativeStackNavigator();

// Store logout handler in a ref accessible to child components
let logoutHandlerRef: (() => Promise<void>) | null = null;

// Define screen components OUTSIDE of AppContent to prevent recreation on every render
// This is critical for performance - inline components cause React Navigation to do extra work

const HomeStackNavigator = React.memo(() => {
  const topBarVisible = useTopBarStore((s) => s.visible === true);

  return (
    <View style={{ flex: 1 }}>
      <HomeStack.Navigator screenOptions={{ headerShown: false }}>
        <HomeStack.Screen name="HomeScreen">
          {() => <Home onLogout={() => logoutHandlerRef?.()} />}
        </HomeStack.Screen>
        <HomeStack.Screen
          name="Details"
          component={Details}
          options={{ presentation: 'transparentModal', animation: 'fade', gestureEnabled: false }}
        />
        <HomeStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
        <HomeStack.Screen
          name="Library"
          component={Library}
          options={{ presentation: 'card', animation: 'fade' }}
        />
        <HomeStack.Screen
          name="Collections"
          component={Collections}
          options={{ presentation: 'card', animation: 'fade' }}
        />
        <HomeStack.Screen
          name="Search"
          component={Search}
          options={{ presentation: 'modal', animation: 'slide_from_bottom' }}
        />
        <HomeStack.Screen
          name="Browse"
          component={Browse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
      </HomeStack.Navigator>
      {topBarVisible && <GlobalTopAppBar screenContext="HomeStack" />}
    </View>
  );
});

const NewHotStackNavigator = React.memo(() => {
  const topBarVisible = useTopBarStore((s) => s.visible === true);

  return (
    <View style={{ flex: 1 }}>
      <NewHotStack.Navigator screenOptions={{ headerShown: false }}>
        <NewHotStack.Screen name="NewHotScreen" component={NewHot} />
        <NewHotStack.Screen
          name="Details"
          component={Details}
          options={{ presentation: 'transparentModal', animation: 'fade', gestureEnabled: false }}
        />
        <NewHotStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
      </NewHotStack.Navigator>
      {topBarVisible && <GlobalTopAppBar screenContext="NewHot" />}
    </View>
  );
});

const MyListStackNavigator = React.memo(() => {
  const topBarVisible = useTopBarStore((s) => s.visible === true);

  return (
    <View style={{ flex: 1 }}>
      <MyListStack.Navigator screenOptions={{ headerShown: false }}>
        <MyListStack.Screen name="MyListScreen" component={MyList} />
        <MyListStack.Screen
          name="Details"
          component={Details}
          options={{ presentation: 'transparentModal', animation: 'fade', gestureEnabled: false }}
        />
        <MyListStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
      </MyListStack.Navigator>
      {topBarVisible && <GlobalTopAppBar screenContext="MyList" />}
    </View>
  );
});

const SearchStackNavigator = React.memo(() => (
  <View style={{ flex: 1 }}>
    <SearchStack.Navigator screenOptions={{ headerShown: false }}>
      <SearchStack.Screen name="SearchScreen">
        {() => <Search isTab />}
      </SearchStack.Screen>
      <SearchStack.Screen
        name="Details"
        component={Details}
        options={{ presentation: 'transparentModal', animation: 'fade', gestureEnabled: false }}
      />
      <SearchStack.Screen
        name="Player"
        component={Player}
        options={{ presentation: 'fullScreenModal', animation: 'fade' }}
      />
    </SearchStack.Navigator>
  </View>
));

const SettingsTabScreen = React.memo(() => (
  <SettingsStack.Navigator screenOptions={{ headerShown: false }}>
    <SettingsStack.Screen name="SettingsMain">
      {() => <Settings onLogout={() => logoutHandlerRef?.()} />}
    </SettingsStack.Screen>
    <SettingsStack.Screen name="CatalogSettings" component={CatalogSettings} />
    <SettingsStack.Screen name="HomeScreenSettings" component={HomeScreenSettings} />
    <SettingsStack.Screen name="DetailsScreenSettings" component={DetailsScreenSettings} />
    <SettingsStack.Screen name="ContinueWatchingSettings" component={ContinueWatchingSettings} />
    <SettingsStack.Screen name="BottomAppBarSettings" component={BottomAppBarSettings} />
    <SettingsStack.Screen name="SearchSettings" component={SearchSettings} />
    <SettingsStack.Screen name="TMDBSettings" component={TMDBSettings} />
    <SettingsStack.Screen name="TraktSettings" component={TraktSettings} />
    <SettingsStack.Screen name="MDBListSettings" component={MDBListSettings} />
    <SettingsStack.Screen name="OverseerrSettings" component={OverseerrSettings} />
    <SettingsStack.Screen name="PlexSettings">
      {() => <PlexSettings onLogout={() => logoutHandlerRef?.()} />}
    </SettingsStack.Screen>
    <SettingsStack.Screen name="UpdateSettings" component={UpdateSettings} />
  </SettingsStack.Navigator>
));

// Tabs component extracted and memoized to prevent unnecessary re-renders
const Tabs = React.memo(() => {
  const tabBarVisible = useTopBarStore(s => s.tabBarVisible === true);
  const insets = useSafeAreaInsets();
  const { settings } = useAppSettings();

  // Use native iOS tabs when available (iOS 18+ with @bottom-tabs)
  if (Platform.OS === 'ios' && createNativeBottomTabNavigator) {
    const IOSTab = createNativeBottomTabNavigator();

    return (
      <View style={{ flex: 1, backgroundColor: '#1b0a10' }}>
        <IOSTab.Navigator
          initialRouteName="HomeTab"
          screenOptions={{
            headerShown: false,
            tabBarActiveTintColor: '#007AFF',
            tabBarInactiveTintColor: '#8E8E93',
            translucent: true,
            lazy: false,
            freezeOnBlur: false,
          }}
        >
          <IOSTab.Screen
            name="HomeTab"
            component={HomeStackNavigator}
            options={{
              title: 'Home',
              tabBarIcon: () => ({ sfSymbol: 'house' }),
            }}
          />
          <IOSTab.Screen
            name="SearchTab"
            component={SearchStackNavigator}
            options={{
              title: 'Search',
              tabBarIcon: () => ({ sfSymbol: 'magnifyingglass' }),
            }}
          />
          {settings.showNewHotTab && (
            <IOSTab.Screen
              name="NewHotTab"
              component={NewHotStackNavigator}
              options={{
                title: 'New & Hot',
                tabBarIcon: () => ({ sfSymbol: 'play.circle' }),
              }}
            />
          )}
          <IOSTab.Screen
            name="MyTab"
            component={MyListStackNavigator}
            options={{
              title: 'My List',
              tabBarIcon: () => ({ sfSymbol: 'bookmark' }),
            }}
          />
          <IOSTab.Screen
            name="SettingsTab"
            component={SettingsTabScreen}
            options={{
              title: 'Settings',
              tabBarIcon: () => ({ sfSymbol: 'gear' }),
            }}
          />
        </IOSTab.Navigator>
      </View>
    );
  }

  // Fallback for Android and older iOS
  return (
    <Tab.Navigator
      sceneContainerStyle={{ backgroundColor: '#1b0a10' }}
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarShowLabel: true,
        tabBarActiveTintColor: '#fff',
        tabBarInactiveTintColor: '#bdbdbd',
        lazy: false,
        freezeOnBlur: false,
        animation: 'fade',
        tabBarStyle: tabBarVisible ? {
          position: 'absolute' as const,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: Platform.OS === 'ios' ? 'transparent' : 'rgba(0,0,0,0.9)',
          borderTopWidth: 0,
          height: 68 + insets.bottom,
          paddingBottom: insets.bottom + 10,
          paddingTop: 10,
        } : { display: 'none' as const },
        tabBarBackground: () => (
          <ConditionalBlurView intensity={90} tint="dark" style={{ flex: 1 }} fallbackColor="rgba(0,0,0,0.9)" />
        ),
        tabBarIcon: ({ color, focused }) => {
          const name = route.name === 'HomeTab' ? (focused ? 'home' : 'home-outline')
            : route.name === 'SearchTab' ? (focused ? 'search' : 'search-outline')
            : route.name === 'NewHotTab' ? (focused ? 'play-circle' : 'play-circle-outline')
            : route.name === 'SettingsTab' ? (focused ? 'settings' : 'settings-outline')
            : route.name === 'MyTab' ? (focused ? 'bookmark' : 'bookmark-outline')
            : (focused ? 'home' : 'home-outline');
          return <Ionicons name={name as any} size={22} color={color} />;
        }
      })}
      screenListeners={{
        tabPress: () => {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        }
      }}
    >
      <Tab.Screen name="HomeTab" options={{ title: 'Home' }} component={HomeStackNavigator} />
      <Tab.Screen name="SearchTab" options={{ title: 'Search' }} component={SearchStackNavigator} />
      {settings.showNewHotTab && (
        <Tab.Screen name="NewHotTab" options={{ title: 'New & Hot' }} component={NewHotStackNavigator} />
      )}
      <Tab.Screen name="MyTab" options={{ title: 'My List' }} component={MyListStackNavigator} />
      <Tab.Screen name="SettingsTab" options={{ title: 'Settings' }} component={SettingsTabScreen} />
    </Tab.Navigator>
  );
});

function AppContent() {
  const { flixor, isLoading, error, isAuthenticated, isConnected, refresh } = useFlixor();
  const {
    isUpdateAvailable,
    isDownloading,
    updateInfo,
    applyUpdate,
    snoozeUpdate,
    dismissUpdate,
  } = useUpdateCheck();

  // Onboarding state
  const [hasCompletedOnboarding, setHasCompletedOnboarding] = React.useState<boolean | null>(null);

  // Check onboarding status on mount
  React.useEffect(() => {
    (async () => {
      try {
        const onboardingValue = await AsyncStorage.getItem(ONBOARDING_KEY);
        setHasCompletedOnboarding(onboardingValue === 'true');
      } catch {
        setHasCompletedOnboarding(true); // Skip onboarding on error
      }
    })();
  }, []);

  const handleOnboardingComplete = React.useCallback(async () => {
    await AsyncStorage.setItem(ONBOARDING_KEY, 'true');
    setHasCompletedOnboarding(true);
  }, []);

  // Update the logout handler ref so memoized components can access it
  logoutHandlerRef = React.useCallback(async () => {
    if (flixor) {
      await flixor.logout();
      // Clear onboarding flag so it shows again on next login
      await AsyncStorage.removeItem(ONBOARDING_KEY);
      // Reset all app settings to defaults
      await resetAppSettings();
      setHasCompletedOnboarding(false);
      refresh();
    }
  }, [flixor, refresh]);

  // Show loading screen during initialization or onboarding check
  if (isLoading || hasCompletedOnboarding === null) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" size="large" />
        <Text style={{ color: '#666', marginTop: 16 }}>Loading...</Text>
      </View>
    );
  }

  // Show error if initialization failed
  if (error) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        <Text style={{ color: '#e50914', fontSize: 18, fontWeight: '600', marginBottom: 8 }}>
          Initialization Error
        </Text>
        <Text style={{ color: '#999', textAlign: 'center' }}>{error.message}</Text>
      </View>
    );
  }

  return (
    <>
      <NavigationContainer>
        <Stack.Navigator screenOptions={{ headerShown: false }}>
          {!isAuthenticated ? (
            // Not logged in - show Plex login
            <Stack.Screen name="PlexLogin">
              {() => <PlexLogin onAuthenticated={refresh} />}
            </Stack.Screen>
          ) : !isConnected ? (
            // Logged in but no server selected - show server selection
            <Stack.Screen name="ServerSelect">
              {() => <ServerSelect onConnected={refresh} />}
            </Stack.Screen>
          ) : !hasCompletedOnboarding ? (
            // Fully connected but first time - show onboarding (includes config as final slide)
            <Stack.Screen name="Onboarding">
              {() => <OnboardingScreen onComplete={handleOnboardingComplete} />}
            </Stack.Screen>
          ) : (
            // Fully authenticated, connected, and onboarded - show main app
            <Stack.Screen name="Main" component={Tabs} />
          )}
        </Stack.Navigator>
      </NavigationContainer>
      <UpdatePopup
        visible={isUpdateAvailable}
        updateInfo={updateInfo}
        isDownloading={isDownloading}
        onUpdateNow={applyUpdate}
        onUpdateLater={snoozeUpdate}
        onDismiss={dismissUpdate}
      />
    </>
  );
}

export default function App() {
  // Initialize memory manager on app start (clears image cache when app goes to background)
  useEffect(() => {
    memoryManager.initialize();
    return () => memoryManager.cleanup();
  }, []);

  return (
    <SafeAreaProvider initialMetrics={initialWindowMetrics}>
      <FlixorProvider>
        <AppContent />
      </FlixorProvider>
    </SafeAreaProvider>
  );
}
