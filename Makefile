# This Makefile will be checked into the public repo, do not store sensitive secrets here
export GOERLI_RPC=https://eth-goerli.public.blastapi.io
export GOERLI_CHAINID=5


test-fast:
	forge test --no-match-path test/LiquidDelegateV2.invariants.t.sol

deploy-simulate:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	forge script -vvv script/DeployV2.s.sol --sig "deploy()" --rpc-url ${GOERLI_RPC} --private-key ${PK} --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY} --base-fee 130