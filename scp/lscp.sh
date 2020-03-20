#!/bin/bash

DEVICE_ID=$1
LOCAL_PATH=$2
TARGET_PATH=$3
LOCAL=$4
SERVER="lunixo.com"
AUTH_URL="https://${SERVER}/api/security/authentication"
COOKIE_FILE="lunixo-auth"
SSH_IDENTITY_FILE="ssh-identity"
DEVICE=""
LOCATION_ID=""
SSH_USER="root"
SSH_SERVER=""
SSH_PORT=22

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

    local error=$(curl -c ${COOKIE_FILE} -s \
          --header "Content-Type: application/json" \
          --request POST \
          --data "{\"email\":\"${email}\",\"password\":\"${password}\"}" \
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
    local deviceUrl="http://${SERVER}/api/devices/${DEVICE_ID}"
    local response=$(curl -b ${COOKIE_FILE} -s ${deviceUrl})
    parseError "${response}" "Failed to get device"
    DEVICE="${response}"
    
    echo "Connecting to device $(jq -r '.device.name' <<< ${DEVICE}) (ID: $(jq -r '.device.id' <<< ${DEVICE}), Location: $(jq -r '.location.name' <<< ${DEVICE}))"
    
    LOCATION_ID=$(jq -r '.location.id' <<< ${DEVICE})
    
    if [[ ${LOCAL} == 'local' || ${LOCAL} == 'l' ]]; then
        SSH_SERVER=$(echo $(jq -r '.device.deviceDetails.localIpV4Addresses' <<< ${DEVICE}) | awk -F, '{print $1}')
    else
        SSH_SERVER=$(jq -r '.device.deviceMaintenance.maintenanceServer' <<< ${DEVICE})
        SSH_PORT=$(jq -r '.device.deviceMaintenance.maintenancePort' <<< ${DEVICE})
    fi
    
    if [[ ${SSH_SERVER} == 'null' ]]; then
        echo "SSH Configuration does not exist for the device. SSH may be disabled or not supported by the device."
        exit 1
    fi
    
    echo "SSH Server: ${SSH_SERVER}:${SSH_PORT}"
}

function getPrivateKey() {
    local locationId=$(jq -r '.location.id' <<< ${DEVICE})
    local privateKeyUrl="http://${SERVER}/api/locations/${LOCATION_ID}/devices/${DEVICE_ID}/maintenance/privateKey/download"
    local response=$(curl -b ${COOKIE_FILE} -s ${privateKeyUrl})

    if  [[ "${response}" =~ "-----BEGIN RSA PRIVATE KEY-----"* ]] ; then
        if [[ -e "${SSH_IDENTITY_FILE}" ]]
         then 
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

if [[ "${DEVICE_ID}" = "" ]]; then
  echo 'No Device ID specified' >&2
  exit 1
fi

if ! [[ -x "$(command -v jq)" ]]; then
  echo 'Error: jq (JSON parser) is not installed. Install with: sudo apt install jq' >&2
  exit 1
fi

if ! getAuthentication; then 
    authenticate 
fi

getDevice
getPrivateKey

scp -r -P "${SSH_PORT}" -i "${SSH_IDENTITY_FILE}" "${LOCAL_PATH}" "${SSH_USER}@${SSH_SERVER}:${TARGET_PATH}"
rm "${SSH_IDENTITY_FILE}"
