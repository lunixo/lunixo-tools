# lssh.sh

__Supported Platforms:__
* Ubuntu 20.04

__Prerequisites:__
* jq (JSON parser), install with: sudo apt install jq

__Connect over SSH Gateway:__

./lssh.sh \<Device ID\>

__Connect directly over LAN:__

./lssh.sh \<Device ID\> l

# lscp.sh

__Copy folder to device__

./lscp.sh \<Device ID\> \<Local Source Path\> \<Remote Target Path\>

__Copy folder to device over LAN__

./lscp.sh \<Device ID\> \<Local Source Path\> \<Remote Target Path\> l
