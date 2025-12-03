// Commitlint configuration aligned with semantic-release
const config = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Align with release.config.mjs configuration
    'type-enum': [
      2,
      'always',
      [
        'feat', // Minor release
        'fix', // Patch release
        'perf', // Patch release
        'revert', // Patch release
        'docs', // No release (unless scope is README)
        'style', // No release
        'refactor', // No release
        'test', // No release
        'build', // No release
        'tool', // No release
        'ci', // No release
        'chore', // No release
      ],
    ],
    // Enforce lowercase subject like bash script
    'subject-case': [2, 'always', 'lower-case'],
    // Ensure subject is not empty
    'subject-empty': [2, 'never'],
    // Ensure type is not empty
    'type-empty': [2, 'never'],
  },
};

module.exports = config;
