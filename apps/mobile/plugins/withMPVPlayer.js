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
 * Add libmpv Maven dependency to app build.gradle
 */
function addMpvDependency(projectRoot) {
  const buildGradlePath = path.join(projectRoot, 'android', 'app', 'build.gradle');

  if (!fs.existsSync(buildGradlePath)) {
    console.warn('[withMPVPlayer] WARNING: build.gradle not found');
    return;
  }

  let content = fs.readFileSync(buildGradlePath, 'utf8');

  // Check if dependency already exists
  if (content.includes('dev.jdtech.mpv:libmpv')) {
    console.log('[withMPVPlayer] libmpv Maven dependency already exists in build.gradle');
    return;
  }

  // Find the dependencies block and add libmpv Maven dependency
  const dependenciesRegex = /dependencies\s*\{/;
  if (dependenciesRegex.test(content)) {
    content = content.replace(
      dependenciesRegex,
      `dependencies {
    // MPV Player library from Maven Central
    implementation 'dev.jdtech.mpv:libmpv:0.5.1'
`
    );
    fs.writeFileSync(buildGradlePath, content);
    console.log('[withMPVPlayer] Added libmpv Maven dependency to build.gradle');
  } else {
    console.warn('[withMPVPlayer] WARNING: Could not find dependencies block in build.gradle');
  }
}

/**
 * Add configurations exclusion to app build.gradle (like NuvioStreaming)
 */
function addConfigurationsExclusion(projectRoot) {
  const buildGradlePath = path.join(projectRoot, 'android', 'app', 'build.gradle');

  if (!fs.existsSync(buildGradlePath)) {
    console.warn('[withMPVPlayer] WARNING: app build.gradle not found');
    return;
  }

  let content = fs.readFileSync(buildGradlePath, 'utf8');

  // Check if exclusion already exists
  if (content.includes("exclude group: 'com.caverock'")) {
    console.log('[withMPVPlayer] androidsvg exclusion already exists in app build.gradle');
    return;
  }

  // Add configurations.all exclusion before dependencies block (like NuvioStreaming)
  const dependenciesRegex = /dependencies\s*\{/;
  if (dependenciesRegex.test(content)) {
    content = content.replace(
      dependenciesRegex,
      `configurations.all {
    exclude group: 'com.caverock', module: 'androidsvg'
}

dependencies {`
    );
    fs.writeFileSync(buildGradlePath, content);
    console.log('[withMPVPlayer] Added configurations exclusion to app build.gradle');
  }
}

/**
 * Update root build.gradle to exclude jdtech.mpv from JitPack
 */
function fixMavenRepositories(projectRoot) {
  const rootBuildGradlePath = path.join(projectRoot, 'android', 'build.gradle');

  if (!fs.existsSync(rootBuildGradlePath)) {
    console.warn('[withMPVPlayer] WARNING: root build.gradle not found');
    return;
  }

  let content = fs.readFileSync(rootBuildGradlePath, 'utf8');

  // Check if already fixed
  if (content.includes('jdtech')) {
    console.log('[withMPVPlayer] JitPack exclusion already configured');
    return;
  }

  // Replace JitPack repo with exclusion for jdtech
  content = content.replace(
    "maven { url 'https://www.jitpack.io' }",
    `maven {
      url 'https://www.jitpack.io'
      content {
        excludeGroup 'dev.jdtech.mpv'
      }
    }`
  );

  fs.writeFileSync(rootBuildGradlePath, content);
  console.log('[withMPVPlayer] Added JitPack exclusion for dev.jdtech.mpv');
}

/**
 * Add excludeAppGlideModule to gradle.properties to prevent Glide duplicate class conflict
 */
function addGlideExclusion(projectRoot) {
  const gradlePropertiesPath = path.join(projectRoot, 'android', 'gradle.properties');

  if (!fs.existsSync(gradlePropertiesPath)) {
    console.warn('[withMPVPlayer] WARNING: gradle.properties not found');
    return;
  }

  let content = fs.readFileSync(gradlePropertiesPath, 'utf8');

  if (content.includes('excludeAppGlideModule')) {
    console.log('[withMPVPlayer] excludeAppGlideModule already set in gradle.properties');
    return;
  }

  content += '\n# Exclude AppGlideModule from react-native-fast-image to prevent duplicate class\nexcludeAppGlideModule=true\n';
  fs.writeFileSync(gradlePropertiesPath, content);
  console.log('[withMPVPlayer] Added excludeAppGlideModule=true to gradle.properties');
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
      addMpvDependency(config.modRequest.projectRoot);
      addConfigurationsExclusion(config.modRequest.projectRoot);
      addGlideExclusion(config.modRequest.projectRoot);
      fixMavenRepositories(config.modRequest.projectRoot);
      return config;
    },
  ]);

  // Modify MainApplication to register the package
  config = withMpvMainApplication(config);

  return config;
}

module.exports = withMPVPlayer;
