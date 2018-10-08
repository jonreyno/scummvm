#!/bin/bash
LIBS_ZIP_URL="https://www.scummvm.org/frs/build/scummvm-ios7-libs.zip"
LIBS_ZIP_FILENAME="scummvm-libs.zip"
GIT_REPO_URL="https://github.com/scummvm/scummvm.git"

# Clone the repository
#git clone "$GIT_REPO_URL"

# Compile create_project
(cd scummvm/devtools/create_project/xcode; xcodebuild)

# Create the workspace
mkdir build
cd build
curl -L "$LIBS_ZIP_URL" -o "$LIBS_ZIP_FILENAME"
unzip "$LIBS_ZIP_FILENAME"
rm "$LIBS_ZIP_FILENAME"

../scummvm/devtools/create_project/xcode/build/Release/create_project ../scummvm --xcode --enable-fluidsynth --disable-bink --disable-nasm --disable-opengl --disable-theora --disable-taskbar --disable-libcurl --disable-sdlnet
open scummvm.xcodeproj
