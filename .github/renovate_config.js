const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');

function kubectlPackageRules() {
  return fs
    .readdirSync(repoRoot)
    .filter((file) => /^Dockerfile_v\d+\.\d+\.x$/.test(file))
    .map((file) => {
      const [, major, minor] = file.match(/^Dockerfile_v(\d+)\.(\d+)\.x$/);
      return {
        description: `Limit kubectl updates in ${file} to ${major}.${minor}.x`,
        matchFileNames: [file],
        matchPackageNames: ['kubernetes/kubernetes'],
        allowedVersions: `/^${major}\\.${minor}\\./`,
      };
    });
}

module.exports = {
  platform: 'github',
  repositories: ['identw/kubectl'],
  packageRules: kubectlPackageRules(),
};
