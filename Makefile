# This Makefile will be checked into the public repo, do not store sensitive secrets here
export GOERLI_RPC=https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161
export GOERLI_CHAINID=5
export GOERLI_FORK_BLOCK=8907950


test-fast:
	forge test --no-match-path test/DelegateToken.invariants.t.sol

test-fork:
	forge test -vvv --rpc-url ${GOERLI_RPC} --fork-block-number ${GOERLI_FORK_BLOCK} --match-path test/CreateOfferer.t.sol

deploy-simulate:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	forge script -vvv script/Deploy.s.sol --sig "deploy()" --rpc-url ${GOERLI_RPC} --private-key ${PK} --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}

verify:
	# To generate constructor argument, call $(cast abi-encode "constructor(address)" "0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE")
	# 0x00000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde
	# forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde 0xE98b24636746704f53625ed4300d84181819E512 src/PrincipalToken.sol:PrincipalToken --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch
	# forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000000000000000076a84fef008cdabe6409d2fe638b000000000000000000000000e98b24636746704f53625ed4300d84181819e5120000000000000000000000000000000000000000000000000000000000000080000000000000000000000000e5ee2b9d5320f2d1492e16567f36b578372b3d9f000000000000000000000000000000000000000000000000000000000000002668747470733a2f2f6d657461646174612e64656c65676174652e636173682f6c69717569642f0000000000000000000000000000000000000000000000000000 0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE src/LiquidDelegateV2.sol:LiquidDelegateV2 --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch
	# cast abi-encode "constructor(address,address)" 0x00000000000001ad428e4906aE43D8F9852d0dD6 0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE
	forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000000000000000001ad428e4906ae43d8f9852d0dd600000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde 0x74A2Dc882b41DD2dB3DB88857dDc0f28F257473f src/WrapOfferer.sol:WrapOfferer --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch

cloc:
	cloc src/CreateOfferer.sol src/DelegateToken.sol src/PrincipalToken.sol src/libraries/*.sol