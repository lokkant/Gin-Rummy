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

### Server settings

When you host a game the **HOST A GAME** screen lets you set the port, the time each phase of a turn lasts
(the eye starts to redden, it is fully red, the glass cracks, the round is lost) and whether the horror mode
is on for both players, or pick a saved settings file (or drop a file onto the window). **ALL SETTINGS...**
on that screen, or **CREATE SERVER CONFIG** in the start menu, opens a form with every setting of the game;
SAVE writes it as a Lua file into the `server_configs` folder of the game's save directory, where the host
screen offers it. A dedicated server can use the same file: `love . --server --port 6789 --config my_server`
(a name from that folder, or a path to a file). The settings only count on the machine that runs the server;
the horror switch is sent to the players, the other effects stay each player's own.

The pause menu (ESC) has a sound button: all sounds, essential only (cards, heartbeat, glass, invalid
moves) or none. The card sway can't be switched off.

### Unsettling effects

The creepy extras are in the "Unsettling effects" block of `src/config.lua`; they work at any stage of the
game (for debugging) and each has its own switch. `horror_enabled = false` turns all of them off and
`horror_intensity` (0..1) scales them. `darkness_unlit` sets how dark the part without light is. In the game and the layoff scene the table is never evenly lit: the light follows the turn and both players' sides are lit when all cards are open (round result, end of the match, layoff), with the corners always dark. The menus have the plain cloth. Barely visible pairs of
eyes in the dark half (`watchers_*`), a faint hum that comes and goes and muffled opponent sounds (`ambient_*`, `room_reverb`), a very rare
muffled knock (`knock_*`),
a rare phantom card rustle (`phantom_*`), kings and queens that glance at the cursor (`face_gaze_*`),
restless cards and a breathing stock (`card_nervousness`, `opponent_restlessness`, `deck_breathing`),
the eye now and then opening a slit in the opponent's turn for a second (`eye_peek_*`), the opponent's
heartbeat (`opponent_heartbeat_*`) and turn timers that get shorter every few rounds for both players
(`timer_shrink_*`; the server decides, so the host's values count).

<img width="1919" height="1199" alt="изображение" src="https://github.com/user-attachments/assets/e26aeda8-8997-45b5-b1cd-420c5cba1570" />

## Game Recordings

<img width="800" height="241" alt="hover_cards" src="https://github.com/user-attachments/assets/c7539d6f-fa3b-48c2-af9a-68d4ba70d0e5" />

<img width="800" height="504" alt="" src="https://github.com/user-attachments/assets/e45d9b4a-3ac7-49d7-ae3e-0c80f20cbe7d" />

<img width="800" height="500" alt="end" src="https://github.com/user-attachments/assets/79b903ba-76f2-4033-a461-7de11d8f9e95" />

<img width="800" height="498" alt="" src="https://github.com/user-attachments/assets/8858a468-7ab3-4bf1-836d-128426c8c9c9" />
