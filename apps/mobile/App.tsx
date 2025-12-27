import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs';
import { View, ActivityIndicator, Text, Pressable, Platform } from 'react-native';
import GlobalTopAppBar from './src/components/GlobalTopAppBar';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { useTopBarStore } from './src/components/TopBarStore';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

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
import ContinueWatchingSettings from './src/screens/settings/ContinueWatchingSettings';
import TMDBSettings from './src/screens/settings/TMDBSettings';
import TraktSettings from './src/screens/settings/TraktSettings';
import * as Haptics from 'expo-haptics';

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

// Note: expo-image uses disk cache by default (cachePolicy="disk" or "memory-disk")
// Cache limits are managed by the OS and expo-image internally

type RootStackParamList = {
  PlexLogin: undefined;
  ServerSelect: undefined;
  Main: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator();
const HomeStack = createNativeStackNavigator();
const SettingsStack = createNativeStackNavigator();

function AppContent() {
  const { flixor, isLoading, error, isAuthenticated, isConnected, refresh } = useFlixor();

  const handleLogout = async () => {
    if (flixor) {
      await flixor.logout();
      refresh();
    }
  };

  // Show loading screen during initialization
  if (isLoading) {
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

  const HomeStackNavigator = () => {
    const topBarVisible = useTopBarStore(s => s.visible === true);

    return (
      <View style={{ flex: 1 }}>
        <HomeStack.Navigator screenOptions={{ headerShown: false }}>
          <HomeStack.Screen name="HomeScreen">
            {() => <Home onLogout={handleLogout} />}
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
        {topBarVisible && <GlobalTopAppBar />}
      </View>
    );
  };

  // Screen wrapper components for native iOS tabs
  const NewHotScreen = () => (
    <View style={{ flex: 1 }}>
      <NewHot />
      <GlobalTopAppBar />
    </View>
  );

  const MyListScreen = () => (
    <View style={{ flex: 1 }}>
      <MyList />
      <GlobalTopAppBar />
    </View>
  );

  const SettingsTabScreen = () => (
    <SettingsStack.Navigator screenOptions={{ headerShown: false }}>
      <SettingsStack.Screen name="SettingsMain">
        {() => (
          <Settings onLogout={handleLogout} />
        )}
      </SettingsStack.Screen>
      <SettingsStack.Screen name="CatalogSettings" component={CatalogSettings} />
      <SettingsStack.Screen name="HomeScreenSettings" component={HomeScreenSettings} />
      <SettingsStack.Screen name="ContinueWatchingSettings" component={ContinueWatchingSettings} />
      <SettingsStack.Screen name="TMDBSettings" component={TMDBSettings} />
      <SettingsStack.Screen name="TraktSettings" component={TraktSettings} />
    </SettingsStack.Navigator>
  );

  const Tabs = () => {
    const tabBarVisible = useTopBarStore(s => s.tabBarVisible === true);
    const insets = useSafeAreaInsets();

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
              lazy: true,
              freezeOnBlur: true,
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
              name="NewHotTab"
              component={NewHotScreen}
              options={{
                title: 'New & Hot',
                tabBarIcon: () => ({ sfSymbol: 'play.circle' }),
              }}
            />
            <IOSTab.Screen
              name="MyTab"
              component={MyListScreen}
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
            Platform.OS === 'ios'
              ? <BlurView intensity={90} tint="dark" style={{ flex: 1 }} />
              : <View style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.9)' }} />
          ),
          tabBarIcon: ({ color, focused }) => {
            const name = route.name === 'HomeTab' ? (focused ? 'home' : 'home-outline')
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
        <Tab.Screen name="NewHotTab" options={{ title: 'New & Hot' }} component={NewHotScreen} />
        <Tab.Screen name="MyTab" options={{ title: 'My List' }} component={MyListScreen} />
        <Tab.Screen name="SettingsTab" options={{ title: 'Settings' }} component={SettingsTabScreen} />
      </Tab.Navigator>
    );
  };

  return (
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
        ) : (
          // Fully authenticated and connected - show main app
          <Stack.Screen name="Main" component={Tabs} />
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default function App() {
  return (
    <FlixorProvider>
      <AppContent />
    </FlixorProvider>
  );
}
