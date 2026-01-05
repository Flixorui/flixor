/**
 * Expo config plugin to add KSPlayer native files to Xcode project
 *
 * This plugin:
 * 1. Copies Swift/ObjC files from native/ios/ to ios/Flixor/ during prebuild
 * 2. Adds file references to the Xcode project
 * 3. Adds KSPlayer Swift Package dependency
 * 4. Removes KSPlayer CocoaPods references (SPM is used instead)
 * 5. Adds build script to fix invalid bundle identifiers in KSPlayer frameworks
 *
 * This ensures EAS builds work correctly even when ios/ is regenerated.
 */
const { withXcodeProject, withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

// Script to fix invalid bundle identifiers in KSPlayer frameworks
// libshaderc_combined has underscores which Apple doesn't allow
// Must also re-sign the framework so code signature identifier matches
const FIX_BUNDLE_ID_SCRIPT = `
# Fix invalid CFBundleIdentifier in KSPlayer frameworks and re-sign
# Apple doesn't allow underscores in bundle identifiers
# The code signature identifier must also match the bundle identifier

FRAMEWORKS_PATH="\${BUILT_PRODUCTS_DIR}/\${FRAMEWORKS_FOLDER_PATH}"
if [ -d "$FRAMEWORKS_PATH" ]; then
  for framework in "$FRAMEWORKS_PATH"/*.framework; do
    if [ -d "$framework" ]; then
      PLIST="$framework/Info.plist"
      if [ -f "$PLIST" ]; then
        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "")
        if [[ "$BUNDLE_ID" == *"_"* ]]; then
          FIXED_ID=$(echo "$BUNDLE_ID" | tr '_' '-')
          FRAMEWORK_NAME=$(basename "$framework" .framework)
          echo "Fixing bundle identifier for $FRAMEWORK_NAME: $BUNDLE_ID -> $FIXED_ID"

          # Update the bundle identifier in Info.plist
          /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $FIXED_ID" "$PLIST"

          # Re-sign the framework with the correct identifier
          # This ensures code signature identifier matches bundle identifier
          if [ -n "\${EXPANDED_CODE_SIGN_IDENTITY}" ] && [ "\${CODE_SIGNING_REQUIRED}" != "NO" ]; then
            echo "Re-signing $FRAMEWORK_NAME with identifier $FIXED_ID"
            codesign --force --sign "\${EXPANDED_CODE_SIGN_IDENTITY}" --identifier "$FIXED_ID" --preserve-metadata=entitlements,flags,runtime "$framework"
          elif [ -n "\${CODE_SIGN_IDENTITY}" ] && [ "\${CODE_SIGNING_REQUIRED}" != "NO" ]; then
            echo "Re-signing $FRAMEWORK_NAME with identifier $FIXED_ID (using CODE_SIGN_IDENTITY)"
            codesign --force --sign "\${CODE_SIGN_IDENTITY}" --identifier "$FIXED_ID" --preserve-metadata=entitlements,flags,runtime "$framework"
          else
            echo "Warning: No code signing identity found, skipping re-sign"
          fi
        fi
      fi
    fi
  done
fi
`;

// Generate a unique UUID for Xcode project entries
function generateUUID() {
  return 'XXXXXXXXXXXXXXXXXXXXXXXX'.replace(/X/g, () =>
    Math.floor(Math.random() * 16).toString(16).toUpperCase()
  );
}

const withKSPlayer = (config) => {
  return withXcodeProject(config, async (config) => {
    const xcodeProject = config.modResults;
    const projectName = config.modRequest.projectName || 'Flixor';
    const projectRoot = config.modRequest.projectRoot;

    // Source directory (outside ios/, survives prebuild)
    const sourceDir = path.join(projectRoot, 'native', 'ios');
    // Destination directory (inside ios/Flixor/)
    const destDir = path.join(projectRoot, 'ios', projectName);

    // Files to copy and add
    const sourceFiles = [
      { name: 'KSPlayerView.swift', path: `${projectName}/KSPlayerView.swift` },
      { name: 'KSPlayerViewManager.swift', path: `${projectName}/KSPlayerViewManager.swift` },
      { name: 'KSPlayerModule.swift', path: `${projectName}/KSPlayerModule.swift` },
      { name: 'KSPlayerManager.m', path: `${projectName}/KSPlayerManager.m` },
    ];

    // Step 1: Copy files from native/ios/ to ios/Flixor/
    console.log('[withKSPlayer] Copying KSPlayer native files...');

    // Ensure destination directory exists
    if (!fs.existsSync(destDir)) {
      fs.mkdirSync(destDir, { recursive: true });
      console.log(`[withKSPlayer] Created directory: ${destDir}`);
    }

    for (const file of sourceFiles) {
      const sourcePath = path.join(sourceDir, file.name);
      const destPath = path.join(destDir, file.name);

      if (fs.existsSync(sourcePath)) {
        fs.copyFileSync(sourcePath, destPath);
        console.log(`[withKSPlayer] Copied ${file.name} to ios/${projectName}/`);
      } else {
        console.warn(`[withKSPlayer] WARNING: Source file not found: ${sourcePath}`);
      }
    }

    // Step 2: Add file references to Xcode project
    const target = xcodeProject.getFirstTarget().uuid;
    const mainGroupKey = xcodeProject.findPBXGroupKey({ name: projectName });

    for (const file of sourceFiles) {
      // Check if file is already in project
      const existingFile = xcodeProject.hasFile(file.path);

      if (!existingFile) {
        console.log(`[withKSPlayer] Adding ${file.name} to Xcode project`);

        // Add file to project
        xcodeProject.addSourceFile(
          file.path,
          { target },
          mainGroupKey
        );
      } else {
        console.log(`[withKSPlayer] ${file.name} already exists in project`);
      }
    }

    // Step 3: Add KSPlayer Swift Package dependency
    console.log('[withKSPlayer] Adding KSPlayer Swift Package dependency...');

    const pbxProject = xcodeProject.hash.project;

    // Initialize package references array if it doesn't exist
    if (!pbxProject.objects['XCRemoteSwiftPackageReference']) {
      pbxProject.objects['XCRemoteSwiftPackageReference'] = {};
    }
    if (!pbxProject.objects['XCSwiftPackageProductDependency']) {
      pbxProject.objects['XCSwiftPackageProductDependency'] = {};
    }

    // Check if KSPlayer package already exists
    const existingPackages = pbxProject.objects['XCRemoteSwiftPackageReference'];
    let ksPlayerPackageKey = null;

    for (const key in existingPackages) {
      if (key.endsWith('_comment')) continue;
      const pkg = existingPackages[key];
      if (pkg && pkg.repositoryURL && pkg.repositoryURL.includes('KSPlayer')) {
        ksPlayerPackageKey = key;
        console.log('[withKSPlayer] KSPlayer package reference already exists');
        break;
      }
    }

    // Add KSPlayer package reference if not exists
    if (!ksPlayerPackageKey) {
      ksPlayerPackageKey = generateUUID();
      pbxProject.objects['XCRemoteSwiftPackageReference'][ksPlayerPackageKey] = {
        isa: 'XCRemoteSwiftPackageReference',
        repositoryURL: 'https://github.com/kingslay/KSPlayer.git',
        requirement: {
          kind: 'branch',
          branch: 'main',
        },
      };
      pbxProject.objects['XCRemoteSwiftPackageReference'][`${ksPlayerPackageKey}_comment`] = 'XCRemoteSwiftPackageReference "KSPlayer"';
      console.log('[withKSPlayer] Added KSPlayer package reference');
    }

    // Add package reference to project
    const projectKey = xcodeProject.getFirstProject().uuid;
    const project = pbxProject.objects['PBXProject'][projectKey];

    if (!project.packageReferences) {
      project.packageReferences = [];
    }

    const hasPackageRef = project.packageReferences.some(
      ref => ref.value === ksPlayerPackageKey
    );

    if (!hasPackageRef) {
      project.packageReferences.push({
        value: ksPlayerPackageKey,
        comment: 'XCRemoteSwiftPackageReference "KSPlayer"',
      });
      console.log('[withKSPlayer] Added package reference to project');
    }

    // Add KSPlayer product dependency to target
    const nativeTarget = xcodeProject.getFirstTarget();
    const targetKey = nativeTarget.uuid;
    const targetObj = pbxProject.objects['PBXNativeTarget'][targetKey];

    if (!targetObj.packageProductDependencies) {
      targetObj.packageProductDependencies = [];
    }

    // Check if KSPlayer dependency already exists
    let hasKSPlayerDep = false;
    const productDeps = pbxProject.objects['XCSwiftPackageProductDependency'];
    for (const depRef of targetObj.packageProductDependencies) {
      const depKey = depRef.value || depRef;
      const dep = productDeps[depKey];
      if (dep && dep.productName === 'KSPlayer') {
        hasKSPlayerDep = true;
        break;
      }
    }

    if (!hasKSPlayerDep) {
      const ksPlayerDepKey = generateUUID();
      pbxProject.objects['XCSwiftPackageProductDependency'][ksPlayerDepKey] = {
        isa: 'XCSwiftPackageProductDependency',
        package: ksPlayerPackageKey,
        productName: 'KSPlayer',
      };
      pbxProject.objects['XCSwiftPackageProductDependency'][`${ksPlayerDepKey}_comment`] = 'KSPlayer';

      targetObj.packageProductDependencies.push({
        value: ksPlayerDepKey,
        comment: 'KSPlayer',
      });
      console.log('[withKSPlayer] Added KSPlayer product dependency to target');
    }

    // Ensure bridging header is configured
    const buildSettings = xcodeProject.getBuildProperty('SWIFT_OBJC_BRIDGING_HEADER');
    if (!buildSettings) {
      console.log('[withKSPlayer] Setting bridging header');
      xcodeProject.addBuildProperty(
        'SWIFT_OBJC_BRIDGING_HEADER',
        `${projectName}/${projectName}-Bridging-Header.h`
      );
    }

    // Step 4: Add build script to fix invalid bundle identifiers
    // This must run BEFORE code signing (which happens in the "Copy Bundle Resources" phase)
    console.log('[withKSPlayer] Adding bundle identifier fix script...');

    const scriptName = '[KSPlayer] Fix Framework Bundle IDs';

    // Check if script already exists
    const buildPhases = targetObj.buildPhases || [];
    let scriptExists = false;

    for (const phaseRef of buildPhases) {
      const phaseKey = phaseRef.value || phaseRef;
      const phase = pbxProject.objects['PBXShellScriptBuildPhase']?.[phaseKey];
      if (phase && phase.name && phase.name.includes('Fix Framework Bundle IDs')) {
        scriptExists = true;
        console.log('[withKSPlayer] Bundle ID fix script already exists');
        break;
      }
    }

    if (!scriptExists) {
      const scriptKey = generateUUID();

      // Create the shell script build phase
      if (!pbxProject.objects['PBXShellScriptBuildPhase']) {
        pbxProject.objects['PBXShellScriptBuildPhase'] = {};
      }

      pbxProject.objects['PBXShellScriptBuildPhase'][scriptKey] = {
        isa: 'PBXShellScriptBuildPhase',
        buildActionMask: 2147483647,
        files: [],
        inputPaths: [],
        name: `"${scriptName}"`,
        outputPaths: [],
        runOnlyForDeploymentPostprocessing: 0,
        shellPath: '/bin/sh',
        shellScript: JSON.stringify(FIX_BUNDLE_ID_SCRIPT),
      };
      pbxProject.objects['PBXShellScriptBuildPhase'][`${scriptKey}_comment`] = scriptName;

      // Add to target's build phases (near the end, before code signing)
      targetObj.buildPhases.push({
        value: scriptKey,
        comment: scriptName,
      });

      console.log('[withKSPlayer] Added bundle identifier fix script to build phases');
    }

    return config;
  });
};

// Wrapper to also handle Podfile modifications
const withKSPlayerAndPodfile = (config) => {
  // First, apply the Xcode project modifications
  config = withKSPlayer(config);

  // Then, modify the Podfile to remove any KSPlayer pod references
  config = withDangerousMod(config, [
    'ios',
    async (config) => {
      const podfilePath = path.join(config.modRequest.platformProjectRoot, 'Podfile');

      if (fs.existsSync(podfilePath)) {
        let podfileContent = fs.readFileSync(podfilePath, 'utf8');

        // Remove any KSPlayer-related pod lines
        const linesToRemove = [
          /^\s*pod\s+'KSPlayer'.*$/gm,
          /^\s*pod\s+'DisplayCriteria'.*$/gm,
          /^\s*pod\s+'FFmpegKit'.*$/gm,
          /^\s*pod\s+'Libass'.*$/gm,
          /^\s*#\s*KSPlayer dependencies.*$/gm,
        ];

        let modified = false;
        for (const regex of linesToRemove) {
          if (regex.test(podfileContent)) {
            podfileContent = podfileContent.replace(regex, '');
            modified = true;
          }
        }

        // Clean up multiple empty lines
        podfileContent = podfileContent.replace(/\n{3,}/g, '\n\n');

        if (modified) {
          fs.writeFileSync(podfilePath, podfileContent);
          console.log('[withKSPlayer] Removed KSPlayer pod references from Podfile');
        }
      }

      return config;
    },
  ]);

  return config;
};

module.exports = withKSPlayerAndPodfile;
