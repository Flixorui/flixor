/**
 * Expo config plugin to add KSPlayer native files to Xcode project
 */
const { withXcodeProject } = require('@expo/config-plugins');

const withKSPlayer = (config) => {
  return withXcodeProject(config, async (config) => {
    const xcodeProject = config.modResults;
    const projectName = config.modRequest.projectName || 'Flixor';

    // Files to add
    const sourceFiles = [
      { name: 'KSPlayerView.swift', path: `${projectName}/KSPlayerView.swift` },
      { name: 'KSPlayerViewManager.swift', path: `${projectName}/KSPlayerViewManager.swift` },
      { name: 'KSPlayerModule.swift', path: `${projectName}/KSPlayerModule.swift` },
      { name: 'KSPlayerManager.m', path: `${projectName}/KSPlayerManager.m` },
    ];

    // Get the main target
    const target = xcodeProject.getFirstTarget().uuid;

    // Find or create the group
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

    // Ensure bridging header is configured
    const buildSettings = xcodeProject.getBuildProperty('SWIFT_OBJC_BRIDGING_HEADER');
    if (!buildSettings) {
      console.log('[withKSPlayer] Setting bridging header');
      xcodeProject.addBuildProperty(
        'SWIFT_OBJC_BRIDGING_HEADER',
        `${projectName}/${projectName}-Bridging-Header.h`
      );
    }

    return config;
  });
};

module.exports = withKSPlayer;
