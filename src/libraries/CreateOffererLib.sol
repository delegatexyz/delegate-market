// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {SpentItem, ReceivedItem} from "seaport/contracts/interfaces/ContractOffererInterface.sol";

library CreateOffererErrors {
    error NoBatchWrapping();
    error InvalidExpiryType();
}

library CreateOffererEnums {
    enum ExpiryType {
        none,
        absolute,
        relative
    }

    enum TargetToken {
        none,
        principal,
        delegate
    }

    enum Stage {
        none,
        generate,
        transfer,
        ratify
    }
}

library CreateOffererStructs {
    struct Stage {
        CreateOffererEnums.Stage flag;
    }

    struct Receivers {
        address principal;
        address delegate;
    }

    struct Parameters {
        address seaport;
        address seaportConduit;
        address principalToken;
        address delegateToken;
    }

    struct Context {
        bytes32 rights;
        uint256 signerSalt;
        uint256 expiryLength;
        CreateOffererEnums.ExpiryType expiryType;
        CreateOffererEnums.TargetToken targetToken;
        Receivers receivers;
    }

    struct Order {
        bytes32 rights;
        uint256 expiryLength;
        uint256 signerSalt;
        address tokenContract;
        CreateOffererEnums.ExpiryType expiryType;
        CreateOffererEnums.TargetToken targetToken;
    }

    struct ERC721Order {
        uint256 tokenId;
        Order info;
    }

    struct ERC20Order {
        uint256 amount;
        Order info;
    }

    struct ERC1155Order {
        uint256 amount;
        uint256 tokenId;
        Order info;
    }
}

library CreateOffererProcess {
    function receivers(CreateOffererEnums.TargetToken targetToken, address targetTokenReceiver, CreateOffererStructs.Receivers storage tokenReceivers)
        internal
        returns (CreateOffererStructs.Receivers memory processedReceivers)
    {
        if (targetToken == CreateOffererEnums.TargetToken.principal) {
            processedReceivers = CreateOffererStructs.Receivers({principal: targetTokenReceiver, delegate: tokenReceivers.delegate});
            tokenReceivers.principal = targetTokenReceiver;
        } else if (targetToken == CreateOffererEnums.TargetToken.delegate) {
            processedReceivers = CreateOffererStructs.Receivers({principal: tokenReceivers.principal, delegate: targetTokenReceiver});
            tokenReceivers.delegate = targetTokenReceiver;
        } else {
            revert("invalid targetToken");
        }
    }

    function expiry(CreateOffererEnums.ExpiryType expiryType, uint256 expiryLength) internal view returns (uint256) {
        if (expiryType == CreateOffererEnums.ExpiryType.relative) {
            return block.timestamp + expiryLength;
        } else if (expiryType == CreateOffererEnums.ExpiryType.absolute) {
            return expiryLength;
        } else {
            revert CreateOffererErrors.InvalidExpiryType();
        }
    }

    function order(
        address seaport,
        CreateOffererStructs.Stage storage stage,
        address caller,
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context
    ) internal view returns (CreateOffererStructs.Context memory decodedContext, SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        require(caller == seaport, "caller not seaport");
        require(stage.flag == CreateOffererEnums.Stage.generate, "locked");
        if (!(minimumReceived.length == 1 && maximumSpent.length == 1)) revert CreateOffererErrors.NoBatchWrapping();
        decodedContext = abi.decode(context, (CreateOffererStructs.Context));
        if (fulfiller == decodedContext.receivers.principal) {
            require(fulfiller != decodedContext.receivers.delegate, "symmetric receivers");
        } else if (fulfiller == decodedContext.receivers.delegate) {
            require(fulfiller != decodedContext.receivers.principal, "symmetric receivers");
        } else {
            revert("fulfiller not receiver");
        }
        offer = new SpentItem[](1);
        offer[0] = SpentItem({
            itemType: minimumReceived[0].itemType,
            token: minimumReceived[0].token,
            identifier: minimumReceived[0].identifier,
            amount: minimumReceived[0].amount
        });
        consideration = new ReceivedItem[](1);
        consideration[0] = ReceivedItem({
            itemType: maximumSpent[0].itemType,
            token: maximumSpent[0].token,
            identifier: maximumSpent[0].identifier,
            amount: maximumSpent[0].amount,
            recipient: payable(address(this))
        });
    }
}
