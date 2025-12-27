const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const monorepoRoot = path.resolve(projectRoot, '../..');

const config = getDefaultConfig(projectRoot);

// Watch all files in the monorepo
config.watchFolders = [monorepoRoot];

// Resolve modules from both the project and the monorepo root
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(monorepoRoot, 'node_modules'),
];

// Ensure React and other shared packages resolve to the root to avoid duplicates
config.resolver.extraNodeModules = {
  'react': path.resolve(monorepoRoot, 'node_modules/react'),
  'react-native': path.resolve(monorepoRoot, 'node_modules/react-native'),
  'react-refresh': path.resolve(monorepoRoot, 'node_modules/react-refresh'),
  '@flixor/core': path.resolve(monorepoRoot, 'packages/core'),
};

// Prevent duplicate packages by disabling symlinks resolution for these
config.resolver.disableHierarchicalLookup = true;

module.exports = config;
