#!/bin/sh
# Mirrors the client skills from the latest release tag of the repository
# that owns each: skills/spooler-go from spoolersh/spooler-go, skills/spooler-cli
# from spoolersh/spooler-cli. Run from the repository root. Prints one
# "<skill> <tag>" line per skill mirrored; a tag without the skill is skipped
# with a warning and the current copy stays.
#
# MIRROR_SOURCE is the base URL of the repositories, for a local run against
# checkouts (MIRROR_SOURCE=/path/to/parent).
set -eu

: "${MIRROR_SOURCE:=https://github.com/spoolersh}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# latest_tag prints the highest release tag of a repository, vMAJOR.MINOR.PATCH;
# a pre-release (v1.2.0-rc.1) is not a release, as go's @latest reads it.
latest_tag() {
	git ls-remote --tags --refs "$1" 'refs/tags/v*' \
		| sed 's|.*/||' \
		| grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
		| sort -V \
		| tail -n 1
}

# mirror copies skills/<name> from the latest tag of <repo>.
mirror() {
	repo=$1
	name=$2
	url="$MIRROR_SOURCE/$repo"
	tag=$(latest_tag "$url")
	if [ -z "$tag" ]; then
		echo "::warning::$repo has no release tag; keeping skills/$name" >&2
		return 0
	fi
	git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$tmp/$repo"
	if [ ! -f "$tmp/$repo/skills/$name/SKILL.md" ]; then
		echo "::warning::$repo $tag has no skills/$name; keeping skills/$name" >&2
		return 0
	fi
	rm -rf "skills/$name"
	cp -R "$tmp/$repo/skills/$name" "skills/$name"
	echo "$name $tag"
}

mirror spooler-go spooler-go
mirror spooler-cli spooler-cli
