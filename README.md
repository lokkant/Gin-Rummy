# Gin-Rummy

The gin rummy game implemented using the LÖVE engine.

## Build

Use src/build.bat to build the project.

## Run

Run the program without arguments for the game. Two more options exist:

- `--server [--port N]` starts only the game server (port 6789 by default), without a window.
- `--connect host:port` skips the menus and joins that server at once.

## Connect

The start menu offers two ways to play:

- **Join a game**: enter the IP address and the port of the other player's (or a dedicated) server.
- **Host a game**: choose a port and the game starts a server on your computer and puts you in the room.
  The screen shows the address the other player has to enter. In the same network or a VPN use the first
  address; over the internet the (UDP) port has to be forwarded on your router.

For the game to work, users and the server must be able to reach each other.

## Settings

The tunable numbers are in `src/config.lua`: the turn timer (when the eye starts to turn red, when it is fully
red, when the screen cracks, when the round is lost by waiting and how many points the opponent gets for it)
and a few visual values. The values in the file are small, for debugging. To change them without rebuilding,
create a file `user_config.lua` in the game's save directory that returns a table with the keys to change,
for example `return {idle_warning_start = 20, idle_warning_full_delay = 25, idle_loss_delay = 5}` (the eye turns
red from 20 s, is fully red at 45 s, the glass cracks at 46 s and the round is lost at 51 s). The server enforces the timeout and sends
the numbers to the clients, so the settings of the player who hosts the game count.

<img width="1919" height="1199" alt="изображение" src="https://github.com/user-attachments/assets/e26aeda8-8997-45b5-b1cd-420c5cba1570" />

## Game Recordings

<img width="800" height="241" alt="hover_cards" src="https://github.com/user-attachments/assets/c7539d6f-fa3b-48c2-af9a-68d4ba70d0e5" />

<img width="800" height="504" alt="" src="https://github.com/user-attachments/assets/e45d9b4a-3ac7-49d7-ae3e-0c80f20cbe7d" />

<img width="800" height="500" alt="end" src="https://github.com/user-attachments/assets/79b903ba-76f2-4033-a461-7de11d8f9e95" />

<img width="800" height="498" alt="" src="https://github.com/user-attachments/assets/8858a468-7ab3-4bf1-836d-128426c8c9c9" />
