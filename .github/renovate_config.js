const fs = require('fs');
const path = require('path');

function findRepoRoot() {
  const candidates = [
    process.env.GITHUB_WORKSPACE,
    path.join(__dirname, '..'),
    process.cwd(),
  ].filter(Boolean);

  for (const candidate of candidates) {
    try {
      if (
        fs
          .readdirSync(candidate)
          .some((file) => /^Dockerfile_v\d+\.\d+\.x$/.test(file))
      ) {
        return candidate;
      }
    } catch {
      // try next candidate
    }
  }

  throw new Error(
    'Unable to locate Dockerfile_v*.x while building Renovate packageRules'
  );
}

function kubectlPackageRules(repoRoot) {
  return fs
    .readdirSync(repoRoot)
    .filter((file) => /^Dockerfile_v\d+\.\d+\.x$/.test(file))
    .sort()
    .map((file) => {
      const [, major, minor] = file.match(/^Dockerfile_v(\d+)\.(\d+)\.x$/);
      return {
        description: `Limit kubectl updates in ${file} to ${major}.${minor}.x`,
        matchFileNames: [file],
        matchPackageNames: ['kubernetes/kubernetes'],
        // Semver range (not regex): works with github-releases tags like v1.25.16
        allowedVersions: `${major}.${minor}.x`,
      };
    });
}

function buildConfig() {
  const repoRoot = findRepoRoot();
  const packageRules = kubectlPackageRules(repoRoot);
  if (packageRules.length === 0) {
    throw new Error(
      `No Dockerfile_v*.x found under ${repoRoot}; refusing empty packageRules`
    );
  }

  return {
    platform: 'github',
    repositories: ['identw/kubectl'],
    packageRules,
  };
}

const config = buildConfig();

// Materialize a self-contained config for renovatebot/github-action: the action
// mounts only this file into /github-action/, so __dirname-based scans break.
if (require.main === module) {
  process.stdout.write(`module.exports = ${JSON.stringify(config, null, 2)};\n`);
}

module.exports = config;
