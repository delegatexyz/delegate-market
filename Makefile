# This Makefile will be checked into the public repo, do not store sensitive secrets here
export GOERLI_RPC=https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161
export GOERLI_CHAINID=5
export GOERLI_FORK_BLOCK=8907950
export MAINNET_RPC=https://eth.rpc.blxrbdn.com


test-fast:
	forge test --no-match-path test/DelegateToken.invariants.t.sol

test-fork:
	forge test -vvv --rpc-url ${GOERLI_RPC} --fork-block-number ${GOERLI_FORK_BLOCK} --match-path test/CreateOfferer.t.sol

deploy-simulate:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	# Can also try --resume in place of --broadcast
	forge script -vvv script/Deploy.s.sol --sig "deploy()" --rpc-url ${MAINNET_RPC} --private-key ${PK}

verify:
	# To generate constructor argument, call $(cast abi-encode "constructor(address)" "0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE")
	# 0x00000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde
	# forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde 0xE98b24636746704f53625ed4300d84181819E512 src/PrincipalToken.sol:PrincipalToken --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch
	# forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000000000000000076a84fef008cdabe6409d2fe638b000000000000000000000000e98b24636746704f53625ed4300d84181819e5120000000000000000000000000000000000000000000000000000000000000080000000000000000000000000e5ee2b9d5320f2d1492e16567f36b578372b3d9f000000000000000000000000000000000000000000000000000000000000002668747470733a2f2f6d657461646174612e64656c65676174652e636173682f6c69717569642f0000000000000000000000000000000000000000000000000000 0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE src/LiquidDelegateV2.sol:LiquidDelegateV2 --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch
	# cast abi-encode "constructor(address,address)" 0x00000000000001ad428e4906aE43D8F9852d0dD6 0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE
	# forge verify-contract --chain ${GOERLI_CHAINID} --constructor-args 0x00000000000000000000000000000000000001ad428e4906ae43d8f9852d0dd600000000000000000000000070ee311907291129a959b5bf6ae1d4a3ed869cde 0x74A2Dc882b41DD2dB3DB88857dDc0f28F257473f src/WrapOfferer.sol:WrapOfferer --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch
	# forge verify-contract 0xBa93c25cD7db01b5d8f4b74aE4e3F5e048144834 src/MarketMetadata.sol:MarketMetadata --chain 1  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch --constructor-args 0x000000000000000000000000bc22c4fbd596885a8c5cd490ba25515dadf1a91a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002f68747470733a2f2f6d657461646174612e64656c65676174652e78797a2f312f6d61726b6574706c6163652f76322f0000000000000000000000000000000000
	# forge verify-contract 0xC73dFD486BC155b8126a366F68A4fefe05CE1dCD src/PrincipalToken.sol:PrincipalToken --chain 1  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch --constructor-args 0x000000000000000000000000c2e257476822377dfb549f001b4cb00103345e66
	# forge verify-contract 0xC2E257476822377dFB549f001B4cb00103345e66 src/DelegateToken.sol:DelegateToken --chain 1  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch --constructor-args 0x00000000000000000000000000000000000000447e69651d841bd8d104bed493000000000000000000000000c73dfd486bc155b8126a366f68a4fefe05ce1dcd000000000000000000000000ba93c25cd7db01b5d8f4b74ae4e3f5e048144834
	forge verify-contract 0xf4c9581E2F2CE9d7E07a20b81e1B46aA95C8b6f4 src/CreateOfferer.sol:CreateOfferer --chain 1  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch --constructor-args 0x00000000000000000000000000000000000000adc04c56bf30ac9d3c0aaf14dc000000000000000000000000c2e257476822377dfb549f001b4cb00103345e66


cloc:
	cloc src/CreateOfferer.sol src/DelegateToken.sol src/PrincipalToken.sol src/libraries/*.sol