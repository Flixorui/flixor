import React, { useEffect } from 'react';
import { useWindowDimensions, StyleSheet, View } from 'react-native';
import Animated, {
    useSharedValue,
    useAnimatedStyle,
    withRepeat,
    withTiming,
    Easing,
    interpolate,
    Extrapolation,
    SharedValue,
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';

// Color palettes for each slide
const COLOR_PALETTES = [
    ['#FFD700', '#FF6B00'], // Star: Gold -> Orange
    ['#7C3AED', '#EC4899'], // Plugin: Purple -> Pink
    ['#00D9FF', '#0EA5E9'], // Search: Cyan -> Blue
    ['#FF006E', '#FB7185'], // Heart: Pink -> Rose
];

interface ShapeAnimationProps {
    scrollX: SharedValue<number>;
}

export const ShapeAnimation: React.FC<ShapeAnimationProps> = ({ scrollX }) => {
    const rotation = useSharedValue(0);
    const pulse = useSharedValue(0);
    const { width: windowWidth, height: windowHeight } = useWindowDimensions();

    // Rotation animation
    useEffect(() => {
        rotation.value = withRepeat(
            withTiming(360, {
                duration: 20000,
                easing: Easing.linear,
            }),
            -1,
            false
        );
        pulse.value = withRepeat(
            withTiming(1, {
                duration: 3000,
                easing: Easing.inOut(Easing.ease),
            }),
            -1,
            true
        );
    }, []);

    const inputRange = [0, windowWidth, windowWidth * 2, windowWidth * 3];

    // Animated orb 1 (large, background)
    const orb1Style = useAnimatedStyle(() => {
        const translateX = interpolate(
            scrollX.value,
            inputRange,
            [windowWidth * 0.3, windowWidth * 0.6, windowWidth * 0.2, windowWidth * 0.7],
            Extrapolation.CLAMP
        );
        const translateY = interpolate(
            scrollX.value,
            inputRange,
            [windowHeight * 0.5, windowHeight * 0.4, windowHeight * 0.6, windowHeight * 0.45],
            Extrapolation.CLAMP
        );
        const scale = 1 + pulse.value * 0.15;
        return {
            transform: [
                { translateX },
                { translateY },
                { scale },
                { rotate: `${rotation.value}deg` },
            ],
            opacity: 0.4,
        };
    });

    // Animated orb 2 (medium)
    const orb2Style = useAnimatedStyle(() => {
        const translateX = interpolate(
            scrollX.value,
            inputRange,
            [windowWidth * 0.6, windowWidth * 0.3, windowWidth * 0.7, windowWidth * 0.4],
            Extrapolation.CLAMP
        );
        const translateY = interpolate(
            scrollX.value,
            inputRange,
            [windowHeight * 0.3, windowHeight * 0.6, windowHeight * 0.4, windowHeight * 0.55],
            Extrapolation.CLAMP
        );
        const scale = 1 + pulse.value * 0.2;
        return {
            transform: [
                { translateX },
                { translateY },
                { scale },
                { rotate: `${-rotation.value * 0.7}deg` },
            ],
            opacity: 0.3,
        };
    });

    // Animated orb 3 (small, accent)
    const orb3Style = useAnimatedStyle(() => {
        const translateX = interpolate(
            scrollX.value,
            inputRange,
            [windowWidth * 0.5, windowWidth * 0.4, windowWidth * 0.6, windowWidth * 0.5],
            Extrapolation.CLAMP
        );
        const translateY = interpolate(
            scrollX.value,
            inputRange,
            [windowHeight * 0.65, windowHeight * 0.55, windowHeight * 0.5, windowHeight * 0.6],
            Extrapolation.CLAMP
        );
        const scale = 1 + pulse.value * 0.25;
        return {
            transform: [
                { translateX },
                { translateY },
                { scale },
                { rotate: `${rotation.value * 1.3}deg` },
            ],
            opacity: 0.5,
        };
    });

    // Get current color palette based on scroll
    const getColorIndex = () => {
        const index = Math.round(scrollX.value / windowWidth);
        return Math.min(Math.max(index, 0), COLOR_PALETTES.length - 1);
    };

    return (
        <View style={[styles.container, { width: windowWidth, height: windowHeight }]}>
            {/* Large background orb */}
            <Animated.View style={[styles.orb, styles.orb1, orb1Style]}>
                <LinearGradient
                    colors={['#FFD70050', '#FF6B0030']}
                    style={styles.orbGradient}
                    start={{ x: 0, y: 0 }}
                    end={{ x: 1, y: 1 }}
                />
            </Animated.View>

            {/* Medium orb */}
            <Animated.View style={[styles.orb, styles.orb2, orb2Style]}>
                <LinearGradient
                    colors={['#7C3AED40', '#EC489930']}
                    style={styles.orbGradient}
                    start={{ x: 0, y: 0 }}
                    end={{ x: 1, y: 1 }}
                />
            </Animated.View>

            {/* Small accent orb */}
            <Animated.View style={[styles.orb, styles.orb3, orb3Style]}>
                <LinearGradient
                    colors={['#00D9FF50', '#0EA5E940']}
                    style={styles.orbGradient}
                    start={{ x: 0, y: 0 }}
                    end={{ x: 1, y: 1 }}
                />
            </Animated.View>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        position: 'absolute',
        top: 0,
        left: 0,
        overflow: 'hidden',
    },
    orb: {
        position: 'absolute',
        borderRadius: 999,
        overflow: 'hidden',
    },
    orb1: {
        width: 400,
        height: 400,
        marginLeft: -200,
        marginTop: -200,
    },
    orb2: {
        width: 280,
        height: 280,
        marginLeft: -140,
        marginTop: -140,
    },
    orb3: {
        width: 180,
        height: 180,
        marginLeft: -90,
        marginTop: -90,
    },
    orbGradient: {
        width: '100%',
        height: '100%',
        borderRadius: 999,
    },
});

export default ShapeAnimation;
