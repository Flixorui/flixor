import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { View, ActivityIndicator, Text } from 'react-native';
import GlobalTopAppBar from './src/components/GlobalTopAppBar';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { useTopBarStore } from './src/components/TopBarStore';

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
import { Platform } from 'react-native';

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
const MyListStack = createNativeStackNavigator();

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

  const Tabs = () => {
    const tabBarVisible = useTopBarStore(s => s.tabBarVisible === true);

    return (
      <Tab.Navigator
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
            borderRadius: 0,
            borderTopWidth: 0,
            height: 68,
            paddingBottom: 20,
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
        <Tab.Screen name="NewHotTab" options={{ title: 'New & Hot' }}>
          {() => (
            <View style={{ flex: 1 }}>
              <NewHot />
              <GlobalTopAppBar />
            </View>
          )}
        </Tab.Screen>
        <Tab.Screen name="MyTab" options={{ title: 'My List' }}>
          {() => (
            <MyListStack.Navigator screenOptions={{ headerShown: false }}>
              <MyListStack.Screen name="MyListScreen">
                {({ navigation }) => (
                  <View style={{ flex: 1 }}>
                    <MyList onOpenSettings={() => navigation.navigate('Settings')} />
                    <GlobalTopAppBar />
                  </View>
                )}
              </MyListStack.Screen>
              <MyListStack.Screen name="Settings">
                {({ navigation }) => (
                  <Settings onLogout={handleLogout} onBack={() => navigation.goBack()} />
                )}
              </MyListStack.Screen>
              <MyListStack.Screen name="CatalogSettings" component={CatalogSettings} />
              <MyListStack.Screen name="HomeScreenSettings" component={HomeScreenSettings} />
              <MyListStack.Screen name="ContinueWatchingSettings" component={ContinueWatchingSettings} />
              <MyListStack.Screen name="TMDBSettings" component={TMDBSettings} />
              <MyListStack.Screen name="TraktSettings" component={TraktSettings} />
            </MyListStack.Navigator>
          )}
        </Tab.Screen>
        <Tab.Screen name="SettingsTab" options={{ title: 'Settings' }}>
          {() => (
            <View style={{ flex: 1 }}></View>
          )}
        </Tab.Screen>
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
