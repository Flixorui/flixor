/**
 * Expo config plugin to add MPV (libmpv) native files to iOS Xcode project
 *
 * This plugin:
 * 1. Copies Swift/ObjC files from native/ios/ to ios/Flixor/ during prebuild
 * 2. Adds file references to the Xcode project
 * 3. Adds MPVKit-GPL Swift Package dependency (from edde746/MPVKit)
 * 4. Configures bridging header for libmpv
 *
 * This ensures EAS builds work correctly even when ios/ is regenerated.
 */
const { withXcodeProject, withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

// Generate a unique UUID for Xcode project entries
function generateUUID() {
  return 'XXXXXXXXXXXXXXXXXXXXXXXX'.replace(/X/g, () =>
    Math.floor(Math.random() * 16).toString(16).toUpperCase()
  );
}

const withMPViOS = (config) => {
  return withXcodeProject(config, async (config) => {
    const xcodeProject = config.modResults;
    const projectName = config.modRequest.projectName || 'Flixor';
    const projectRoot = config.modRequest.projectRoot;

    // Source directory (outside ios/, survives prebuild)
    const sourceDir = path.join(projectRoot, 'native', 'ios');
    // Destination directory (inside ios/Flixor/)
    const destDir = path.join(projectRoot, 'ios', projectName);

    // MPV iOS files to copy and add
    const sourceFiles = [
      { name: 'MPVPlayerCore.swift', path: `${projectName}/MPVPlayerCore.swift` },
      { name: 'MPVPlayerView.swift', path: `${projectName}/MPVPlayerView.swift` },
      { name: 'MPVPlayerViewManager.swift', path: `${projectName}/MPVPlayerViewManager.swift` },
      { name: 'MPVPlayerModule.swift', path: `${projectName}/MPVPlayerModule.swift` },
      { name: 'MPVPlayerManager.m', path: `${projectName}/MPVPlayerManager.m` },
    ];

    // Step 1: Copy files from native/ios/ to ios/Flixor/
    console.log('[withMPViOS] Copying MPV native files...');

    // Ensure destination directory exists
    if (!fs.existsSync(destDir)) {
      fs.mkdirSync(destDir, { recursive: true });
      console.log(`[withMPViOS] Created directory: ${destDir}`);
    }

    for (const file of sourceFiles) {
      const sourcePath = path.join(sourceDir, file.name);
      const destPath = path.join(destDir, file.name);

      if (fs.existsSync(sourcePath)) {
        fs.copyFileSync(sourcePath, destPath);
        console.log(`[withMPViOS] Copied ${file.name} to ios/${projectName}/`);
      } else {
        console.warn(`[withMPViOS] WARNING: Source file not found: ${sourcePath}`);
      }
    }

    // Step 2: Add file references to Xcode project
    const target = xcodeProject.getFirstTarget().uuid;
    const mainGroupKey = xcodeProject.findPBXGroupKey({ name: projectName });

    for (const file of sourceFiles) {
      // Check if file is already in project
      const existingFile = xcodeProject.hasFile(file.path);

      if (!existingFile) {
        console.log(`[withMPViOS] Adding ${file.name} to Xcode project`);

        // Add file to project
        xcodeProject.addSourceFile(
          file.path,
          { target },
          mainGroupKey
        );
      } else {
        console.log(`[withMPViOS] ${file.name} already exists in project`);
      }
    }

    // Step 3: Add MPVKit Swift Package dependency
    console.log('[withMPViOS] Adding MPVKit Swift Package dependency...');

    const pbxProject = xcodeProject.hash.project;

    // Initialize package references array if it doesn't exist
    if (!pbxProject.objects['XCRemoteSwiftPackageReference']) {
      pbxProject.objects['XCRemoteSwiftPackageReference'] = {};
    }
    if (!pbxProject.objects['XCSwiftPackageProductDependency']) {
      pbxProject.objects['XCSwiftPackageProductDependency'] = {};
    }

    // Check if MPVKit package already exists
    const existingPackages = pbxProject.objects['XCRemoteSwiftPackageReference'];
    let mpvKitPackageKey = null;

    for (const key in existingPackages) {
      if (key.endsWith('_comment')) continue;
      const pkg = existingPackages[key];
      if (pkg && pkg.repositoryURL && pkg.repositoryURL.includes('MPVKit')) {
        mpvKitPackageKey = key;
        console.log('[withMPViOS] MPVKit package reference already exists');
        break;
      }
    }

    // Add MPVKit package reference if not exists
    // Using edde746/MPVKit which provides GPL-licensed MPVKit with all codecs
    if (!mpvKitPackageKey) {
      mpvKitPackageKey = generateUUID();
      pbxProject.objects['XCRemoteSwiftPackageReference'][mpvKitPackageKey] = {
        isa: 'XCRemoteSwiftPackageReference',
        repositoryURL: 'https://github.com/edde746/MPVKit',
        requirement: {
          kind: 'revision',
          revision: '0d0931fbbb25a3483a7edb46babd3f2f55abeefc',
        },
      };
      pbxProject.objects['XCRemoteSwiftPackageReference'][`${mpvKitPackageKey}_comment`] = 'XCRemoteSwiftPackageReference "MPVKit"';
      console.log('[withMPViOS] Added MPVKit package reference');
    }

    // Add package reference to project
    const projectKey = xcodeProject.getFirstProject().uuid;
    const project = pbxProject.objects['PBXProject'][projectKey];

    if (!project.packageReferences) {
      project.packageReferences = [];
    }

    const hasPackageRef = project.packageReferences.some(
      ref => ref.value === mpvKitPackageKey
    );

    if (!hasPackageRef) {
      project.packageReferences.push({
        value: mpvKitPackageKey,
        comment: 'XCRemoteSwiftPackageReference "MPVKit"',
      });
      console.log('[withMPViOS] Added package reference to project');
    }

    // Add MPVKit product dependency to target (Libmpv library)
    const nativeTarget = xcodeProject.getFirstTarget();
    const targetKey = nativeTarget.uuid;
    const targetObj = pbxProject.objects['PBXNativeTarget'][targetKey];

    if (!targetObj.packageProductDependencies) {
      targetObj.packageProductDependencies = [];
    }

    // Check if MPVKit-GPL dependency already exists
    let hasMpvKitDep = false;
    const productDeps = pbxProject.objects['XCSwiftPackageProductDependency'];
    for (const depRef of targetObj.packageProductDependencies) {
      const depKey = depRef.value || depRef;
      const dep = productDeps[depKey];
      if (dep && (dep.productName === 'MPVKit-GPL' || dep.productName === 'MPVKit')) {
        hasMpvKitDep = true;
        break;
      }
    }

    if (!hasMpvKitDep) {
      const mpvKitDepKey = generateUUID();
      pbxProject.objects['XCSwiftPackageProductDependency'][mpvKitDepKey] = {
        isa: 'XCSwiftPackageProductDependency',
        package: mpvKitPackageKey,
        productName: 'MPVKit-GPL',
      };
      pbxProject.objects['XCSwiftPackageProductDependency'][`${mpvKitDepKey}_comment`] = 'MPVKit-GPL';

      targetObj.packageProductDependencies.push({
        value: mpvKitDepKey,
        comment: 'MPVKit-GPL',
      });
      console.log('[withMPViOS] Added MPVKit-GPL product dependency to target');
    }

    // Ensure bridging header is configured
    const buildSettings = xcodeProject.getBuildProperty('SWIFT_OBJC_BRIDGING_HEADER');
    if (!buildSettings) {
      console.log('[withMPViOS] Setting bridging header');
      xcodeProject.addBuildProperty(
        'SWIFT_OBJC_BRIDGING_HEADER',
        `${projectName}/${projectName}-Bridging-Header.h`
      );
    }

    // Set minimum iOS deployment target for Metal/Vulkan support
    console.log('[withMPViOS] Setting iOS deployment target to 14.0...');
    xcodeProject.addBuildProperty('IPHONEOS_DEPLOYMENT_TARGET', '14.0');

    return config;
  });
};

// Wrapper to also handle bridging header modifications
const withMPViOSAndBridgingHeader = (config) => {
  // First, apply the Xcode project modifications
  config = withMPViOS(config);

  // Then, modify the bridging header to include libmpv
  config = withDangerousMod(config, [
    'ios',
    async (config) => {
      const projectName = config.modRequest.projectName || 'Flixor';
      const bridgingHeaderPath = path.join(
        config.modRequest.platformProjectRoot,
        projectName,
        `${projectName}-Bridging-Header.h`
      );

      // React Native imports needed for Swift view managers
      const reactImports = `
// React Native headers
#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>
`;

      // MPV imports to add
      const mpvImports = `
// MPV (libmpv) headers for video playback
#if __has_include(<Libmpv/client.h>)
#import <Libmpv/client.h>
#import <Libmpv/render.h>
#import <Libmpv/render_gl.h>
#endif
`;

      if (fs.existsSync(bridgingHeaderPath)) {
        let headerContent = fs.readFileSync(bridgingHeaderPath, 'utf8');
        let modified = false;

        // Check if React imports already exist
        if (!headerContent.includes('RCTBridgeModule.h')) {
          // Add React imports after the initial comment block
          const insertPoint = headerContent.indexOf('//\n\n') + 4;
          if (insertPoint > 3) {
            headerContent = headerContent.slice(0, insertPoint) + reactImports + headerContent.slice(insertPoint);
          } else {
            headerContent = headerContent.trimEnd() + '\n' + reactImports;
          }
          modified = true;
          console.log('[withMPViOS] Added React Native imports to bridging header');
        }

        // Check if MPV imports already exist
        if (!headerContent.includes('Libmpv/client.h')) {
          // Add MPV imports at the end of the file
          headerContent = headerContent.trimEnd() + '\n' + mpvImports;
          modified = true;
          console.log('[withMPViOS] Added libmpv imports to bridging header');
        }

        if (modified) {
          fs.writeFileSync(bridgingHeaderPath, headerContent);
        } else {
          console.log('[withMPViOS] All imports already in bridging header');
        }
      } else {
        // Create bridging header if it doesn't exist
        const headerContent = `//
//  ${projectName}-Bridging-Header.h
//  ${projectName}
//
//  Created by Expo
//

#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>
${mpvImports}
`;
        // Ensure directory exists
        const headerDir = path.dirname(bridgingHeaderPath);
        if (!fs.existsSync(headerDir)) {
          fs.mkdirSync(headerDir, { recursive: true });
        }
        fs.writeFileSync(bridgingHeaderPath, headerContent);
        console.log('[withMPViOS] Created bridging header with libmpv imports');
      }

      return config;
    },
  ]);

  return config;
};

module.exports = withMPViOSAndBridgingHeader;
