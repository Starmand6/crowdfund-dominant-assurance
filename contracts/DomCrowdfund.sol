// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Dominant Assurance Escrow Platform for t0wn-Prospera Funding Campaign
 * @author Armand Daigle, Scott Auriat
 * @notice This is an alternative way to crowdfund projects
 * @dev Heart hands to you!
 */
contract DomCrowdfund is Ownable, Pausable, ReentrancyGuard {
    IERC20 private immutable usdcToken;

    struct Campaign {
        string title;
        address payable creator;
        uint256 targetAmount;
        uint256 refundAmount;
        uint256 campaignExpiryDate;
        uint32 maxEarlyPledgers;
        address[] pledgers;
        uint256 totalPledgedAmount;
        bool isGoalMet;
        bool hasCompletedRefunds;
    }

    Campaign[] public allCampaigns;

    /// It's a Campaign mapping party in here!
    mapping(uint32 => Campaign) public campaignsByID;
    mapping(address => Campaign) public creatorToCampaign;
    mapping(uint32 => mapping(address => uint256)) campaignPledgerAmounts;
    mapping(uint32 => mapping(address => bool)) campaignEarlyPledgers;
    mapping(uint32 => mapping(address => bool)) campaignPledgersRefunded;

    event CampaignCreated(address payable, uint256, uint256, uint256);
    event CampaignPledge(address, uint256, uint256);
    event CampaignGoalMet_RAWK(uint256);
    event CampaignFundsSent(address payable);

    error CampaignIDDoesNotExist();
    error CampaignIsStillActive();
    error CampaignHasExpired();
    error InsufficientFunds();
    error SuccessfulCampaign_NoRefunds();
    error YouAreNotTheCampaignCreator();
    error RefundAlreadyWithdrawn();
    error YouAreNotAPledger();
    error CampaignGoalIsNotMet();

    // Modifiers go here

    constructor(IERC20 usdcAddress) {
        usdcToken = IERC20(usdcAddress);
        //usdcOpToken = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
    }

    receive() external payable {}

    fallback() external payable {}

    function createCampaign(
        string calldata _title,
        uint256 _targetAmount,
        uint256 _refundAmount,
        uint256 _expiryDate,
        uint32 _maxEarlyPledgers
    ) external payable returns (uint32) {
        require(
            _expiryDate > block.timestamp,
            "Campaign expiry date must be in the future."
        );
        require(
            _targetAmount > _refundAmount,
            "Campaign goal must be greater than bonus."
        );

        Campaign memory campaign = Campaign(
            _title,
            payable(msg.sender),
            _targetAmount,
            _refundAmount,
            _expiryDate,
            _maxEarlyPledgers,
            new address[](0),
            0,
            false,
            false
        );

        // Populate struct, arrays, and mappings with new campaign
        allCampaigns.push(campaign);
        uint32 currentID = uint32(allCampaigns.length);
        campaignsByID[currentID] = campaign;
        creatorToCampaign[msg.sender] = campaign;

        emit CampaignCreated(
            payable(msg.sender),
            _targetAmount,
            _refundAmount,
            _expiryDate
        );
        return (currentID);
    }

    /// @notice This function will place funds into "escrow"
    function pledge(uint32 id, uint256 amount) external payable whenNotPaused {
        if (id > allCampaigns.length - 1) {
            revert CampaignIDDoesNotExist();
        }
        if (block.timestamp > campaignsByID[id].campaignExpiryDate) {
            revert CampaignHasExpired();
        }
        // Or can it be msg.value using USDC?
        if (usdcToken.balanceOf(msg.sender) < amount) {
            revert InsufficientFunds();
        }

        // Can insert a minimum pledge check here, if campaign has one.
        require(
            usdcToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient Allowance"
        );
        require(
            usdcToken.transferFrom(msg.sender, address(this), amount),
            "Failed to send pledge amount"
        );

        // Calculates if caller will be an early pledger.
        if (
            campaignEarlyPledgers[id][msg.sender] == false &&
            campaignsByID[id].pledgers.length <
            campaignsByID[id].maxEarlyPledgers
        ) {
            campaignEarlyPledgers[id][msg.sender] = true;
        }

        campaignPledgerAmounts[id][msg.sender] += amount;
        campaignsByID[id].totalPledgedAmount += amount;
        emit CampaignPledge(msg.sender, id, amount);

        if (
            campaignsByID[id].totalPledgedAmount >=
            campaignsByID[id].targetAmount
        ) {
            campaignsByID[id].isGoalMet = true;
            emit CampaignGoalMet_RAWK(campaignsByID[id].totalPledgedAmount);
        }
    }

    function withdrawRefund(
        uint32 id
    ) external payable whenNotPaused nonReentrant {
        if (campaignPledgersRefunded[id][msg.sender]) {
            revert RefundAlreadyWithdrawn();
        }
        if (campaignPledgerAmounts[id][msg.sender] == 0) {
            revert YouAreNotAPledger();
        }
        if (campaignsByID[id].isGoalMet == true) {
            revert SuccessfulCampaign_NoRefunds();
        }

        uint256 refundAmount = campaignPledgerAmounts[id][msg.sender];
        // Sanity Check
        if (address(this).balance < refundAmount) {
            revert InsufficientFunds();
        }
        campaignPledgerAmounts[id][msg.sender] = 0;
        campaignPledgersRefunded[id][msg.sender] = true;
        require(
            usdcToken.transferFrom(msg.sender, address(this), refundAmount),
            "Failed to withdraw funds."
        );

        if (campaignEarlyPledgers[id][msg.sender]) {
            uint256 earlyPledgerRefundBonus = earlyRefundCalc(id);
            if (address(this).balance < earlyPledgerRefundBonus) {
                revert InsufficientFunds();
            }
            require(
                usdcToken.transferFrom(
                    msg.sender,
                    address(this),
                    earlyPledgerRefundBonus
                ),
                "Failed to withdraw funds."
            );
        }
    }

    /**
     * @notice The goal is to get to here! Individual campaign creators are
     * responsible for pulling their funds.
     * @dev Note: No event is emitted when campaign expires. This function will
     * simply be able to be called after campaign expiry. A timer could be
     * implemented on the front end if desired.
     * @param receivingAddress Creators must call this function, but they can
     * input another address to receive funds if desired.
     */
    function creatorWithdrawal(
        uint32 id,
        address payable receivingAddress
    ) external payable whenNotPaused {
        //
        if (msg.sender != campaignsByID[id].creator) {
            revert YouAreNotTheCampaignCreator();
        }

        if (block.timestamp < campaignsByID[id].campaignExpiryDate) {
            revert CampaignIsStillActive();
        }
        if (campaignsByID[id].isGoalMet != true) {
            revert CampaignGoalIsNotMet();
        }

        // This is a fairly crucial check.
        if (
            usdcToken.balanceOf(address(this)) < campaignsByID[id].targetAmount
        ) {
            revert InsufficientFunds();
        }

        require(
            usdcToken.transfer(
                receivingAddress,
                campaignsByID[id].targetAmount
            ),
            "Funds transfer failed"
        );
        emit CampaignFundsSent(receivingAddress);
    }

    /// Getters
    // To avoid "Stack too deep" errors and for general sanity, campaign getters
    // were split into a few functions.
    function getCampaignInfo(
        uint32 id
    )
        public
        view
        returns (
            string memory,
            address payable,
            uint256,
            uint256,
            uint256,
            uint32
        )
    {
        return (
            campaignsByID[id].title,
            campaignsByID[id].creator,
            campaignsByID[id].targetAmount,
            campaignsByID[id].refundAmount,
            campaignsByID[id].campaignExpiryDate,
            campaignsByID[id].maxEarlyPledgers
        );
    }

    function getCampaignFundingStatus(
        uint32 id
    ) public view returns (uint256, uint256, bool) {
        uint256 percentOfGoal = (campaignsByID[id].totalPledgedAmount /
            campaignsByID[id].targetAmount) * 100;
        return (
            campaignsByID[id].totalPledgedAmount,
            percentOfGoal,
            campaignsByID[id].isGoalMet
        );
    }

    function getCampaignCount() public view returns (uint256) {
        return allCampaigns.length;
    }

    function getCampaignPledgers(
        uint32 id
    ) public view returns (address[] memory) {
        return (campaignsByID[id].pledgers);
    }

    function getCampaignEarlyPledgers(
        uint32 id
    ) public view returns (address[] memory) {
        address[] memory pledgers = campaignsByID[id].pledgers;
        address[] memory earlyPledgers;
        uint32 i = 0;
        for (; i < pledgers.length; i++) {
            if (campaignEarlyPledgers[id][pledgers[i]]) {
                earlyPledgers[i] = pledgers[i];
            }
        }
        return (earlyPledgers);
    }

    /// @return Should return "0, 0, [], false" if campaign is still active or
    /// the campaign goal was met.
    function getCampaignRefundStatus(
        uint32 id
    ) public view returns (uint256, uint256, address[] memory, bool) {
        address[] memory notRefunded;
        uint32 i = 0;
        address[] memory pledgers = campaignsByID[id].pledgers;
        uint256 amountNotRefunded;
        for (; i < pledgers.length; i++) {
            if (campaignPledgerAmounts[id][pledgers[i]] > 0) {
                notRefunded[i] = pledgers[i];
                amountNotRefunded += campaignPledgerAmounts[id][pledgers[i]];
            }
            if (campaignEarlyPledgers[id][pledgers[i]] == true) {
                uint256 earlyRefund = earlyRefundCalc(id);
                amountNotRefunded += earlyRefund;
            }
        }

        // amountRefunded is obtained in a less direct, backwards manner due
        // to the fact that the notRefunded array was already being populated,
        // so it was easy to get the amountNotRefunded.
        uint256 amountRefunded = campaignsByID[id].totalPledgedAmount -
            amountNotRefunded;
        uint256 percentRefunded = (amountRefunded /
            campaignsByID[id].totalPledgedAmount) * 100;

        return (
            amountRefunded,
            percentRefunded,
            notRefunded,
            campaignsByID[id].hasCompletedRefunds
        );
    }

    function earlyRefundCalc(uint32 id) public view returns (uint256) {
        uint16 numPledgers = uint16(campaignsByID[id].pledgers.length);
        uint256 earlyPledgerRefundBonus = campaignsByID[id].refundAmount /
            (
                (numPledgers > campaignsByID[id].maxEarlyPledgers)
                    ? campaignsByID[id].maxEarlyPledgers
                    : numPledgers
            );
        return earlyPledgerRefundBonus;
    }

    function getUSDCTokenAddress() public view returns (address) {
        return address(usdcToken);
    }
}
