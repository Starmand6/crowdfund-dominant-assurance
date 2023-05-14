// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/escrow/RefundEscrow.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./t0wnToken.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Dominant Assurance Escrow Contract for the CityDAO-t0wn-Prospera Funding Campaign
 * @author Armand Daigle, Scott Auriat, and ...
 * @notice This is a newish way to crowdfund projects.
 * This contract has NOT been audited. Do not use in production.
 * @dev Heart hands to you!
 */
contract t0wnCampaign is Ownable, RefundEscrow, Pausable, ReentrancyGuard {
    /// Token Contract Instances
    IERC20 public immutable i_usdcToken;
    t0wnToken public immutable i_t0wnToken;

    /// Campaign State Variables
    uint256 public s_targetAmount;
    uint256 public s_refundBonus;
    // Need to add minimum pledge amount
    uint256 public s_campaignExpiryDate;
    uint256 public s_totalPledgedAmount;
    bool public s_isCampaignGoalMet = false;
    bool public s_refundsCompleted = false;

    /// Pledger State Variables
    address[] public s_pledgers;
    uint8 public immutable s_maxEarlyPledgers;
    mapping(address => uint256) public s_pledgerAmounts;
    mapping(address => bool) public s_isEarlyPledger;
    mapping(address => bool) public s_hasReceivedRefund;

    event CampaignCreated(address payable, uint256, uint256, uint256);
    event CampaignPledge(address, uint256);
    event CampaignGoalMet_RAWK(uint256);
    event CampaignFundsSent(address payable);
    event t0wnTokensClaimed(address payable, uint256);

    error CampaignIsStillActive();
    error CampaignHasExpired();
    error InsufficientFunds();
    error SuccessfulCampaign_NoRefunds();
    error RefundAlreadyWithdrawn();
    error YouAreNotAPledger();
    error CampaignGoalIsNotMet();

    constructor(
        ERC20 usdcAddress,
        t0wnToken _t0wnToken,
        address payable _beneficiaryWallet,
        uint256 _targetAmount,
        uint256 _refundBonus,
        uint256 _expiryDate,
        uint8 _maxEarlyPledgers
    ) payable RefundEscrow(_beneficiaryWallet) {
        require(
            _expiryDate > block.timestamp,
            "Campaign expiry date must be in the future."
        );
        require(
            _targetAmount > _refundBonus,
            "Campaign goal must be greater than bonus."
        );
        require(
            msg.value == _refundBonus,
            "Funds sent at contract creation must equal refund bonus amount."
        );
        i_usdcToken = IERC20(usdcAddress);
        i_t0wnToken = t0wnToken(_t0wnToken);
        s_targetAmount = _targetAmount;
        s_refundBonus = _refundBonus;
        s_campaignExpiryDate = block.timestamp + (_expiryDate * 1 days);
        s_maxEarlyPledgers = _maxEarlyPledgers;
    }

    receive() external payable {}

    fallback() external payable {}

    /// @notice This function will place funds into "escrow"
    function deposit(address payee) public payable override whenNotPaused {
        if (block.timestamp > s_campaignExpiryDate) {
            revert CampaignHasExpired();
        }
        // Calculates if caller will be an early pledger.
        if (
            s_isEarlyPledger[msg.sender] == false &&
            s_pledgers.length < s_maxEarlyPledgers
        ) {
            s_isEarlyPledger[msg.sender] = true;
        }
        //require (msg.value == amount, "Input does not match ether sent.");
        // if (i_usdcToken.balanceOf(msg.sender) < amount) {
        //     revert InsufficientFunds();
        // }
        // require(
        //     i_usdcToken.transferFrom(msg.sender, address(this), amount),
        //     "Failed to send pledge amount"
        // );

        // s_totalPledgedAmount = i_usdcToken.balanceOf(address(this));
        s_totalPledgedAmount += msg.value;
        s_pledgers.push(msg.sender);
        s_pledgerAmounts[msg.sender] += msg.value;
        emit CampaignPledge(msg.sender, msg.value);

        if (s_totalPledgedAmount >= s_targetAmount) {
            s_isCampaignGoalMet = true;
            emit CampaignGoalMet_RAWK(s_totalPledgedAmount);
        }
    }

    // Can be called by Chainlink Automation or owner if desired.
    function enableRefunds() public override whenNotPaused onlyOwner {
        if (block.timestamp < s_campaignExpiryDate) {
            revert CampaignIsStillActive();
        }
        if (s_isCampaignGoalMet == true) {
            revert SuccessfulCampaign_NoRefunds();
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
            revert YouAreNotAPledger();
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
                address payable pledger = payable(msg.sender);
                // If using ETH for payments:
                if (s_isEarlyPledger[msg.sender]) {
                    withdraw(payable(msg.sender));
                    (bool success, ) = msg.sender.call{
                        value: refundAmount_EarlyPledger
                    }("");
                    require(success, "Failed to send refund");
                }
                super.withdraw(pledger);

                // If using USDC for payments:
                // if (
                //     i_usdcToken.balanceOf(address(this)) <
                //     refundAmount_EarlyPledger
                // ) {
                //     revert InsufficientFunds();
                // }
                // if (s_isEarlyPledger[msg.sender]) {
                //     i_usdcToken.transfer(msg.sender, refundAmount_EarlyPledger);
                // } else {
                //     uint256 regRefundAmount = s_totalPledgedAmount /
                //         numPledgers;
                //     i_usdcToken.transfer(msg.sender, regRefundAmount);
                // }
            }
        }
    }

    function close() public override onlyOwner whenNotPaused {
        if (s_isCampaignGoalMet != true) {
            revert CampaignGoalIsNotMet();
        }
        if (block.timestamp < s_campaignExpiryDate) {
            revert CampaignIsStillActive();
        }
        super.close();
    }

    function beneficiaryWithdraw() public override onlyOwner whenNotPaused {
        // This would be a huge problem, but this is mainly a sanity check
        // and a jumping off point if things are extra wonky.
        if (address(this).balance < s_targetAmount) {
            revert InsufficientFunds();
        }

        // Some way to deal funds over s_targetAmount?

        super.beneficiaryWithdraw();
        emit CampaignFundsSent(beneficiary());

        // If using USDC for payments:
        // if (i_usdcToken.balanceOf(address(this)) < s_targetAmount) {
        //     revert InsufficientFunds();
        // }
        // require(
        //     i_usdcToken.transfer(receiver, s_targetAmount),
        //     "Funds transfer failed"
        // );
        // emit CampaignFundsSent(beneficiary());
    }

    // Might want to put this function in the t0wn Token contract instead
    function claimt0wnTokens() external nonReentrant whenNotPaused {
        if (block.timestamp < s_campaignExpiryDate) {
            revert CampaignIsStillActive();
        }
        if (s_isCampaignGoalMet == false) {
            revert CampaignGoalIsNotMet();
        }
        if (s_pledgerAmounts[msg.sender] == 0) {
            revert YouAreNotAPledger();
        }
        // Use pledger mapping to mint tokens 1-for-1 to pledged amount,
        // then transfer to caller.
        uint256 amount = s_pledgerAmounts[msg.sender];
        s_pledgerAmounts[msg.sender] = 0;
        if (s_pledgerAmounts[msg.sender] > 0) {
            i_t0wnToken.mint(msg.sender, amount);
        }
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
        uint256 percentOfGoal = (s_totalPledgedAmount / s_targetAmount) * 100;
        return (s_totalPledgedAmount, percentOfGoal, s_isCampaignGoalMet);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getPledgers() public view returns (address[] memory) {
        return (s_pledgers);
    }

    function getEarlyPledgers() public view returns (address[] memory) {
        address[] memory earlyPledgers;
        uint32 i = 0;
        for (; i < s_pledgers.length; i++) {
            if (s_isEarlyPledger[s_pledgers[i]]) {
                earlyPledgers[i] = s_pledgers[i];
            }
        }

        return (earlyPledgers);
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
