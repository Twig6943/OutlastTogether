How to run:
- Configure a server_config.json based on the example manually, or use the GUI to configure it (optional for the headless as the server will use sensible defaults should no server config exist. but I recommend checking if port 7777 isn't already used on your computer, then changing the port in the config if need be)
- Compile the mod, then open 2 instances of Outlast with the Multiplayer.u file loaded
- Run server.py directly or use the example docker compose
- if you use the docker compose remember to change the port made available in the compose to what you set in the config
- Load into the same checkpoint.

for the sake of additional documention, below are the same example server_config and docker compose files.

docker-compose.yml example
```
services:
  oltogether:
    build: 
      context: .
      dockerfile: dockerfile
    container_name: oltogether-server
    restart: unless-stopped
    volumes:
      - ./server_config.json:/app/server_config.json:ro # comment this and the above line out of you do not configure a server_config.json file. 
    ports:
      - "7777:7777"
    command: ["python3", "server.py", "--headless"]
```

server_config.json example
```
{
  "game_path": "<replace with the path to the binary of literally any officially purchased copy of Outlast 1>",
  "player_name": "Meina2",
  "host": "127.0.0.1",
  "port": "7777",
  "server_name": "Meina's Server"
}
```