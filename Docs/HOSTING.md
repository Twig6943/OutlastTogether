# Running dedicated server on Linux

### Prerequisites

Warning: Run everything here within a tmux session if you'd like it to continue running once you log out of ssh

Ensure the following dependencies are installed on your host:

* podman
* tmux
* git
* text editor (e.g. vim)

### Podman Setup

On the machine that will host the dedicated server, execute the following commands individually:

```sh
mkdir -p $HOME/Games/outlast
git clone https://github.com/MeinaWithAI/OutlastTogether $HOME/Games/outlast
cd $HOME/Games/outlast
podman build -t outlast -f CI/Containerfile .
```

### Running the Container

Run the container with:

```sh
podman run -d \
  --name outlast \
  -p 7777:7777/tcp \
  -p 7777:7777/udp \
  -p 47778:47778/tcp \
  -p 47778:47778/udp \
  -v ./server_config.json:/build/server_config.json:ro \
  localhost/outlast
```

For logs:
```sh
podman logs -f outlast
```
