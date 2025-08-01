# Nordvpn Youtube Tester

A command-line tool that tests YouTube content accessibility across NordVPN servers by automatically connecting to different regions via nordvpn cli and checking video availability via yt-dlp.

## Features

- Detects your local country based public ip
- Automatically connects to NordVPN servers
- Tests YouTube video accessibility

## Why

YouTube has recently intensified its restrictions on ad blockers and VPN usage.  
Some VPN IPs are now blocked from viewing content entirely, or trigger constant CAPTCHA and login prompts.  
This script helps identify which NordVPN servers still work reliably for accessing specific YouTube videos.  
useful for users seeking uninterrupted viewing, testing geo-blocking, or preserving privacy.

## Requirements

- Bash (or compatible shell)
- `curl` (for web requests)
- `yt-dlp` (for checking if the ip is blocked)
- `nordvpn` CLI (official client)
- `grep` (for checking cli output)
- `tr` (for splitting cli output)
- `awk` (for text edits and printing)
- `sed` (for the saved working servers file)

Here you can copy all af them:
```bash
curl yt-dlp nordvpn grep tr awk sed
```

## Usage

```bash
./nordvpn-youtube-tester.sh
```

It will:

* Connect to a random server in your current country
* Test if the video is accessible from that region
* Retry until a working server is found
* Print the working server

## Notes

* Requires an active NordVPN subscription
* Run `nordvpn login` before using the script
* Make shure that `nordvpn c` also works

## Installation

Clone this repository:

```bash
git clone https://codeberg.org/marvin1099/nordvpn-youtube-tester.git
cd nordvpn-youtube-tester
chmod +x nordvpn-youtube-tester.sh
```