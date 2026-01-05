import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

type SettingItemProps = {
  title: string;
  description?: string;
  icon?: keyof typeof Ionicons.glyphMap;
  renderIcon?: () => React.ReactNode;
  renderRight?: () => React.ReactNode;
  onPress?: () => void;
  disabled?: boolean;
  isLast?: boolean;
};

export default function SettingItem({
  title,
  description,
  icon,
  renderIcon,
  renderRight,
  onPress,
  disabled,
  isLast,
}: SettingItemProps) {
  return (
    <Pressable
      onPress={disabled ? undefined : onPress}
      style={[
        styles.row,
        !isLast && styles.rowBorder,
        disabled && styles.rowDisabled,
      ]}
    >
      <View style={styles.iconWrap}>
        {renderIcon ? renderIcon() : <Ionicons name={icon || 'settings-outline'} size={18} color="#e5e7eb" />}
      </View>
      <View style={styles.textWrap}>
        <Text style={styles.title}>{title}</Text>
        {description ? <Text style={styles.description} numberOfLines={1}>{description}</Text> : null}
      </View>
      {renderRight ? <View style={styles.rightWrap}>{renderRight()}</View> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  rowBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  rowDisabled: {
    opacity: 0.5,
  },
  iconWrap: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: 'rgba(229,231,235,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  textWrap: {
    flex: 1,
  },
  title: {
    color: '#f9fafb',
    fontSize: 15,
    fontWeight: '600',
  },
  description: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 2,
  },
  rightWrap: {
    marginLeft: 8,
  },
});
