import React from 'react';
import { View, Text } from 'react-native';
import { FontAwesome5 } from '@expo/vector-icons';
import { Ionicons } from '@expo/vector-icons';

export default function BadgePill({ icon, label }: { icon?: 'cc'|'ad'|'dolby'|'hd'|'5.1'|'hdr'|'hdr10'|'hdr10+'|'hlg'; label?: string }) {
  const bg = { backgroundColor:'#1a1b20', paddingHorizontal:10, paddingVertical:6, borderRadius:8, flexDirection:'row', alignItems:'center' } as const;
  const textStyle = { color:'#fff', fontWeight:'700', fontSize:12 } as const;

  if (icon === 'cc') {
    return (
      <View style={bg}>
        <FontAwesome5 name="closed-captioning" size={12} color="#fff" />
        {label ? <Text style={[textStyle, { marginLeft:6 }]}>{label}</Text> : null}
      </View>
    );
  }
  if (icon === 'ad') {
    return (
      <View style={bg}>
        <FontAwesome5 name="audio-description" size={12} color="#fff" />
        {label ? <Text style={[textStyle, { marginLeft:6 }]}>{label}</Text> : null}
      </View>
    );
  }
  if (icon === 'hd') {
    return (
      <View style={bg}>
        <Text style={textStyle}>HD</Text>
      </View>
    );
  }
  if (icon === 'dolby') {
    return (
      <View style={[bg, { backgroundColor: '#9b59b6' }]}>
        <Text style={textStyle}>DV</Text>
      </View>
    );
  }
  if (icon === 'hdr' || icon === 'hdr10') {
    return (
      <View style={[bg, { backgroundColor: '#8e44ad' }]}>
        <Text style={textStyle}>HDR10</Text>
      </View>
    );
  }
  if (icon === 'hdr10+') {
    return (
      <View style={[bg, { backgroundColor: '#9b59b6' }]}>
        <Text style={textStyle}>HDR10+</Text>
      </View>
    );
  }
  if (icon === 'hlg') {
    return (
      <View style={[bg, { backgroundColor: '#27ae60' }]}>
        <Text style={textStyle}>HLG</Text>
      </View>
    );
  }
  if (icon === '5.1') {
    return (
      <View style={bg}>
        <Text style={textStyle}>5.1</Text>
      </View>
    );
  }
  // Default text label pill
  return (
    <View style={bg}>
      <Text style={textStyle}>{label}</Text>
    </View>
  );
}

