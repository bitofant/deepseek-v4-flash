# DeepSeek V4 Flash
Purpose of this repo is to run a quantized version of DeekSeek V4 Flash 0731 using `llama.cpp` in docker.

## Machine
- headless machine running Ubuntu Server
- 96gb system memory - not all of it is available
- RTX 5090 with 32gb VRAM - all of it available
- docker and nvidia docker tools already installed

## CLAUDE.md Guidance
- broad architecture of this repo must be recorded in `CLAUDE.md`
- file must be kept in sync with the repo, apply edits to `CLAUDE.md` alongside changes to the repo
- use terse language

## Work Guidance
- skip code comments if the code is self-explanatory
- code comments must be extremely terse
- less code is better code
- create and persist small scripts instead of running medium to long bash commands ad-hoc
  - e.g. create `start.sh`, `stop.sh`, `rebuild.sh`, ...
- do not install anything globally
  - example: if a 1-time dependency is required to download a model from hugging-face, just write a script to create and start a throw-away container to get it done
- prefer additive patches over editing
  - example: instead of cloning a repo and applying changes in place, prefer cloning a repo in a subfolder, and "override" files from the subfolder via Dockerfile instructions at build time
