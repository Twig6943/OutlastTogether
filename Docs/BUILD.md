# Launcher

### Windows
```
choco install -y mingw python312
pip install nuitka --break-system-packages
python -m pip install --no-python-version-warning --disable-pip-version-check -r requirements.txt
python -m nuitka --mingw64 --enable-plugin=tk-inter --onefile OutlastTogether.py --output-filename=OutlastLauncher.exe
```

### Linux (cross-compile to windows) (It's not recommended to use the linux version of outlast)
```
./Cross_compile.sh
```

# Unreal script

### Prerequisites
- A copy of Outlast
- [UDK](https://drive.google.com/file/d/1IZed_3QAivpnU2uPlSClFVs-YOZrIpcd/view)

```
Compile.bat
```

Output should be at `%UDK%\UDKGame\Script\Multiplayer.u`

See [the ci](./.github/workflows) for more details
