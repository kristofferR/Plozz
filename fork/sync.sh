#!/usr/bin/env bash
# Keep this fork's patches on top of upstream Plozz.
#
#   main                  exact mirror of upstream main (fast-forward only)
#   patched               upstream main plus the fork's commits (rebased, pushed with lease)
#   release/<n>           upstream's release tags, mirrored
#   patched-release/<n>   upstream's release/<n> plus the same commits (immutable tags)
#
# A patch is an ordinary commit on `patched`. The last commit there is generated:
# it enables the engine's object-audio traits by editing the engine pin in
# Package.swift and Package.resolved. Upstream rewrites those lines on every
# engine update, so that commit is recreated here instead of rebased.
#
# Usage: fork/sync.sh [--build] [--no-push]
#   --build    compile the tvOS app for the simulator before pushing
#   --no-push  rebuild locally only
# After a rebase conflict: resolve it, `git rebase --continue`, run this again.
set -euo pipefail

upstream_url="https://github.com/brandomoore/Plozz.git"
branch="patched"
traits="TrueHDObjectAudio DTSXObjectAudio"
traits_subject="Enable the engine's height-channel components"

fail() {
  echo "fork/sync.sh: $*" >&2
  exit 1
}

build=0
push=1
for arg in "$@"; do
  case "$arg" in
    --build) build=1 ;;
    --no-push) push=0 ;;
    *) fail "usage: fork/sync.sh [--build] [--no-push]" ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"
[[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes first"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$upstream_url"
git fetch --quiet upstream main 'refs/tags/release/*:refs/tags/release/*'

# Rebased commits keep the identity the fork's commits already carry, whoever
# runs this and whatever git identity that machine has.
GIT_COMMITTER_NAME="$(git log -1 --format=%an "$branch")"
GIT_COMMITTER_EMAIL="$(git log -1 --format=%ae "$branch")"
export GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Commits the generated trait commit on top of HEAD. Its dates come from HEAD,
# so an unchanged parent always yields the same commit.
enable_traits() {
  # Add the traits to every engine trait list (the remote pin and the local checkout).
  FORK_TRAITS="$traits" perl -0pi -e '
    s{traits: \[([^\]]*)\]}{
      my @have = $1 =~ /"([^"]+)"/g;
      for my $trait (split " ", $ENV{FORK_TRAITS}) {
        push @have, $trait unless grep { $_ eq $trait } @have;
      }
      "traits: [" . join(", ", map { qq("$_") } @have) . "]"
    }ge' Package.swift
  local trait
  for trait in $traits; do
    grep -q "traits: \[.*\"$trait\"" Package.swift || fail "could not enable $trait in Package.swift"
  done
  # Resolved in a throwaway scratch directory; the checkouts take about 2 GB.
  swift package --scratch-path "$scratch" resolve
  grep -q '"identity" : "libtruehd"' Package.resolved || fail "LibTrueHD was not resolved"

  local stamp
  stamp="$(git log -1 --format=%cI)"
  GIT_AUTHOR_NAME="$GIT_COMMITTER_NAME" GIT_AUTHOR_EMAIL="$GIT_COMMITTER_EMAIL" \
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
    git commit --quiet --all --message "$traits_subject"
}

has_traits_commit() {
  [[ "$(git log -1 --format=%s "$1")" == "$traits_subject" ]]
}

# 1. The branch: upstream main plus the fork's commits.
git switch --quiet "$branch"
if has_traits_commit HEAD && git merge-base --is-ancestor upstream/main HEAD; then
  echo "fork/sync.sh: $branch already contains upstream main"
else
  if has_traits_commit HEAD; then
    git reset --quiet --keep HEAD~1
  fi
  git rebase upstream/main
  enable_traits
  echo "fork/sync.sh: $branch is upstream $(git rev-parse --short upstream/main) plus $(git rev-list --count upstream/main..HEAD) commits"
fi

if (( build )); then
  # The deploy script's defaults (30 s settings lookup, 4 min build) only fit a
  # warm build on an idle machine.
  PLOZZ_BUILD_SETTINGS_TIMEOUT="${PLOZZ_BUILD_SETTINGS_TIMEOUT:-600}" \
    PLOZZ_BUILD_TIMEOUT="${PLOZZ_BUILD_TIMEOUT:-3600}" tools/deploy-tv.sh --sim-build
fi
if (( push )); then
  git push origin upstream/main:refs/heads/main
  git push --force-with-lease origin "$branch"
fi

# 2. The newest upstream release, with the same commits on top.
release="$(git tag --list 'release/*' --sort=-version:refname | head -n 1)"
if [[ -n "$release" ]] && ! git rev-parse --quiet --verify "refs/tags/patched-$release" >/dev/null \
  && [[ -z "$(git ls-remote --tags origin "refs/tags/patched-$release")" ]]; then
  patches="$(git rev-list --reverse "upstream/main..$branch~1")"
  git switch --quiet --detach "$release"
  # shellcheck disable=SC2086
  if [[ -n "$patches" ]] && ! git cherry-pick $patches >/dev/null; then
    git cherry-pick --abort
    git switch --quiet "$branch"
    fail "the fork's commits do not apply to $release; no patched-$release tag was made"
  fi
  enable_traits
  git tag "patched-$release"
  git switch --quiet "$branch"
  echo "fork/sync.sh: tagged patched-$release"
fi
if (( push )); then
  git push origin 'refs/tags/release/*:refs/tags/release/*' 'refs/tags/patched-release/*:refs/tags/patched-release/*'
fi
