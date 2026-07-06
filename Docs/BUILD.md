# Launcher

### Windows
```
choco install -y python312
pip install --no-python-version-warning --disable-pip-version-check nuitka zstandard ordered-set -r requirements.txt
build_launcher.bat
```

### Linux (cross-compile to windows)

- It's not recommended to use the linux version of outlast for various reasons.

Provided as a containerfile for ci, though it'll compile fine if you just use the necessary commands from it on your host.

```
podman build -t outlast-launcher -f ci/Containerfile_launcher .
```

# UnrealScript

## Prerequisites
- A copy of Outlast
- [Outlast level editor](https://github.com/superboo07/Outlast-Level-Editor) (Don't forget to setup UDK like it tells you to)

### Windows

```
build_unrealscript.bat
```

### Linux

```
podman build -t outlast-unrealscript -f ci/Containerfile_unrealscript .
```

Output should be at `%UDK%\UDKGame\Script\Multiplayer.u`

See [the ci](./.github/workflows) for more details
