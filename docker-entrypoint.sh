#!/bin/bash

useradd --shell /bin/bash -u $USER_ID -m build
chown build /home/build

su build -c "$@"
