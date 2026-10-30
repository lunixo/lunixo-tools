# lssh.sh

__Supported Platforms:__
* Ubuntu 24.04 +

__Prerequisites:__
* jq (JSON parser), install with: sudo apt install jq
* websocat, for devices using the WebSocket tunnel: download the binary for your platform from https://github.com/vi/websocat/releases, e.g. websocat.x86_64-unknown-linux-musl, and install it as /usr/local/bin/websocat (chmod +x)

The scripts detect devices using the WebSocket tunnel and connect through websocat automatically. Older devices are connected over the SSH Gateway.

__Connect over SSH Gateway:__

./lssh.sh \<Device ID\>

__Connect directly over LAN:__

./lssh.sh -l \<Device ID\>

# lscp.sh

__Copy folder to device__

./lscp.sh \<Device ID\> \<Local Source Path\> \<Remote Target Path\>

__Copy folder to device over LAN__

./lscp.sh -l \<Device ID\> \<Local Source Path\> \<Remote Target Path\>
