# Benchmarking Build Performance of OpenJDK

Documentation:
[Updating OpenJDK for Android Platform Builds](http://go/updating-opendjk-android)

### 1. Build openjdk17 locally

```
PATH/TO/openjdk/repo/toolchain/jdk/build/build-openjdk17-linux.sh -d destdir builddir
```

  The build writes `jdk.zip` and `jdk-debuginfo.zip` to `destdir`.

### 2. Updating the platform prebuilts from a local build

```
rm -rf PATH/TO/internal/repo/main/prebuilts/jdk/jdk17/linux-x86
mkdir PATH/TO/internal/repo/main/prebuilts/jdk/jdk17/linux-x86
unzip $DIST_DIR/jdk.zip -d PATH/TO/internal/repo/main/prebuilts/jdk/jdk17/linux-x86
```
  Use `jdk.zip` to populate `PATH/TO/internal/repo/main/prebuilts/jdk/jdk17/linux-x86`.

### 3. Disable hyperthreading on gLinux server

  Public Documents: [How to disable or enable hyper threading on my Linux server](https://www.golinuxhub.com/2018/05/how-to-disable-or-enable-hyper/)

  1. Check whether hyperthreading is enabled and show all of the logical CPUs
  and their HT pair relationships.

  ```
  grep -H . /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -n -t ',' -k 2 -u
  ```

  2. If hyperthreading is enabled, disable it. (assume there are n CPUs)

        Create a script to disable hyperthreading.

  ```
  $ cat > /tmp/disable_ht.sh <<EOF
  #!/bin/bash
  for i in {0..n/2}; do
    echo "Disabling logical HT core $i."
    echo 0 > /sys/devices/system/cpu/cpu${i}/online;
  done
  EOF
  sh /tmp/disable_ht.sh
  ```

### 4. Do the clean build of internal android

  ```
  rm -rf `PATH/TO/internal/repo/main/out`
  USE_RBE=false m -j32
  ```

### 5. Analyze `PATH/TO/internal/repo/main/out/build.trace.gz`

  ```
  gunzip PATH/TO/internal/repo/main/out/build.trace.gz
  ```

  Then you will get a json file called `build.trace`. Collect all file whose `rule_name`
  is `javac` and then the sum of their `user_time` is the total time.
  Two methods are provided below. Both work.

  #### 5.1 You can write a python script to analyze data

  #### 5.2 command line version

  ```
  grep rule_name.*javac PATH/TO/build.trace | cut -d '"' -f 13 | cut -c2- | sed 's/.$//' | awk '{sum += $1} END {print sum}'
  ```
