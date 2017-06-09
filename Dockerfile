FROM ubuntu:14.04
RUN apt-get update && apt-get install -y \
    make \
    xz-utils \
    zip unzip \
 && rm -rf /var/lib/apt/lists/*

ADD docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash", "/home/build/src/toolchain/jdk/build/build-openjdk.sh"]
