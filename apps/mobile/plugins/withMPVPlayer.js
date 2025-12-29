/**
 * Expo config plugin to add MPV native player to Android
 *
 * This plugin:
 * 1. Copies Kotlin files from native/android/mpv/ to android/app/src/main/java/xyz/flixor/mobile/mpv/
 * 2. Adds dev.jdtech.mpv:libmpv Maven dependency to build.gradle
 * 3. Registers MpvPackage in MainApplication.kt
 *
 * This ensures EAS builds work correctly even when android/ is regenerated.
 */
const { withDangerousMod, withMainApplication } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Copy MPV native files to android project
 */
function copyMpvFiles(projectRoot) {
  const sourceDir = path.join(projectRoot, 'native', 'android', 'mpv');
  const destDir = path.join(projectRoot, 'android', 'app', 'src', 'main', 'java', 'xyz', 'flixor', 'mobile', 'mpv');

  // Create destination directory if it doesn't exist
  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
    console.log(`[withMPVPlayer] Created directory: ${destDir}`);
  }

  // Copy all Kotlin files from source to destination
  if (fs.existsSync(sourceDir)) {
    const files = fs.readdirSync(sourceDir);
    files.forEach(file => {
      const srcFile = path.join(sourceDir, file);
      const destFile = path.join(destDir, file);
      if (fs.statSync(srcFile).isFile() && file.endsWith('.kt')) {
        fs.copyFileSync(srcFile, destFile);
        console.log(`[withMPVPlayer] Copied ${file} to android project`);
      }
    });
  } else {
    console.warn(`[withMPVPlayer] WARNING: Source directory not found: ${sourceDir}`);
  }
}

/**
 * Copy libmpv AAR to android libs folder
 */
function copyMpvLibrary(projectRoot) {
  const sourceAar = path.join(projectRoot, 'native', 'android', 'libs', 'libmpv-release.aar');
  const destDir = path.join(projectRoot, 'android', 'app', 'libs');
  const destAar = path.join(destDir, 'libmpv-release.aar');

  // Create libs directory if it doesn't exist
  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
    console.log(`[withMPVPlayer] Created libs directory: ${destDir}`);
  }

  // Copy the AAR file
  if (fs.existsSync(sourceAar)) {
    fs.copyFileSync(sourceAar, destAar);
    console.log('[withMPVPlayer] Copied libmpv-release.aar to android/app/libs/');
  } else {
    console.warn(`[withMPVPlayer] WARNING: libmpv-release.aar not found at: ${sourceAar}`);
  }
}

/**
 * Add libmpv local AAR dependency to app build.gradle
 */
function addMpvDependency(projectRoot) {
  const buildGradlePath = path.join(projectRoot, 'android', 'app', 'build.gradle');

  if (!fs.existsSync(buildGradlePath)) {
    console.warn('[withMPVPlayer] WARNING: build.gradle not found');
    return;
  }

  let content = fs.readFileSync(buildGradlePath, 'utf8');

  // Check if dependency already exists
  if (content.includes('libmpv-release.aar')) {
    console.log('[withMPVPlayer] libmpv dependency already exists in build.gradle');
    return;
  }

  // Find the dependencies block and add libmpv as local AAR
  const dependenciesRegex = /dependencies\s*\{/;
  if (dependenciesRegex.test(content)) {
    content = content.replace(
      dependenciesRegex,
      `dependencies {
    // MPV Player library - local AAR from GitHub releases (no Glide conflict)
    implementation files("libs/libmpv-release.aar")
`
    );
    fs.writeFileSync(buildGradlePath, content);
    console.log('[withMPVPlayer] Added libmpv local AAR dependency to build.gradle');
  } else {
    console.warn('[withMPVPlayer] WARNING: Could not find dependencies block in build.gradle');
  }
}

/**
 * Add dependency resolution strategy to root build.gradle to resolve androidsvg conflict
 */
function addResolutionStrategy(projectRoot) {
  const rootBuildGradlePath = path.join(projectRoot, 'android', 'build.gradle');

  if (!fs.existsSync(rootBuildGradlePath)) {
    console.warn('[withMPVPlayer] WARNING: root build.gradle not found');
    return;
  }

  let content = fs.readFileSync(rootBuildGradlePath, 'utf8');

  // Check if resolution strategy already exists
  if (content.includes('androidsvg')) {
    console.log('[withMPVPlayer] Resolution strategy already exists in root build.gradle');
    return;
  }

  // Add subprojects configuration with resolution strategy
  const subprojectsConfig = `
subprojects {
    configurations.all {
        resolutionStrategy {
            // Exclude androidsvg-aar in favor of androidsvg to avoid duplicate classes
            exclude group: 'com.caverock', module: 'androidsvg-aar'
        }
    }
}
`;

  // Append to the end of the file
  content = content + subprojectsConfig;
  fs.writeFileSync(rootBuildGradlePath, content);
  console.log('[withMPVPlayer] Added resolution strategy to root build.gradle');
}

/**
 * Modify MainApplication.kt to include MpvPackage
 */
function withMpvMainApplication(config) {
  return withMainApplication(config, async (config) => {
    let contents = config.modResults.contents;

    // Add import for MpvPackage
    const mpvImport = 'import xyz.flixor.mobile.mpv.MpvPackage';
    if (!contents.includes(mpvImport)) {
      // Add import after the last import statement
      const lastImportIndex = contents.lastIndexOf('import ');
      const endOfLastImport = contents.indexOf('\n', lastImportIndex);
      contents = contents.slice(0, endOfLastImport + 1) + mpvImport + '\n' + contents.slice(endOfLastImport + 1);
      console.log('[withMPVPlayer] Added MpvPackage import to MainApplication.kt');
    }

    // Add MpvPackage to the packages list
    // Match the expression-body format: override fun getPackages(): List<ReactPackage> = PackageList(this).packages.apply {
    const packagesPatternExpression = /PackageList\(this\)\.packages\.apply\s*\{/;
    if (contents.match(packagesPatternExpression) && !contents.includes('MpvPackage()')) {
      contents = contents.replace(
        packagesPatternExpression,
        `PackageList(this).packages.apply {\n              add(MpvPackage())`
      );
      console.log('[withMPVPlayer] Added MpvPackage to packages list');
    }

    config.modResults.contents = contents;
    return config;
  });
}

/**
 * Main plugin function
 */
function withMPVPlayer(config) {
  // Copy native files and add dependencies during prebuild
  config = withDangerousMod(config, [
    'android',
    async (config) => {
      copyMpvFiles(config.modRequest.projectRoot);
      copyMpvLibrary(config.modRequest.projectRoot);
      addMpvDependency(config.modRequest.projectRoot);
      addResolutionStrategy(config.modRequest.projectRoot);
      return config;
    },
  ]);

  // Modify MainApplication to register the package
  config = withMpvMainApplication(config);

  return config;
}

module.exports = withMPVPlayer;
