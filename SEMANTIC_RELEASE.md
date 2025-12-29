# Semantic Release Setup

This document explains the automated release system for the noir_IEEE754 project.

## Overview

This project uses [semantic-release](https://github.com/semantic-release/semantic-release) to automate the versioning and release process. Releases are automatically created when changes are merged to the `main` branch, based on conventional commit messages.

## How It Works

### 1. Commit Message Format

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>
```

**Example commits:**
```
feat(float): add fused multiply-add operation
fix(div): correct division by zero handling
docs: update README with examples
test: add edge case tests for sqrt
chore: update dependencies
```

### 2. Version Bumping

The type of commit determines the version bump:

| Commit Type | Version Bump | Example |
|-------------|--------------|---------|
| `feat:` | Minor (0.x.0) | 0.4.0 → 0.5.0 |
| `fix:` | Patch (0.0.x) | 0.4.0 → 0.4.1 |
| `feat!:` or `BREAKING CHANGE:` | Major (x.0.0) | 0.4.0 → 1.0.0 |
| `docs:`, `test:`, `chore:`, etc. | No release | - |

### 3. Release Workflow

When a PR is merged to `main`:

1. **Commit Analysis**: Semantic-release analyzes all commits since the last release
2. **Version Calculation**: Determines the next version based on commit types
3. **Changelog Generation**: Creates/updates CHANGELOG.md with all changes
4. **Git Tag Creation**: Creates a new git tag (e.g., `v0.5.0`)
5. **GitHub Release**: Publishes a GitHub release with the changelog
6. **Commit Changelog**: Commits the updated CHANGELOG.md back to main

### 4. Configuration Files

- **`.releaserc.json`**: Main semantic-release configuration
- **`package.json`**: Node.js dependencies for semantic-release
- **`.github/workflows/release.yml`**: GitHub Actions workflow that runs semantic-release

### 5. Plugins Used

The release process uses the following semantic-release plugins:

1. **@semantic-release/commit-analyzer**: Analyzes commits to determine version bump
2. **@semantic-release/release-notes-generator**: Generates release notes from commits
3. **@semantic-release/changelog**: Updates CHANGELOG.md file
4. **@semantic-release/git**: Commits the changelog back to the repository
5. **@semantic-release/github**: Creates GitHub releases and tags

## Testing Locally

You can test the semantic-release configuration locally without triggering an actual release:

```bash
# Install dependencies
npm install

# Run semantic-release in dry-run mode
npx semantic-release --dry-run --no-ci
```

This will show what version would be released based on recent commits, without actually creating a release.

## Breaking Changes

To indicate a breaking change (triggers a major version bump):

**Option 1: Use `!` after the type**
```
feat!: change float32_add signature to require rounding mode
```

**Option 2: Add `BREAKING CHANGE:` in the commit footer**
```
feat: change float32_add signature

BREAKING CHANGE: The function now requires a rounding mode parameter.
All existing code must be updated to pass ROUNDING_MODE_NEAREST_EVEN.
```

## Manual Releases

Releases are triggered automatically on merge to `main`. However, you can also trigger a release manually:

1. Go to the [Actions tab](https://github.com/jeswr/noir_IEEE754/actions/workflows/release.yml)
2. Click "Run workflow"
3. Select the `main` branch
4. Click "Run workflow"

## Troubleshooting

### No release is created

**Possible reasons:**
- No commits with `feat:` or `fix:` types since last release
- Not on the `main` branch
- Commit message includes `[skip ci]`

### Release fails

**Check:**
1. GitHub Actions logs for error messages
2. That all semantic-release plugins are properly installed
3. That GITHUB_TOKEN has sufficient permissions

### Want to skip a release

Add `[skip ci]` to the commit message:

```
chore: update documentation [skip ci]
```

## Examples

### Feature Addition (Minor Bump)
```bash
git commit -m "feat(float): add IEEE 754-2019 fused multiply-add operation"
# Result: v0.4.0 → v0.5.0
```

### Bug Fix (Patch Bump)
```bash
git commit -m "fix(div): handle subnormal division edge case correctly"
# Result: v0.4.0 → v0.4.1
```

### Breaking Change (Major Bump)
```bash
git commit -m "feat!: change all function signatures to accept rounding mode"
# Result: v0.4.0 → v1.0.0
```

### No Release
```bash
git commit -m "docs: improve README examples"
# Result: No release created
```

## References

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Release Documentation](https://semantic-release.gitbook.io/)
- [Semantic Versioning](https://semver.org/)
