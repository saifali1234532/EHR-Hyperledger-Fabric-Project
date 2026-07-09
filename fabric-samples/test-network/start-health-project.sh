#!/bin/bash
set -e

echo "🚀 Starting E-Health Blockchain Project inside Workspace..."

# Fix Docker socket permissions gracefully
sudo chmod 666 /var/run/docker.sock || true

# Dynamically target the fabric-samples inside your current project directory
PROJECT_DIR=$(pwd)
FABRIC_SAMPLE_DIR="$PROJECT_DIR/fabric-samples"
TEST_NETWORK_DIR="$FABRIC_SAMPLE_DIR/test-network"

if [ ! -d "$TEST_NETWORK_DIR" ]; then
    echo "❌ Error: Could not find fabric-samples/test-network in this directory."
    echo "   Are you sure you are running this from ~/my-new-project/EHR-Hyperledger-Fabric-Project ?"
    exit 1
fi

# Clean old artifacts and old containers
cd "$TEST_NETWORK_DIR"
./network.sh down 2>/dev/null || true
docker rm -f chaincode_health 2>/dev/null || true

# Start the Fabric test network
echo "📡 Starting Fabric network..."
DOCKER_BUILDKIT=0 ./network.sh up createChannel -c healthchannel -ca

# Establish reliable absolute environment base paths
export PATH="${FABRIC_SAMPLE_DIR}/bin":$PATH
export FABRIC_CFG_PATH="${FABRIC_SAMPLE_DIR}/config/"
export CORE_PEER_TLS_ENABLED=true

# Helper function to switch Peer context cleanly
set_peer_context() {
    local org=$1
    if [ "$org" == "org1" ]; then
        export CORE_PEER_LOCALMSPID="Org1MSP"
        export CORE_PEER_TLS_ROOTCERT_FILE="${TEST_NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
        export CORE_PEER_MSPCONFIGPATH="${TEST_NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
        export CORE_PEER_ADDRESS=localhost:7051
    elif [ "$org" == "org2" ]; then
        export CORE_PEER_LOCALMSPID="Org2MSP"
        export CORE_PEER_TLS_ROOTCERT_FILE="${TEST_NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
        export CORE_PEER_MSPCONFIGPATH="${TEST_NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
        export CORE_PEER_ADDRESS=localhost:9051
    fi
}

# Create CCAS connection package safely inside a subshell
echo "📦 Packaging Chaincode-as-a-Service package..."
(
    cd /tmp
    rm -rf ccas-pkg && mkdir ccas-pkg && cd ccas-pkg
    echo '{"address":"chaincode_health:9999","dial_timeout":"10s","tls_required":false}' > connection.json
    echo '{"type":"ccaas","label":"healthcontract_1.0"}' > metadata.json
    tar cfz code.tar.gz connection.json
    tar cfz "$PROJECT_DIR/healthcontract.tar.gz" metadata.json code.tar.gz
)

# Install on Org1
echo "📥 Installing chaincode on Org1..."
set_peer_context "org1"
peer lifecycle chaincode install "$PROJECT_DIR/healthcontract.tar.gz"

# Install on Org2
echo "📥 Installing chaincode on Org2..."
set_peer_context "org2"
peer lifecycle chaincode install "$PROJECT_DIR/healthcontract.tar.gz"

# Get Package ID reliably using Org1 context
set_peer_context "org1"
echo "🔍 Fetching Chaincode Package ID..."
CC_PACKAGE_ID=$(peer lifecycle chaincode queryinstalled --output json | jq -r '.installed_chaincodes[] | select(.label=="healthcontract_1.0") | .package_id')

if [ -z "$CC_PACKAGE_ID" ] || [ "$CC_PACKAGE_ID" == "null" ]; then
    echo "❌ Error: Failed to fetch Chaincode Package ID."
    exit 1
fi

echo "📌 Package ID: $CC_PACKAGE_ID"

# Start chaincode external server container
echo "🐳 Launching external Chaincode container..."
docker run -d \
  --name chaincode_health \
  --network fabric_test \
  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
  -e CHAINCODE_ID="$CC_PACKAGE_ID" \
  healthcontract:latest

echo "⏳ Giving the chaincode container a moment to initialize..."
sleep 3

# Approve for Org1
echo "👍 Approving chaincode definition for Org1..."
set_peer_context "org1"
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${TEST_NETWORK_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" \
  --channelID healthchannel --name healthcontract \
  --version 1.0 --package-id "$CC_PACKAGE_ID" --sequence 1

# Approve for Org2
echo "👍 Approving chaincode definition for Org2..."
set_peer_context "org2"
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${TEST_NETWORK_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" \
  --channelID healthchannel --name healthcontract \
  --version 1.0 --package-id "$CC_PACKAGE_ID" --sequence 1

# Commit the definition to the channel
echo "🚀 Committing chaincode to healthchannel..."
set_peer_context "org1"
peer lifecycle chaincode commit \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${TEST_NETWORK_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" \
  --channelID healthchannel --name healthcontract \
  --version 1.0 --sequence 1 \
  --peerAddresses localhost:7051 \
  --tlsRootCertFiles "${TEST_NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" \
  --peerAddresses localhost:9051 \
  --tlsRootCertFiles "${TEST_NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

echo ""
echo "✅ E-Health Blockchain Network Ready!"
echo "✅ Chaincode deployed and running via CCaaS!"
