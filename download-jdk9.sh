#!/bin/bash -e

# Downloads jdk9 sources from hg and converts them to git
# Puts hg-git converter in $PWD/hg-git/
# Puts hg jdk9 source in $PWD/hg/jdk9*
# Puts git sources in $PWD/git/jdk9*

# Use hg-git 0.8.0, the last tag that produces identical git SHAs to
# https://github.com/jetbrains/jdk8u
hg clone git://github.com/schacon/hg-git.git -u 0.8.0

jdk9=http://hg.openjdk.java.net/jdk9/dev

mkdir -p hg
hg clone --pull ${jdk9} hg/jdk9
for i in corba hotspot jaxp jaxws jdk langtools nashorn; do
  hg clone --pull ${jdk9}/$i hg/jdk9_$i
done

for hgdir in hg/*; do 
  gitdir=${hgdir/hg\//git\/}
  mkdir -p ${gitdir}
  git init --bare ${gitdir}/.git
  (
    cd $hgdir
    hg bookmark -r default upstream-master
    hg --config extensions.hggit=../../hg-git/hggit push ../../$gitdir
  )
done
