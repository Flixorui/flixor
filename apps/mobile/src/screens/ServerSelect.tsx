import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  ActivityIndicator,
  Alert,
  FlatList,
  RefreshControl,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFlixor } from '../core';
import type { PlexServer } from '@flixor/core';

interface ServerSelectProps {
  onConnected: () => void;
}

export default function ServerSelect({ onConnected }: ServerSelectProps) {
  const { flixor } = useFlixor();
  const [servers, setServers] = useState<PlexServer[]>([]);
  const [loading, setLoading] = useState(true);
  const [connecting, setConnecting] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const loadServers = async () => {
    if (!flixor) return;

    try {
      console.log('[ServerSelect] Loading servers...');
      const serverList = await flixor.getServers();
      console.log('[ServerSelect] Found', serverList.length, 'servers');
      setServers(serverList);
    } catch (e: any) {
      console.log('[ServerSelect] Error loading servers:', e?.message);
      Alert.alert('Error', 'Failed to load servers. Please try again.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadServers();
  }, [flixor]);

  const connectToServer = async (server: PlexServer) => {
    if (!flixor) return;

    try {
      setConnecting(server.id);
      console.log('[ServerSelect] Connecting to server:', server.name);

      await flixor.connectToServer(server);
      console.log('[ServerSelect] Connected successfully');
      onConnected();
    } catch (e: any) {
      console.log('[ServerSelect] Connection error:', e?.message);
      Alert.alert(
        'Connection Failed',
        `Could not connect to ${server.name}. Make sure the server is online and accessible.`
      );
    } finally {
      setConnecting(null);
    }
  };

  const handleRefresh = () => {
    setRefreshing(true);
    loadServers();
  };

  const renderServer = ({ item: server }: { item: PlexServer }) => {
    const isConnecting = connecting === server.id;
    const isOnline = server.presence;

    return (
      <Pressable
        onPress={() => connectToServer(server)}
        disabled={isConnecting || connecting !== null}
        style={{
          backgroundColor: '#1a1a1a',
          borderRadius: 12,
          padding: 16,
          marginBottom: 12,
          flexDirection: 'row',
          alignItems: 'center',
          opacity: connecting && !isConnecting ? 0.5 : 1,
        }}
      >
        <View
          style={{
            width: 48,
            height: 48,
            borderRadius: 24,
            backgroundColor: '#333',
            alignItems: 'center',
            justifyContent: 'center',
            marginRight: 16,
          }}
        >
          <Ionicons name="server" size={24} color="#e50914" />
        </View>

        <View style={{ flex: 1 }}>
          <Text style={{ color: '#fff', fontSize: 16, fontWeight: '600', marginBottom: 4 }}>
            {server.name}
          </Text>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <View
              style={{
                width: 8,
                height: 8,
                borderRadius: 4,
                backgroundColor: isOnline ? '#4caf50' : '#ff9800',
                marginRight: 6,
              }}
            />
            <Text style={{ color: '#999', fontSize: 12 }}>
              {isOnline ? 'Online' : 'Offline'}
              {server.owned ? '' : ' • Shared'}
            </Text>
          </View>
          {server.connections.length > 0 && (
            <Text style={{ color: '#666', fontSize: 11, marginTop: 2 }}>
              {server.connections.length} connection{server.connections.length !== 1 ? 's' : ''} available
            </Text>
          )}
        </View>

        {isConnecting ? (
          <ActivityIndicator color="#e50914" />
        ) : (
          <Ionicons name="chevron-forward" size={20} color="#666" />
        )}
      </Pressable>
    );
  };

  if (loading) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" size="large" />
        <Text style={{ color: '#666', marginTop: 16 }}>Loading servers...</Text>
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#000', padding: 24 }}>
      <View style={{ marginTop: 60, marginBottom: 24 }}>
        <Text style={{ color: '#fff', fontSize: 28, fontWeight: '800', marginBottom: 8 }}>
          Select a Server
        </Text>
        <Text style={{ color: '#999', fontSize: 14 }}>
          Choose a Plex server to connect to
        </Text>
      </View>

      {servers.length === 0 ? (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Ionicons name="server-outline" size={64} color="#333" />
          <Text style={{ color: '#999', fontSize: 16, marginTop: 16, textAlign: 'center' }}>
            No servers found
          </Text>
          <Text style={{ color: '#666', fontSize: 14, marginTop: 8, textAlign: 'center', maxWidth: 280 }}>
            Make sure you have at least one Plex Media Server set up and linked to your account.
          </Text>
          <Pressable
            onPress={handleRefresh}
            style={{
              marginTop: 24,
              backgroundColor: '#333',
              paddingHorizontal: 20,
              paddingVertical: 12,
              borderRadius: 8,
            }}
          >
            <Text style={{ color: '#fff', fontWeight: '600' }}>Refresh</Text>
          </Pressable>
        </View>
      ) : (
        <FlatList
          data={servers}
          renderItem={renderServer}
          keyExtractor={(item) => item.id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor="#e50914"
            />
          }
          ListFooterComponent={
            <Text style={{ color: '#666', fontSize: 12, textAlign: 'center', marginTop: 16 }}>
              Pull to refresh server list
            </Text>
          }
        />
      )}
    </View>
  );
}
