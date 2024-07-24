# Release Process

## Checklist

- [ ] bump version in configure.ac
- [ ] add entry to ChangeLog
- [ ] add entry to debian/changelog
- [ ] tag with dev tag, test in staging environment
- [ ] tag with release tag
- [ ] upload to GNU mirrors
- [ ] upload Debian packages to deb.taler.net

## Versioning

Releases use `$major.$minor.$patch` semantic versions.  The corresponding git
tag is `v$major.minor.$patch`.

Versions that are tested in staging environments typically use
`v$major.$minor.$patch-dev.$n` tags.

