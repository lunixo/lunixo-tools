#!/bin/bash

# -l connects directly over LAN, it can be placed anywhere in the arguments.
LOCAL=0
ARGS=()
for arg in "$@"; do
    if [[ ${arg} == '-l' ]]; then
        LOCAL=1
    else
        ARGS+=("${arg}")
    fi
done

DEVICE_ID=${ARGS[0]}
SERVER="lunixo.com"
AUTH_URL="https://${SERVER}/api/security/authentication"
COOKIE_FILE="lunixo-auth"
SSH_IDENTITY_FILE="ssh-identity"
DEVICE=""
LOCATION_ID=""
SSH_USER="root"
SSH_SERVER=""
SSH_PORT=22
SSH_OPTIONS=()
IS_TUNNEL=0
TUNNEL_TOKEN=""
TUNNEL_URL=""

function getAuthentication() {
    local userName=$(curl -b ${COOKIE_FILE} -s ${AUTH_URL} | jq -r '.user.userName')
    if [[ ${userName} != '' ]]; then
        echo "Authenticated as ${userName}"
        return 0
    fi
    
    return 1
}

function authenticate() {
    read -p 'E-Mail: ' email
    read -sp 'Password: ' password
    printf '\n'
    read -p '2FA Token: ' twoFacAuthCode
    local error=$(curl -c ${COOKIE_FILE} -s \
          --header "Content-Type: application/json" \
          --request POST \
          --data "{\"email\":\"${email}\",\"password\":\"${password}\",\"twoFacAuthCode\":\"${twoFacAuthCode}\"}" \
          ${AUTH_URL} |  jq -r  '.message')

    printf '\n'
    if [[ ${error} != '' ]]; then
        echo ${error}
        exit 1
    else
        printf "Authenticated as ${email}.\n"
        printf "Authentication stored at $(realpath ${COOKIE_FILE})\n"
    fi
}

function getDevice() {
    local deviceUrl="https://${SERVER}/api/devices/${DEVICE_ID}"
    local response=$(curl -b ${COOKIE_FILE} -s ${deviceUrl})
    parseError "${response}" "Failed to get device"
    DEVICE="${response}"
    
    echo "Connecting to device $(jq -r '.device.name' <<< ${DEVICE}) (ID: $(jq -r '.device.id' <<< ${DEVICE}), Location: $(jq -r '.location.name' <<< ${DEVICE}))"
    
    LOCATION_ID=$(jq -r '.location.id' <<< ${DEVICE})
    if [[ ${LOCAL} == 1 ]]; then
        SSH_SERVER=$(echo $(jq -r '.device.deviceDetails.localIpV4Addresses' <<< ${DEVICE}) | awk -F, '{print $1}')
    else
        SSH_SERVER=$(jq -r '.device.deviceMaintenance.maintenanceServer' <<< ${DEVICE})
        SSH_PORT=$(jq -r '.device.deviceMaintenance.maintenancePort' <<< ${DEVICE})
    fi
        
    if [[ ${SSH_SERVER} == 'null' ]]; then
        echo "SSH Configuration does not exist for the device. SSH may be disabled or not supported by the device."
        exit 1
    fi
    
    # Devices using the WebSocket tunnel report the tunnel server instead of the SSH gateway.
    if [[ ${SSH_SERVER} == ws://* || ${SSH_SERVER} == wss://* ]]; then
        IS_TUNNEL=1
        echo "SSH Tunnel: ${SSH_SERVER}"
    else
        echo "SSH Server: ${SSH_SERVER}:${SSH_PORT}"
    fi
}

function getTunnelToken() {
    local tokenUrl="https://${SERVER}/api/locations/${LOCATION_ID}/devices/${DEVICE_ID}/maintenance/tunnel/clientToken"
    local response=$(curl -b ${COOKIE_FILE} -s --request POST ${tokenUrl})
    parseError "${response}" "Failed to get SSH tunnel token"

    # The token is valid for 5 minutes, it is only needed to open the connection.
    TUNNEL_TOKEN=$(jq -r '.token' <<< ${response})
    TUNNEL_URL=$(jq -r '.url' <<< ${response})
}

function checkWebsocat() {
    if [[ ${IS_TUNNEL} == 1 ]] && ! [[ -x "$(command -v websocat)" ]]; then
        echo 'Error: websocat is not installed, it is required for devices using the WebSocket tunnel. Download from: https://github.com/vi/websocat/releases' >&2
        exit 1
    fi
}

function setSshOptions() {
    SSH_OPTIONS=(-i "${SSH_IDENTITY_FILE}")
    if [[ ${IS_TUNNEL} == 1 ]]; then
        getTunnelToken
        # The device is reached through websocat, the host name only identifies its key in known_hosts.
        SSH_SERVER="lunixo-device-${DEVICE_ID}"
        SSH_OPTIONS+=(-o "ProxyCommand=websocat --binary -H='Authorization: Bearer ${TUNNEL_TOKEN}' '${TUNNEL_URL}'")
    else
        SSH_OPTIONS+=(-o "Port=${SSH_PORT}")
    fi
}

function getPrivateKey() {
    local locationId=$(jq -r '.location.id' <<< ${DEVICE})
    local privateKeyUrl="https://${SERVER}/api/locations/${LOCATION_ID}/devices/${DEVICE_ID}/maintenance/privateKey/download"
    local response=$(curl -b ${COOKIE_FILE} -s ${privateKeyUrl})

    if  [[ "${response}" =~ "-----BEGIN RSA PRIVATE KEY-----"* ]] ; then
        if [[ -e "${SSH_IDENTITY_FILE}" ]]; then 
         rm "${SSH_IDENTITY_FILE}"
        fi
        
        echo "${response}" >> "${SSH_IDENTITY_FILE}"
        chmod 600 "${SSH_IDENTITY_FILE}"
        return 0
    fi
    
    parseError "${response}" "Failed to get private key"
}

function parseError() {
    local error=$(jq -r '.message' <<< $1)
    
    if [[ ${error} != 'null' ]]; then
        echo "$2: ${error}"
        exit 1
    fi
}

if ! [[ -x "$(command -v jq)" ]]; then
  echo 'Error: jq (JSON parser) is not installed. Install with: sudo apt install jq' >&2
  exit 1
fi

if [[ "${DEVICE_ID}" = "" ]]; then
  echo 'No Device ID specified' >&2
  exit 1
fi

if ! getAuthentication; then 
    authenticate 
fi

getDevice
checkWebsocat
getPrivateKey
trap 'rm -f "${SSH_IDENTITY_FILE}"' EXIT
setSshOptions

ssh "${SSH_USER}@${SSH_SERVER}" "${SSH_OPTIONS[@]}" -o ServerAliveInterval=60 -L 9222:localhost:9222
rm -f "${SSH_IDENTITY_FILE}"
