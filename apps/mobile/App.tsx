import "react-native-gesture-handler";
import { enableScreens } from 'react-native-screens';

// Enable native screens for better Android performance
enableScreens(true);

import React, { useEffect } from 'react';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs';
import { View, ActivityIndicator, Text, Pressable, Platform } from 'react-native';
import ConditionalBlurView from './src/components/ConditionalBlurView';
import { useTopBarStore } from './src/components/TopBarStore';
import { useAppSetting, useAppSettings } from './src/hooks/useAppSettings';
import { useTheme } from './src/hooks/useTheme';
import TabGlowIcon from './src/components/TabGlowIcon';
import { NAV_ICONS, navIconForRoute, type NavIconPair } from './src/components/navIcons';
import { NativeTab, usesNativeTabBar } from './src/core/TabBarSupport';
import GlobalTopAppBar from './src/components/GlobalTopAppBar';
import { useSafeAreaInsets, SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { memoryManager } from './src/core/MemoryManager';
import { appLogger } from './src/core/AppLogger';
import { loadAppSettings } from './src/core/SettingsData';

// Silence Reanimated warning about reading shared value during render
// This is caused by third-party libraries and is a known issue
import { configureReanimatedLogger, ReanimatedLogLevel } from 'react-native-reanimated';
configureReanimatedLogger({
  level: ReanimatedLogLevel.warn,
  strict: false, // Disable strict mode warnings
});

import Home from './src/screens/Home';
import Library from './src/screens/Library';
import LibraryHome from './src/screens/LibraryHome';
import Collections from './src/screens/Collections';
import Details from './src/screens/Details';
import Player from './src/screens/Player';
import Search from './src/screens/Search';
import Browse from './src/screens/Browse';
import NewHot from './src/screens/NewHot';
import MyList from './src/screens/MyList';
import Downloads from './src/screens/Downloads';
import StremioSources from './src/screens/StremioSources';
import Settings from './src/screens/Settings';
import ContentSettings from './src/screens/settings/ContentSettings';
import AdvancedSettings from './src/screens/settings/AdvancedSettings';
import AboutSettings from './src/screens/settings/AboutSettings';
import HomeScreenSettings from './src/screens/settings/HomeScreenSettings';
import DetailsScreenSettings from './src/screens/settings/DetailsScreenSettings';
import ContinueWatchingSettings from './src/screens/settings/ContinueWatchingSettings';
import BottomAppBarSettings from './src/screens/settings/BottomAppBarSettings';
import TMDBSettings from './src/screens/settings/TMDBSettings';
import TraktSettings from './src/screens/settings/TraktSettings';
import MDBListSettings from './src/screens/settings/MDBListSettings';
import { Top10ListsSettings, Top10FlixPatrolSettings, Top10KeysSettings, Top10ServicesSettings, Top10RegionSettings, Top10UsageSettings } from './src/screens/settings/Top10Settings';
import OverseerrSettings from './src/screens/settings/OverseerrSettings';
import PlexSettings from './src/screens/settings/PlexSettings';
import UpdateSettings from './src/screens/settings/UpdateSettings';
import PlayerSettings from './src/screens/settings/PlayerSettings';
import TrailerSettings from './src/screens/settings/TrailerSettings';
import LogsScreen from './src/screens/settings/LogsScreen';
import CollectionRowsSettings from './src/screens/settings/CollectionRowsSettings';
import LibraryMappingSettings from './src/screens/settings/LibraryMappingSettings';
import StremioSettings from './src/screens/settings/StremioSettings';
import StremioAddons from './src/screens/settings/StremioAddons';
import HomeRowsSettings from './src/screens/settings/HomeRowsSettings';
import AppearanceSettings from './src/screens/settings/AppearanceSettings';
import EntityBrowse from './src/screens/EntityBrowse';
import Person from './src/screens/Person';
import UserCollection from './src/screens/UserCollection';
import ToastHost from './src/components/Toast';
import { loadAppMode, useAppMode } from './src/core/AppMode';
import * as Haptics from 'expo-haptics';
import UpdatePopup from './src/components/UpdatePopup';
import { useUpdateCheck } from './src/hooks/useUpdateCheck';

// New standalone imports
import { FlixorProvider, useFlixor } from './src/core';
import PlexLogin from './src/screens/PlexLogin';
import ServerSelect from './src/screens/ServerSelect';
import OnboardingScreen from './src/screens/Onboarding';
import ProfileSelect from './src/screens/ProfileSelect';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { resetAppSettings } from './src/core/SettingsData';

const ONBOARDING_KEY = 'flixor:hasCompletedOnboarding';

// Note: expo-image uses disk cache by default (cachePolicy="disk" or "memory-disk")
// Cache limits are managed by the OS and expo-image internally

type RootStackParamList = {
  Onboarding: undefined;
  PlexLogin: undefined;
  ServerSelect: undefined;
  ProfileSelect: undefined;
  Main: undefined;
  Downloads: undefined;
  Player: undefined;
  StremioSources: undefined;
};

// The app is always dark (UIUserInterfaceStyle). Navigators read light or dark from this
// theme, not from the system: without it the iOS 26 native tab bar is forced light.
const navigationTheme = DarkTheme;

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator();
const HomeStack = createNativeStackNavigator();
const SearchStack = createNativeStackNavigator();
const NewHotStack = createNativeStackNavigator();
const MyListStack = createNativeStackNavigator();
const DownloadsStack = createNativeStackNavigator();
const SettingsStack = createNativeStackNavigator();

// Store logout handler in a ref accessible to child components
let logoutHandlerRef: (() => Promise<void>) | null = null;
const triggerLogout = () => logoutHandlerRef ? logoutHandlerRef() : Promise.resolve();

// Define screen components OUTSIDE of AppContent to prevent recreation on every render
// This is critical for performance - inline components cause React Navigation to do extra work

const HomeStackNavigator = React.memo(() => {
  return (
    <View style={{ flex: 1 }}>
      <HomeStack.Navigator screenOptions={{ headerShown: false }}>
        <HomeStack.Screen name="HomeScreen">
          {() => <Home onLogout={triggerLogout} />}
        </HomeStack.Screen>
        <HomeStack.Screen
          name="Details"
          component={Details}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
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
          name="LibraryHome"
          component={LibraryHome}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
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
        <HomeStack.Screen
          name="StremioSources"
          component={StremioSources}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <HomeStack.Screen
          name="EntityBrowse"
          component={EntityBrowse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <HomeStack.Screen
          name="Person"
          component={Person}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <HomeStack.Screen
          name="UserCollection"
          component={UserCollection}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
      </HomeStack.Navigator>
      {/* Home and Library render their own header so it moves with the screen */}
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
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <NewHotStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
        <NewHotStack.Screen
          name="StremioSources"
          component={StremioSources}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <NewHotStack.Screen
          name="EntityBrowse"
          component={EntityBrowse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <NewHotStack.Screen
          name="Person"
          component={Person}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <NewHotStack.Screen
          name="UserCollection"
          component={UserCollection}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <NewHotStack.Screen
          name="Browse"
          component={Browse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
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
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <MyListStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
        <MyListStack.Screen
          name="StremioSources"
          component={StremioSources}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <MyListStack.Screen
          name="EntityBrowse"
          component={EntityBrowse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <MyListStack.Screen
          name="Person"
          component={Person}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <MyListStack.Screen
          name="UserCollection"
          component={UserCollection}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <MyListStack.Screen
          name="Browse"
          component={Browse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
      </MyListStack.Navigator>
      {topBarVisible && <GlobalTopAppBar screenContext="MyList" />}
    </View>
  );
});

const DownloadsStackNavigator = React.memo(() => {
  return (
    <View style={{ flex: 1 }}>
      <DownloadsStack.Navigator screenOptions={{ headerShown: false }}>
        <DownloadsStack.Screen name="DownloadsScreen" component={Downloads} />
        <DownloadsStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
        <DownloadsStack.Screen
          name="StremioSources"
          component={StremioSources}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
      </DownloadsStack.Navigator>
    </View>
  );
});

const SearchStackNavigator = React.memo(() => {
  const [nativeSearchText, setNativeSearchText] = React.useState('');
  // iOS 26+ with liquid glass: Use native search (header required for tab bar transformation)
  // iOS 18 and below / Android: Use custom search bar
  const useNativeTabs = usesNativeTabBar;
  const theme = useTheme();

  return (
    <View style={{ flex: 1 }}>
      <SearchStack.Navigator
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: theme.background },
        }}
      >
        <SearchStack.Screen
          name="SearchScreen"
          options={useNativeTabs ? {
            headerShown: true,
            headerTransparent: true,
            headerLargeTitle: false,
            headerStyle: { backgroundColor: 'transparent' },
            headerTitle: '',
            headerSearchBarOptions: {
              placeholder: 'Search for movies, shows...',
              hideWhenScrolling: false,
              onChangeText: (e: any) => setNativeSearchText(e.nativeEvent.text),
              onCancelButtonPress: () => setNativeSearchText(''),
              autoCapitalize: 'none',
            },
          } : undefined}
        >
          {() => (
            <Search
              isTab
              nativeSearchText={useNativeTabs ? nativeSearchText : undefined}
              hideCustomSearchBar={useNativeTabs}
            />
          )}
        </SearchStack.Screen>
        <SearchStack.Screen
          name="Details"
          component={Details}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <SearchStack.Screen
          name="Player"
          component={Player}
          options={{ presentation: 'fullScreenModal', animation: 'fade' }}
        />
        <SearchStack.Screen
          name="StremioSources"
          component={StremioSources}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <SearchStack.Screen
          name="EntityBrowse"
          component={EntityBrowse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <SearchStack.Screen
          name="Person"
          component={Person}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <SearchStack.Screen
          name="UserCollection"
          component={UserCollection}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
        <SearchStack.Screen
          name="Browse"
          component={Browse}
          options={{ presentation: 'card', animation: 'slide_from_right' }}
        />
      </SearchStack.Navigator>
    </View>
  );
});

const SettingsTabScreen = React.memo(() => (
  <SettingsStack.Navigator screenOptions={{ headerShown: false }}>
    <SettingsStack.Screen name="SettingsMain">
      {() => <Settings onLogout={triggerLogout} />}
    </SettingsStack.Screen>
    <SettingsStack.Screen name="ContentSettings" component={ContentSettings} />
    <SettingsStack.Screen name="AdvancedSettings" component={AdvancedSettings} />
    <SettingsStack.Screen name="AboutSettings" component={AboutSettings} />
    <SettingsStack.Screen name="HomeScreenSettings" component={HomeScreenSettings} />
    <SettingsStack.Screen name="DetailsScreenSettings" component={DetailsScreenSettings} />
    <SettingsStack.Screen name="ContinueWatchingSettings" component={ContinueWatchingSettings} />
    <SettingsStack.Screen name="BottomAppBarSettings" component={BottomAppBarSettings} />
    <SettingsStack.Screen name="TMDBSettings" component={TMDBSettings} />
    <SettingsStack.Screen name="TraktSettings" component={TraktSettings} />
    <SettingsStack.Screen name="MDBListSettings" component={MDBListSettings} />
    <SettingsStack.Screen name="Top10ListsSettings" component={Top10ListsSettings} />
    <SettingsStack.Screen name="Top10FlixPatrolSettings" component={Top10FlixPatrolSettings} />
    <SettingsStack.Screen name="Top10KeysSettings" component={Top10KeysSettings} />
    <SettingsStack.Screen name="Top10ServicesSettings" component={Top10ServicesSettings} />
    <SettingsStack.Screen name="Top10RegionSettings" component={Top10RegionSettings} />
    <SettingsStack.Screen name="Top10UsageSettings" component={Top10UsageSettings} />
    <SettingsStack.Screen name="OverseerrSettings" component={OverseerrSettings} />
    <SettingsStack.Screen name="PlexSettings">
      {() => <PlexSettings onLogout={triggerLogout} />}
    </SettingsStack.Screen>
    <SettingsStack.Screen name="UpdateSettings" component={UpdateSettings} />
    <SettingsStack.Screen name="PlayerSettings" component={PlayerSettings} />
    <SettingsStack.Screen name="TrailerSettings" component={TrailerSettings} />
    <SettingsStack.Screen name="LogsScreen" component={LogsScreen} />
    <SettingsStack.Screen name="CollectionRowsSettings" component={CollectionRowsSettings} />
    <SettingsStack.Screen name="LibraryMappingSettings" component={LibraryMappingSettings} />
    <SettingsStack.Screen name="StremioSettings" component={StremioSettings} />
    <SettingsStack.Screen name="StremioAddons" component={StremioAddons} />
    <SettingsStack.Screen name="HomeRowsSettings" component={HomeRowsSettings} />
    <SettingsStack.Screen name="AppearanceSettings" component={AppearanceSettings} />
    <SettingsStack.Screen
      name="Details"
      component={Details}
      options={{ presentation: 'card', animation: 'slide_from_right' }}
    />
    <SettingsStack.Screen
      name="Browse"
      component={Browse}
      options={{ presentation: 'card', animation: 'slide_from_right' }}
    />
    <SettingsStack.Screen name="EntityBrowse" component={EntityBrowse} />
    <SettingsStack.Screen name="Person" component={Person} options={{ presentation: 'card', animation: 'slide_from_right' }} />
    <SettingsStack.Screen name="UserCollection" component={UserCollection} />
  </SettingsStack.Navigator>
));

// Tabs component extracted and memoized to prevent unnecessary re-renders
const Tabs = React.memo(() => {
  const tabBarVisible = useTopBarStore(s => s.tabBarVisible === true);
  const insets = useSafeAreaInsets();
  const { settings } = useAppSettings();
  const theme = useTheme();
  const labelMode = useAppSetting('tabLabelMode');
  const glowEnabled = useAppSetting('navGlowEnabled');

  // Use native iOS tabs only on iOS 26+ with liquid glass
  // iOS 18 and below falls back to regular tabs with blur view (same as Android)
  if (NativeTab) {
    // The macOS nav icons: outline, and filled on the selected tab
    const nativeOptions = (title: string, icons: NavIconPair, extra?: object) =>
      ({ navigation }: { navigation: any }) => ({
        title,
        // An empty label leaves only the icon. The options re-run when the tab changes.
        tabBarLabel: labelMode === 'always' || (labelMode === 'selected' && navigation.isFocused()) ? title : '',
        tabBarIcon: ({ focused }: { focused: boolean }) => ({ type: 'image', source: focused ? icons.fill : icons.outline, tinted: true }),
        ...extra,
      });

    return (
      <View style={{ flex: 1, backgroundColor: theme.shellBackground }}>
        <NativeTab.Navigator
          initialRouteName="HomeTab"
          screenOptions={{
            headerShown: false,
            // Tabs show selection in neutral white; red is reserved for switches and progress.
            tabBarActiveTintColor: '#fff',
            tabBarInactiveTintColor: '#8E8E93',
            translucent: true,
            lazy: false,
            freezeOnBlur: false,
          }}
        >
          <NativeTab.Screen
            name="HomeTab"
            component={HomeStackNavigator}
            options={nativeOptions('Home', NAV_ICONS.home)}
          />
          <NativeTab.Screen
            name="SearchTab"
            component={SearchStackNavigator}
            options={nativeOptions('Search', NAV_ICONS.search, { tabBarSystemItem: 'search' })}
          />
          {settings.showNewHotTab && (
            <NativeTab.Screen
              name="NewHotTab"
              component={NewHotStackNavigator}
              options={nativeOptions('New & Hot', NAV_ICONS.newHot)}
            />
          )}
          {settings.showMyListTab && (
            <NativeTab.Screen
              name="MyTab"
              component={MyListStackNavigator}
              options={nativeOptions('My List', NAV_ICONS.myList)}
            />
          )}
          {settings.showDownloadsTab && (
            <NativeTab.Screen
              name="DownloadsTab"
              component={DownloadsStackNavigator}
              options={nativeOptions('Downloads', NAV_ICONS.downloads)}
            />
          )}
          <NativeTab.Screen
            name="SettingsTab"
            component={SettingsTabScreen}
            options={nativeOptions('Settings', NAV_ICONS.settings)}
          />
        </NativeTab.Navigator>
      </View>
    );
  }

  // Fallback for Android and older iOS
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        sceneStyle: { backgroundColor: theme.shellBackground },
        tabBarShowLabel: labelMode !== 'none',
        // Hidden labels keep their space so the icons do not shift between tabs
        tabBarLabel: labelMode === 'selected'
          ? ({ focused, color, children }) => (
              <Text style={{ color, fontSize: 10, textAlign: 'center', opacity: focused ? 1 : 0 }}>{children}</Text>
            )
          : undefined,
        tabBarActiveTintColor: '#fff',
        tabBarInactiveTintColor: '#bdbdbd',
        lazy: true,
        freezeOnBlur: Platform.OS === 'android', // Freeze inactive tabs on Android for performance
        animation: Platform.OS === 'android' ? 'none' : 'fade', // Disable tab animation on Android
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
          // The macOS nav icons: outline, and filled on the selected tab
          const icons = navIconForRoute(route.name);
          return <TabGlowIcon source={focused ? icons.fill : icons.outline} size={22} color={color} glow={glowEnabled && focused} theme={theme} />;
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
      {settings.showMyListTab && (
        <Tab.Screen name="MyTab" options={{ title: 'My List' }} component={MyListStackNavigator} />
      )}
      {settings.showDownloadsTab && (
        <Tab.Screen name="DownloadsTab" options={{ title: 'Downloads' }} component={DownloadsStackNavigator} />
      )}
      <Tab.Screen name="SettingsTab" options={{ title: 'Settings' }} component={SettingsTabScreen} />
    </Tab.Navigator>
  );
});

function AppContent() {
  const { flixor, isLoading, error, isAuthenticated, isConnected, refresh, refreshProfile } = useFlixor();
  const { isLoaded: isAppModeReady, isStremioOnly } = useAppMode();
  const theme = useTheme();
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
  if (isLoading || hasCompletedOnboarding === null || !isAppModeReady) {
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
        <Text style={{ color: theme.accent, fontSize: 18, fontWeight: '600', marginBottom: 8 }}>
          Initialization Error
        </Text>
        <Text style={{ color: '#999', textAlign: 'center' }}>{error.message}</Text>
      </View>
    );
  }

  return (
    <>
      <NavigationContainer theme={navigationTheme}>
        <Stack.Navigator 
          screenOptions={{ 
            headerShown: false, 
            gestureEnabled: true, 
            gestureDirection: 'horizontal', 
            animation: 'slide_from_right', 
            fullScreenGestureEnabled: true 
          }}>
          {isStremioOnly && !hasCompletedOnboarding ? (
            // Stremio-only runs with no Plex account or server
            <Stack.Screen name="Onboarding">
              {() => <OnboardingScreen onComplete={handleOnboardingComplete} />}
            </Stack.Screen>
          ) : !isStremioOnly && !isAuthenticated ? (
            // Not logged in - show Plex login
            <Stack.Screen name="PlexLogin">
              {() => <PlexLogin onAuthenticated={refresh} />}
            </Stack.Screen>
          ) : !isStremioOnly && !isConnected ? (
            // Logged in but no server selected - show server selection
            <Stack.Screen name="ServerSelect">
              {() => <ServerSelect onConnected={refresh} />}
            </Stack.Screen>
          ) : !isStremioOnly && !hasCompletedOnboarding ? (
            // Fully connected but first time - show onboarding (includes config as final slide)
            <Stack.Screen name="Onboarding">
              {() => <OnboardingScreen onComplete={handleOnboardingComplete} />}
            </Stack.Screen>
          ) : (
            // Fully authenticated, connected, and onboarded - show main app
            <>
              <Stack.Screen name="Main" component={Tabs} />
              <Stack.Screen
                name="Downloads"
                component={Downloads}
                options={{ presentation: 'card', animation: 'slide_from_right' }}
              />
              <Stack.Screen
                name="Player"
                component={Player}
                options={{ presentation: 'fullScreenModal', animation: 'fade' }}
              />
              <Stack.Screen
                name="StremioSources"
                component={StremioSources}
                options={{ presentation: 'card', animation: 'slide_from_right' }}
              />
              <Stack.Screen
                name="ProfileSelect"
                options={{
                  presentation: 'modal',
                  animation: 'slide_from_bottom',
                  gestureEnabled: true,
                }}
              >
                {({ navigation }) => (
                  <ProfileSelect
                    onProfileSelected={async () => {
                      await refreshProfile();
                      // Reset navigation to force home screen to reload with new profile data
                      navigation.reset({
                        index: 0,
                        routes: [{ name: 'Main' }],
                      });
                    }}
                    onClose={() => navigation.goBack()}
                  />
                )}
              </Stack.Screen>
            </>
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
      <ToastHost />
    </>
  );
}

export default function App() {
  // Initialize memory manager on app start (clears image cache when app goes to background)
  useEffect(() => {
    memoryManager.initialize();

    // Initialize debug logging from persisted settings
    (async () => {
      const settings = await loadAppSettings();
      appLogger.setDebugEnabled(settings.enableDebugLogging);
      appLogger.info('App started');
    })();

    loadAppMode();

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
