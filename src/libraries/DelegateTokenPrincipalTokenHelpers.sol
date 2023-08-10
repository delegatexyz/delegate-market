// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenStructs.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";

library DelegateTokenPrincipalTokenHelpers {
    /// @notice helper function for burning a principal token
    /// @dev must revert if burnAuthorized has already been set to BURN_AUTHORIZED flag
    function burn(address principalToken, Structs.Uint256 storage principalBurnAuthorization, uint256 delegateTokenId) internal {
        if (principalBurnAuthorization.flag == Constants.BURN_AUTHORIZED) revert Errors.BurnAuthorized();
        principalBurnAuthorization.flag = Constants.BURN_AUTHORIZED;
        PrincipalToken(principalToken).burn(msg.sender, delegateTokenId);
    }

    /// @notice helper function for minting a principal token
    /// @dev must revert if mintAuthorized has already been set to MINT_AUTHORIZED flag
    function mint(address principalToken, Structs.Uint256 storage principalMintAuthorization, address principalRecipient, uint256 delegateTokenId) internal {
        if (principalMintAuthorization.flag == Constants.MINT_AUTHORIZED) revert Errors.MintAuthorized();
        principalMintAuthorization.flag = Constants.MINT_AUTHORIZED;
        PrincipalToken(principalToken).mint(principalRecipient, delegateTokenId);
    }

    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function checkBurnAuthorized(address principalToken, Structs.Uint256 storage principalBurnAuthorization) internal {
        principalIsCaller(principalToken);
        if (principalBurnAuthorization.flag != Constants.BURN_AUTHORIZED) revert Errors.BurnNotAuthorized();
        principalBurnAuthorization.flag = Constants.BURN_NOT_AUTHORIZED;
    }

    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function checkMintAuthorized(address principalToken, Structs.Uint256 storage principalMintAuthorization) internal {
        principalIsCaller(principalToken);
        if (principalMintAuthorization.flag != Constants.MINT_AUTHORIZED) revert Errors.MintNotAuthorized();
        principalMintAuthorization.flag = Constants.MINT_NOT_AUTHORIZED;
    }

    /// @notice helper function to revert if caller is not Principal Token
    /// @dev must revert if msg.sender is not the principal token
    function principalIsCaller(address principalToken) internal view {
        if (msg.sender != principalToken) revert Errors.CallerNotPrincipalToken();
    }

    function notPrincipalOperator(address principalToken, uint256 delegateTokenId) internal view {
        if (!PrincipalToken(principalToken).isApprovedOrOwner(msg.sender, delegateTokenId)) {
            revert Errors.NotApproved(msg.sender, delegateTokenId);
        }
    }
}
