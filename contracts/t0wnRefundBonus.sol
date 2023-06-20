// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Refund Bonus Escrow
 * @author Armand Daigle
 * @notice The dominant assurance logic of a crowdfunding campaign.
 */
contract t0wnRefundBonus is Ownable, ReentrancyGuard {
    uint256 public totalRefundBonus;
    uint256 public earlyPledgerRefundBonus;
    uint256 public campaignExpiryTime;
    uint32 public numEarlyPledgers;
    bool public isCampaignExpired = false;
    bool public isCampaignSuccessful = false;

    mapping(address => bool) earlyPledgers;
    mapping(address => bool) hasBeenRefunded;

    // Events mainly for transparency to other DAOs/pledgers.
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

    function setCampaignExpiryTime(uint256 id) external payable onlyOwner {
        // TODO: import Juicebox's JBFundingCycleStore contract and call the currentOf()
        // function which will return the start and duration times of the campaign funding
        // cycle. Store those in variables here to be used by campaignResultRelay().
        // ( ,,, uint256 start, uint256 duration, ,,,,) = JBFundingCycleStore.currentOf(id);
        // campaignExpiryTime = start + duration;
    }

    /**
     * @notice Project campaign "funding cycle" is created on JuiceboxDAO. Right after
     * the funding cycle ends, this function retrieves the early pledger addresses and campaign
     * results. Waiting on Juicebox devs to see if they have a retrievable public array or mapping.
     * Also, anyone call this function to instill more confidence in pledgers.
     * @dev We would have to establish a data source contract to hook into the Juicebox contract
     * architecture to have a payer pay() function call this contract and store pay params like
     * address, amount paid, and time.
     */
    function campaignResultRelay() public {
        require(
            block.timestamp >= campaignExpiryTime,
            "Campaign has not expired yet."
        );

        // TODO: Add locking pattern so that this function can only be called once.

        // TODO: get campaign success and early pledger addresses from Juicebox.
        // isCampaignExpired = isExpired;
        // isCampaignSuccessful = isSuccessful;
        // numEarlyPledgers = uint32(_earlyPledgers.length);
        // earlyPledgerRefundBonus = totalRefundBonus / numEarlyPledgers;

        // uint32 i = 0;
        // for (; i < _earlyPledgers.length; i++) {
        //     earlyPledgers[_earlyPledgers[i]] = true;
        // }
        //emit CampaignHasClosed(isCampaignExpired, isCampaignSuccessful);
    }

    function withdrawRefundBonus() external payable nonReentrant {
        require(
            isCampaignSuccessful == false && isCampaignExpired == true,
            "Campaign must have expired and failed to call this function."
        );
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
     * @dev This function is callable only after campaign expiry if goal is met.
     * @param _address Owner must call this function, but they can
     * input another address to receive funds if desired.
     */
    function t0wnWithdrawal(
        address payable _address
    ) external payable onlyOwner {
        require(
            isCampaignExpired == true && isCampaignSuccessful == true,
            "Campaign must be expired and successful to call this function."
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
