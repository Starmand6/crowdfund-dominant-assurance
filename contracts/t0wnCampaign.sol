// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/escrow/RefundEscrow.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Dominant Assurance Escrow Contract for the CityDAO-t0wn-Prospera Funding Campaign
 * @author Armand Daigle, Scott Auriat, and ...
 * @notice This is a newish way to crowdfund projects.
 * This contract has NOT been audited. Do not use in production.
 * @dev Heart hands to you!
 */
contract t0wnCampaign is Ownable, RefundEscrow, Pausable, ReentrancyGuard {
    /// Campaign State Variables
    uint256 public s_targetAmount;
    uint256 public s_refundBonus;
    uint256 public s_minPledgeAmount;
    uint256 public s_campaignExpiryDate;
    uint256 public s_totalPledgedAmount;
    bool public s_isCampaignGoalMet = false;
    bool public s_refundsCompleted = false;

    /// Pledger State Variables
    address[] public s_allowlist; // Maybe change to an address-bool mapping?
    address[] public s_pledgers;
    address[] public s_earlyPledgers;
    uint8 public s_maxEarlyPledgers;

    // Might need to delete d_pledgerAmounts mapping, since _deposits in Escrow.sol covers it.
    mapping(address => uint256) public s_pledgerAmounts;
    mapping(address => bool) public s_isEarlyPledger;
    mapping(address => bool) public s_hasReceivedRefund;

    // event CampaignHasBegun(address payable, uint256, uint256, uint256);
    event CampaignPledge(address, uint256);
    event CampaignGoalMet_RAWK(uint256);
    event CampaignFundsSent(address payable);
    event t0wnTokensClaimed(address payable, uint256);

    error CampaignHasExpired();
    error AddressNotOnAllowlist();
    error CampaignIsStillActive();
    error InsufficientFunds();
    error SuccessfulCampaign_FunctionIsClosed();
    error RefundAlreadyWithdrawn();
    error AddressIsNotAPledger();
    error CampaignGoalIsNotMet();

    constructor(
        address payable _beneficiaryWallet,
        uint256 _targetAmount,
        uint256 _refundBonus,
        uint256 _campaignLengthInDays,
        uint256 _minPledgeAmount,
        uint8 _maxEarlyPledgers,
        address[] memory _allowlist
    ) payable RefundEscrow(_beneficiaryWallet) {
        require(
            _targetAmount > _refundBonus,
            "Campaign goal must be greater than bonus."
        );
        require(
            msg.value == _refundBonus,
            "Eth sent to contract must equal refund bonus amount."
        );
        s_targetAmount = _targetAmount;
        s_refundBonus = _refundBonus;
        s_campaignExpiryDate =
            block.timestamp +
            (_campaignLengthInDays * 1 days);
        s_minPledgeAmount = _minPledgeAmount;
        s_maxEarlyPledgers = _maxEarlyPledgers;
        s_allowlist = _allowlist;
    }

    receive() external payable {}

    fallback() external payable {}

    /// @notice This function will place funds into "escrow"
    function deposit(address payee) public payable override whenNotPaused {
        if (block.timestamp > s_campaignExpiryDate) {
            revert CampaignHasExpired();
        }
        if (s_isCampaignGoalMet) {
            revert SuccessfulCampaign_FunctionIsClosed();
        }
        uint i = 0;
        for (; i < s_allowlist.length; i++) {
            if (msg.sender == s_allowlist[i]) break;
            if (i == s_allowlist.length - 1) revert AddressNotOnAllowlist();
        }
        if (msg.value < s_minPledgeAmount) {
            revert InsufficientFunds();
        }
        // Calculates if caller will be an early pledger.
        if (
            s_isEarlyPledger[msg.sender] == false &&
            s_pledgers.length < s_maxEarlyPledgers
        ) {
            s_isEarlyPledger[msg.sender] = true;
            s_earlyPledgers.push(msg.sender);
        }

        s_totalPledgedAmount += msg.value;
        s_pledgers.push(msg.sender);
        s_pledgerAmounts[msg.sender] += msg.value;
        emit CampaignPledge(msg.sender, msg.value);

        if (address(this).balance >= s_targetAmount) {
            s_isCampaignGoalMet = true;
            // uint256 overage = address(this).balance - s_targetAmount;
            // (bool success, ) = owner().call{value: overage}("");
            // require(success, "Failed to send funding overage.");
            // close();
            emit CampaignGoalMet_RAWK(s_totalPledgedAmount);
        }
    }

    // Can be called by Chainlink Automation or owner if desired.
    function enableRefunds() public override whenNotPaused onlyOwner {
        // Need to change to OR statement?
        if (block.timestamp < s_campaignExpiryDate) {
            revert CampaignIsStillActive();
        }
        if (s_isCampaignGoalMet == true) {
            revert SuccessfulCampaign_FunctionIsClosed();
        }
        super.enableRefunds();
    }

    function withdraw(
        address payable payee
    ) public override nonReentrant whenNotPaused {
        if (s_hasReceivedRefund[msg.sender]) {
            revert RefundAlreadyWithdrawn();
        }
        if (s_pledgerAmounts[msg.sender] == 0) {
            revert AddressIsNotAPledger();
        }

        uint16 i = 0;
        uint16 numPledgers = uint16(s_pledgers.length);
        for (; i < numPledgers; i++) {
            if (s_pledgers[i] == msg.sender) {
                uint256 refundAmount_EarlyPledger = s_refundBonus /
                    (
                        (numPledgers > s_maxEarlyPledgers)
                            ? s_maxEarlyPledgers
                            : numPledgers
                    );

                // Sanity check
                if (address(this).balance < refundAmount_EarlyPledger) {
                    revert InsufficientFunds();
                }
                s_hasReceivedRefund[msg.sender] = true;
                s_pledgerAmounts[msg.sender] = 0;
                address payable pledger = payable(msg.sender);
                // Early pledgers will receive two payments in one function call:
                // their early pledger bonus and the full refund of their pledge.
                if (s_isEarlyPledger[msg.sender]) {
                    (bool success, ) = msg.sender.call{
                        value: refundAmount_EarlyPledger
                    }("");
                    require(success, "Failed to send refund");
                }
                super.withdraw(pledger);
            }
        }
    }

    function close() public override whenNotPaused onlyOwner {
        if (s_isCampaignGoalMet != true) {
            revert CampaignGoalIsNotMet();
        }
        // Delete this require if we want to close campaign after goal is met.
        if (block.timestamp < s_campaignExpiryDate) {
            revert CampaignIsStillActive();
        }

        // If a pledge takes s_totalPledgeAmount above s_targetAmount, send all overage
        // to t0wn multisig / contract owner before close is called.
        uint256 overage = address(this).balance - s_targetAmount;
        if (overage > 0) {
            (bool success, ) = owner().call{value: overage}("");
            require(success, "Failed to send funding overage.");
        }

        emit CampaignGoalMet_RAWK(s_totalPledgedAmount);

        super.close();
    }

    /// @notice Anyone can call this function since the beneficiary address is set
    /// at contract creation.
    function beneficiaryWithdraw() public override whenNotPaused {
        /*
         * This would be a huge problem, but this is mainly a sanity check
         * and a jumping off point if things are extra wonky. This check
         * also acts as a lock, so that the function may only be successfully
         * called once.
         */
        if (address(this).balance < s_targetAmount) {
            revert InsufficientFunds();
        }
        super.beneficiaryWithdraw();
        emit CampaignFundsSent(beneficiary());
    }

    function pauseCampaign() public onlyOwner {
        _pause();
    }

    function unpauseCampaign() public onlyOwner {
        _unpause();
    }

    /// Getters
    function getCampaignInfo()
        public
        view
        returns (uint256, uint256, uint256, uint8)
    {
        return (
            s_targetAmount,
            s_refundBonus,
            s_campaignExpiryDate,
            s_maxEarlyPledgers
        );
    }

    function getCampaignFundingStatus()
        public
        view
        returns (uint256, uint256, bool)
    {
        uint256 percentOfGoal = ((100 * s_totalPledgedAmount) / s_targetAmount);
        return (s_totalPledgedAmount, percentOfGoal, s_isCampaignGoalMet);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getPledgers() public view returns (address[] memory) {
        return s_pledgers;
    }

    function getEarlyPledgers() public view returns (address[] memory) {
        // require(s_ledgers.length > 0, "No early pledgers yet.");
        return s_earlyPledgers;
    }

    function getAmountPledged(address addy) public view returns (uint256) {
        uint256 amountPledged = s_pledgerAmounts[addy];
        return amountPledged;
    }

    function getRefundStatus()
        public
        view
        returns (uint256, uint256, address[] memory, bool)
    {
        uint256 amountRefunded = s_totalPledgedAmount - address(this).balance;
        uint256 percentRefunded = (amountRefunded / s_totalPledgedAmount) * 100;

        address[] memory notRefunded;
        uint i = 0;
        for (; i < s_pledgers.length; i++) {
            if (s_hasReceivedRefund[s_pledgers[i]] == false) {
                notRefunded[i] = s_pledgers[i];
            }
        }
        return (
            amountRefunded,
            percentRefunded,
            notRefunded,
            s_refundsCompleted
        );
    }
}
