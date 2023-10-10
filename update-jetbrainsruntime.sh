#!/bin/bash

#!/bin/bash
#
# Updates external/jetbrains/JetBrainsRuntime from github.com/JetBrains/JetBrainsRuntime
# Usage:
#   update-jetbrainsruntime.sh <tag>
#
# Scripts attempts to guess repo branch from tag value.
# Only suitable for clean updates, when source fully matches upstream
# and there are no Studio specific patches

set -eu

if [[ $# -eq 0 ]]; then
    echo "No tag provided."
    exit 1
fi

declare -r JBR_TAG="$1"
declare -r prog="${0##*/}"
declare -r top=$(realpath "$(dirname "$0")/../../..")


function github_release_notes(){
  tag=$1
  body=$(curl  --silent --show-error -L -H "X-GitHub-Api-Version: 2022-11-28"   https://api.github.com/repos/JetBrains/JetBrainsRuntime/releases/tags/$tag | grep '"body"' | sed 's/\\r\\n/\
/g')
  # Trim reponse after `Binaries for developers`
  release_notes="${body%Binaries for developers*}"
  # Remove `---` at the end
  release_notes="${release_notes%---*}"
  # Remoce leading text before `Release tag`
  release_notes="${release_notes#*Release tag}"
   # Remove `---` at the begining
  release_notes="${release_notes#*---}"

  # replace markdown links with text
  release_notes=$(echo "$release_notes" | sed -E 's/\(https...youtrack.*JBR-[0-9]*\)//g')
  echo -e "$release_notes"
}

if [[ "$JBR_TAG" =~ ^jbr-release-17\. ]]; then
  declare -r jbr_dir="$top/external/jetbrains/JetBrainsRuntime17"
  declare -r remote_branch="main17"
elif [[ "$JBR_TAG" =~ ^jbr-release-21\. ]]; then
  declare -r jbr_dir="$top/external/jetbrains/JetBrainsRuntime"
  declare -r remote_branch="main"
else
  echo "Wanted 'jbr-release-17.*' or 'jbr-release-21.*' tag but got '$1'"
  exit 2
fi

# Add git remote if nessesary
(
  cd $jbr_dir
  git remote -v | grep -w jb || (
    echo "Adding remote 'jb' in $jbr_dir pointing to https://github.com/JetBrains/JetBrainsRuntime"
    git remote add jb https://github.com/JetBrains/JetBrainsRuntime
  )
)

# Create merge CL
(
  cd $jbr_dir
  git fetch jb $JBR_TAG
  # workaround for b/120986763
  git push -o nokeycheck -o uploadvalidator~skip aosp +$JBR_TAG:jetbrains-master-mirror
  declare -r local_branch=merge_$(echo $JBR_TAG | tr -c -s '[:alnum:]' '_')
  echo "Using git branch '$local_branch'"
  git checkout -B $local_branch $JBR_TAG

  declare -r commit_id=$(git commit-tree -p aosp/$remote_branch -p $JBR_TAG^{} -m "Merge tag $JBR_TAG" $local_branch^{tree})
  echo "Created merge commit $commit_id"

  git checkout $commit_id
  echo "$JBR_TAG" > build.txt
  git add build.txt

  # Try append release notes from GitHub
  git commit --amend -m "$(git log --format=%B -n 1) $(github_release_notes $JBR_TAG)" || true

  # run presubmit hooks
  git commit --amend --no-edit

  git push -o nokeycheck -o uploadvalidator~skip aosp HEAD:refs/for/$remote_branch%wip
)