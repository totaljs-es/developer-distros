# How to use Total.js Developer

## The addresses

Everything is reached by name. The names are answered by the computer itself, so they work from the moment it starts, with no setup.

| Address | What it is |
| --- | --- |
| `http://totaljs.developer` | **Total.js Center**: the state of the services, your projects and how to connect to the database |
| `http://code.totaljs.developer` | **Code**: the editor and the manager of your projects, in the browser |
| `http://flow.totaljs.developer` | **Flow**: programming with diagrams |
| `http://pgadmin.totaljs.developer` | **pgAdmin**: the database, in the browser |
| `http://<project>.totaljs.developer` | each project that you create in Code |

The first time the system starts, Code, Flow, PostgreSQL and pgAdmin download their images. Total.js Center shows the state of each service.

## Your projects

Your projects are in **`/www/www`**, one folder each. Create them in Code: each one gets its own address, `<project>.totaljs.developer`, and the
proxy serves it. The folders `/www/proxy`, `/www/code`, `/www/flow` and `/www/services` hold the configuration of the services themselves.

`/www` belongs to the group `totaljs-developer`. The first user that you create in the installer is in it, and in the group `docker`. To add another person:

```bash
sudo usermod -aG totaljs-developer,docker other-user
```

> The group `docker` can control Docker, which in practice is the same as being the administrator of the computer. Add only people that you trust.

## The database

PostgreSQL runs in a container that is **not published** outside the computer: only the containers of your projects reach it, through the Docker network
`proxy`, at the host `postgres` and the port `5432`, with the user `totaljs` and no password.

```text
postgres://totaljs@postgres:5432/postgres
```

pgAdmin is already connected to it. Its user is `admin@totaljs.developer`, and its password is made when the system is installed, different on each
computer. It is in `/www/services/postgres/.env`, which only the people of the group `totaljs-developer` can read.

To change the version of PostgreSQL or to publish its port, edit `/www/services/postgres/docker-compose.yml` and run
`sudo systemctl restart totaljs-postgres`.

## The services

Each service is a unit of systemd that starts at boot:

```bash
systemctl status totaljs-proxy totaljs-code totaljs-flow totaljs-postgres totaljs-center totaljs-dns
sudo systemctl restart totaljs-code
```

The Compose files are in `/www`. What you edit there stays: an update of the packages never overwrites the files that you changed.

## Node.js and Total.js

Node.js (LTS) is installed for the whole system, with `total4` and `total5` as global packages and `npm`:

```bash
node --version
npm ls -g --depth=0
```

## The desktop edition

| Keys | What it does |
| --- | --- |
| `Super + Enter` | Terminal |
| `Super + D` | Launcher of applications (type to search) |
| `Super + E` | Files |
| `Super + B` | Total.js Center in the browser |
| `Super + C` | Code in the browser |
| `Super + W` | Another wallpaper |
| `Super + Space` | The menu of the desktop (also with the right button on the wallpaper) |
| `Alt + Tab` | Change of window |
| `Super + F` | Maximize or restore the window |
| `Super + Q` or `Alt + F4` | Close the window |
| `Super + 1` ... `4` | Go to the desktop 1 ... 4 (with `Shift`, send the window there) |
| `Print` | Screenshot, saved in `~/Pictures` (with `Alt`, of an area) |

The panel on the top has the menu, Total.js Center, the terminal, the files and the browser, the list of windows, the tray (network and volume) and the clock.

The **widget** on the wallpaper is Conky. It starts with the session with the profile of the system (processor, memory, disk and network). To change it, use *Preferences → Desktop widget* in the menu of the desktop, or the command:

```bash
totaljs-conky system      # processor, memory and disk as rings, the network and the processes
totaljs-conky services    # Docker, the proxy, Code, Flow, PostgreSQL, Total.js Center and SSH
totaljs-conky compact     # a small card with the essentials, at the top right
totaljs-conky clock       # a large clock on the wallpaper, with no card
totaljs-conky hidden      # no widget
```

The one that you choose is kept for the next sessions. The profiles are in `~/.config/conky`: edit them or add your own, with the name `<profile>.conf`.

Wallpapers: there are twelve and a different one is chosen on each start. `totaljs-wallpaper pin` keeps the current one, `totaljs-wallpaper shuffle` goes back to
a random one and `totaljs-wallpaper signature` uses the one with Tux. The look of windows and applications is changed with *Preferences → Appearance*
(in the menu of the desktop).

The configuration of each person is in `~/.config` (`openbox`, `tint2`, `rofi`...). It is copied from `/etc/skel` when the person is created, and is yours to change.

## The terminal

Every terminal shows a summary of the system with the mark of Total.js. To turn it off for your user: `mkdir -p ~/.config/totalfetch && touch ~/.config/totalfetch/off`. The command `totalfetch` shows it at any time.

## Use it from another computer

The names `*.totaljs.developer` are answered by the computer itself, so another computer does not know them. On the other computer, add the address of this one to its file of hosts, for each name that you use:

```text
192.168.1.50  totaljs.developer code.totaljs.developer flow.totaljs.developer pgadmin.totaljs.developer my-project.totaljs.developer
```

The file is `/etc/hosts` on Linux and macOS, and `C:\Windows\System32\drivers\etc\hosts` on Windows. The proxy listens on the port 80 of the computer.

The firewall `ufw` is installed and **not enabled**. To enable it keeping SSH and the web open: `sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw enable`.

## Update

Total.js Developer is a set of packages. It is updated with the rest of the system:

```bash
sudo apt update && sudo apt upgrade
```
