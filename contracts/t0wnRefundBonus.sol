// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Low Risk Refund Bonus Escrow
 * @author Armand Daigle
 * @notice Just a simple refund bonus intermediary
 */
contract t0wnRefundBonus is Ownable, ReentrancyGuard {
    bool public isCampaignExpired = false;
    bool public isCampaignSuccessful = false;
    uint32 public numEarlyPledgers;
    uint256 public totalRefundBonus;
    uint256 public earlyPledgerRefundBonus;

    mapping(address => bool) earlyPledgers;
    mapping(address => bool) hasBeenRefunded;

    event RefundBonusDeposited(address, uint256);
    event CampaignHasClosed(bool, bool);
    event CampaignRefundWithdrawal(address, uint256);
    event OwnerWithdrawal(address, uint256);

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice This should happen before campaign start to increase potential
     * pledger confidence.
     * @dev Can only be called by t0wn multisig.
     */
    function depositRefundBonus(
        uint256 refundBonusAmount
    ) external payable onlyOwner {
        require(
            msg.value == refundBonusAmount,
            "Funds sent to contract must equal refund bonus amount."
        );

        totalRefundBonus = refundBonusAmount;

        emit RefundBonusDeposited(msg.sender, refundBonusAmount);
    }

    // Ideal scenario is that JuiceboxDAO has an automated function that can call this
    // function. If so, their address would be the only address that can call this.
    // Otherwise, this would need to be periodically called by t0wn team.
    // Function gets list of early plegers, campaign success, and campaign expiry
    // from the JuiceboxDAO campaign.
    function campaignResultRelay(
        bool isExpired,
        bool isSuccessful,
        address payable[] memory _earlyPledgers
    ) public {
        require(
            isCampaignExpired == false && isCampaignSuccessful == false,
            "Campaign must either expire or be successful or both to call this function."
        );
        // If JuiceDAO calls this function, could make it so that it becomes locked
        // after one call, as a form of security. But that would mean if it is not called
        // correctly, then the refund bonus could forever be locked in this contract.
        isCampaignExpired = isExpired;
        isCampaignSuccessful = isSuccessful;
        numEarlyPledgers = uint32(_earlyPledgers.length);
        earlyPledgerRefundBonus = totalRefundBonus / numEarlyPledgers;

        uint32 i = 0;
        for (; i < _earlyPledgers.length; i++) {
            earlyPledgers[_earlyPledgers[i]] = true;
        }
        emit CampaignHasClosed(isCampaignExpired, isCampaignSuccessful);
    }

    function withdrawRefundBonus() external payable nonReentrant {
        require(isCampaignSuccessful == false, "Campaign succeeded.");
        require(isCampaignExpired == true, "Campaign is still active.");
        require(
            hasBeenRefunded[msg.sender] == true,
            "Already withdrawn refund."
        );
        require(earlyPledgers[msg.sender] == true, "Caller not pledger.");
        // Sanity Check
        require(
            address(this).balance > earlyPledgerRefundBonus,
            "Insufficient Funds"
        );

        hasBeenRefunded[msg.sender] = true;
        // Sending pledge refund.
        (bool sendSuccess, ) = msg.sender.call{value: earlyPledgerRefundBonus}(
            ""
        );
        require(sendSuccess, "Failed to send refund bonus.");

        emit CampaignRefundWithdrawal(msg.sender, earlyPledgerRefundBonus);
    }

    /**
     * @dev This function is callable onyl after campaign expiry if goal is met.
     * @param _address Owner must call this function, but they can
     * input another address to receive funds if desired.
     */
    function t0wnWithdrawal(
        address payable _address
    ) external payable onlyOwner {
        require(
            isCampaignExpired == false && isCampaignSuccessful == false,
            "Campaign must either expire or be successful or both to call this function."
        );

        (bool success, ) = _address.call{value: address(this).balance}("");
        require(success, "Failed to withdraw campaign funds.");

        emit OwnerWithdrawal(_address, address(this).balance);
    }

    /// Getters
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
