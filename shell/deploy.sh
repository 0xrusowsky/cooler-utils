# Load environment variables
source .env

# Deploy using script
forge script ./script/Deploy.s.sol:Deploy \
--sig "run()" $CHAIN \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
# --broadcast # uncomment to broadcast to the network