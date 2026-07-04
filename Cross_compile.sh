#!/bin/env sh

# This script generates cross compiles python with nuitka
# Based on https://github.com/Nuitka/Nuitka/issues/43

WINEPATH=python
WINEPREFIX=$HOME/.local/share/wineprefixes/nuitka
WINEDEBUG=trace-all,warn-all,err+all,fixme-all

echo "Make sure to have the following packages installed;
python
wine
winetricks
wine-mono
wine-gecko
wget
libwbclient
unzip
7zip (7z)
"

mkdir -p $WINEPREFIX
mkdir -p $WINEPREFIX/prefix/drive_c/users/$USER/AppData/Local/Nuitka/Nuitka/Cache/downloads/depends/x86_64

# Download choco & depends
wget -O $HOME/.cache/Chocolatey-for-wine.7z \
https://github.com/PietJankbal/Chocolatey-for-wine/releases/latest/download/Chocolatey-for-wine.7z # Version known to work fine: v0.5c.755
wget -O $HOME/.cache/depends22_x86.zip https://dependencywalker.com/depends22_x86.zip

# Extract
7z x $HOME/.cache/Chocolatey-for-wine.7z -o$HOME/.cache/Chocolatey-for-wine
unzip $HOME/.cache/depends22_x86.zip -d $WINEPREFIX/prefix/drive_c/users/$USER/AppData/Local/Nuitka/Nuitka/Cache/downloads/depends/x86_64

wine $HOME/.cache/Chocolatey-for-wine/ChoCinstaller_*.exe
wine choco install -y mingw python312

wine pip install nuitka --break-system-packages
wine python -m pip install --no-python-version-warning --disable-pip-version-check -r requirements.txt

# Compile
wine python -m nuitka --mingw64 --enable-plugin=tk-inter --onefile OutlastTogether.py --output-filename=OutlastLauncher.exe
