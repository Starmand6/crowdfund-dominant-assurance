const { deployments, ethers, network, deployer } = require("hardhat");
const { assert, expect } = require("chai");
const { utils } = require("ethers");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
    TARGET_AMOUNT,
    REFUND_BONUS,
    CAMPAIGN_LENGTH_IN_DAYS,
    MIN_PLEDGE_AMOUNT,
    MAX_EARLY_PLEDGERS,
} = require("../helper-hardhat-config");
//const usdcAddress = networkConfig[chainId]["usdcAddress"];
const chainId = network.config.chainId;
var allowlist = new Array();
var accounts,
    pledger,
    earlyPledger,
    rando,
    beneficiary,
    pledgerCalling,
    earlyPledgerCalling,
    randoCalling,
    beneficiaryCalling,
    //t0wnToken,
    t0wnCampaign;

if (chainId == 31337) {
    describe("t0wn Campaign Unit Tests", function () {
        describe("Campaign Constructor()", function () {
            beforeEach(async function () {
                accounts = await ethers.getSigners();
                pledger = accounts[1];
                earlyPledger = accounts[2];
                rando = accounts[3];
                beneficiary = accounts[4];
                allowlist = [pledger.address, earlyPledger.address];
            });
            it("reverts if refund bonus is greater than target amount", async function () {
                const smallTarget = utils.parseEther("1");
                const bigRefundBonus = utils.parseEther("10");
                t0wnCampaign = await ethers.getContractFactory("t0wnCampaign");
                await expect(
                    t0wnCampaign.deploy(
                        beneficiary.address,
                        smallTarget,
                        bigRefundBonus,
                        CAMPAIGN_LENGTH_IN_DAYS,
                        MIN_PLEDGE_AMOUNT,
                        MAX_EARLY_PLEDGERS,
                        allowlist,
                        { value: bigRefundBonus }
                    )
                ).to.be.revertedWith(
                    "Campaign goal must be greater than bonus."
                );
            });
            it("reverts if min Ether is not sent at contract creation", async function () {
                t0wnCampaign = await ethers.getContractFactory("t0wnCampaign");
                await expect(
                    t0wnCampaign.deploy(
                        beneficiary.address,
                        TARGET_AMOUNT,
                        REFUND_BONUS,
                        CAMPAIGN_LENGTH_IN_DAYS,
                        MIN_PLEDGE_AMOUNT,
                        MAX_EARLY_PLEDGERS,
                        allowlist,
                        { value: utils.parseEther("0.0000000001") }
                    )
                ).to.be.revertedWith(
                    "Eth sent to contract must equal refund bonus amount."
                );
            });
            describe("Campaign Contract Functions", function () {
                beforeEach(async function () {
                    await deployments.fixture(["deploy"]);
                    //t0wnToken = await ethers.getContract("t0wnToken");
                    t0wnCampaign = await ethers.getContract("t0wnCampaign");
                    pledgerCalling = t0wnCampaign.connect(pledger);
                    earlyPledgerCalling = t0wnCampaign.connect(earlyPledger);
                    randoCalling = t0wnCampaign.connect(rando);
                    beneficiaryCalling = t0wnCampaign.connect(beneficiary);
                });
                it("allows ownership transfer", async function () {
                    await expect(t0wnCampaign.transferOwnership(rando.address))
                        .to.not.be.reverted;
                    const owner = await t0wnCampaign.owner();
                    assert.equal(owner, rando.address);
                });
                describe("deposit()", function () {
                    it("reverts if pause() has been called", async function () {
                        await t0wnCampaign.pauseCampaign();
                        await expect(
                            randoCalling.deposit(rando.address, {
                                value: utils.parseEther("0.0001"),
                            })
                        ).to.be.revertedWith("Pausable: paused");
                    });
                    it("reverts if campaign has expired", async function () {
                        await time.increase(1_728_060); // 20 days and one minute
                        await expect(
                            pledgerCalling.deposit(pledger.address, {
                                value: utils.parseEther("0.0001"),
                            })
                        ).to.be.revertedWith("CampaignHasExpired");
                    });
                    it("reverts if sender is not on allowlist", async function () {
                        await expect(
                            randoCalling.deposit(rando.address, {
                                value: utils.parseEther("0.0001"),
                            })
                        ).to.be.revertedWith("AddressNotOnAllowlist");
                    });
                    it("reverts if Ether sent is below minimum pledge amount", async function () {
                        await expect(
                            pledgerCalling.deposit(pledger.address, {
                                value: utils.parseEther("0.000000000001"),
                            })
                        ).to.be.revertedWith("InsufficientFunds");
                    });
                    it("calculates early pledgers correctly", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            { value: utils.parseEther("0.0001") }
                        );
                        const earlyPledgers =
                            await t0wnCampaign.getEarlyPledgers();
                        await expect(earlyPledgers)
                            .to.be.an("array")
                            .that.includes(earlyPledger.address);
                    });
                    it("updates pledger and amount variables", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );

                        const pledgers = await t0wnCampaign.getPledgers();
                        await expect(pledgers)
                            .to.be.an("array")
                            .that.includes(earlyPledger.address);

                        const earlyPledgerBool =
                            await t0wnCampaign.s_isEarlyPledger(
                                earlyPledger.address
                            );
                        assert.equal(earlyPledgerBool, true);

                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        const totalCampaignAmount =
                            await t0wnCampaign.s_totalPledgedAmount();
                        assert(
                            totalCampaignAmount.toString(),
                            utils.parseEther("0.0002")
                        );
                        const pledgerAmount =
                            await t0wnCampaign.getAmountPledged(
                                pledger.address
                            );
                        assert(
                            pledgerAmount.toString(),
                            utils.parseEther("0.0002")
                        );
                    });
                    it("deposits correct amount of funds", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            { value: utils.parseEther("0.0001") }
                        );
                        const balance =
                            (await ethers.provider.getBalance(
                                t0wnCampaign.address
                            )) - REFUND_BONUS;
                        assert(balance.toString(), utils.parseEther("0.0001"));
                    });
                    it("emits event", async function () {
                        await expect(
                            pledgerCalling.deposit(pledger.address, {
                                value: utils.parseEther("0.0001"),
                            })
                        ).to.emit(t0wnCampaign, "CampaignPledge");
                    });
                    // close() is Ownable in RefundEscrow.sol :(.... need to discuss
                    it("emits campaign success event when goal is met", async function () {
                        await expect(
                            pledgerCalling.deposit(pledger.address, {
                                value: utils.parseEther("0.01"),
                            })
                        ).to.emit(t0wnCampaign, "CampaignGoalMet_RAWK");
                    });
                    it("closes campaign and emits RefundEscrow.sol's RefundsClosed() event", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.01"),
                        });
                        await time.increase(1_728_060);
                        await expect(t0wnCampaign.close()).to.emit(
                            t0wnCampaign,
                            "RefundsClosed"
                        );
                        const state = await t0wnCampaign.state();
                        assert.equal(state, 2); // RefundEscrow.sol _state Enum is 2 when State is Closed.
                        const [, , campaignGoalMet] =
                            await t0wnCampaign.getCampaignFundingStatus();
                        assert(campaignGoalMet, true);
                    });
                });
                describe("enableRefunds()", function () {
                    it("reverts if called by non-owner account", async function () {
                        // Choosing a pledger address just to show they can't call function either.
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            { value: utils.parseEther("0.0001") }
                        );
                        await expect(
                            earlyPledgerCalling.enableRefunds()
                        ).to.be.revertedWith(
                            "Ownable: caller is not the owner"
                        );
                    });
                    it("reverts if pause() has been called", async function () {
                        await t0wnCampaign.pauseCampaign();
                        await expect(
                            t0wnCampaign.enableRefunds()
                        ).to.be.revertedWith("Pausable: paused");
                    });
                    it("reverts if campaign is active", async function () {
                        await expect(
                            t0wnCampaign.enableRefunds()
                        ).to.be.revertedWith("CampaignIsStillActive");
                    });
                    it("reverts if campaign has met goal", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.01"),
                        });
                        // If campaign is still active, enableRefunds() will revert with the
                        // CampaignIsStillActive() error since it is coded first in function.
                        // To test for after the expiry date, we need to increase time:
                        await time.increase(1_728_060);
                        await expect(
                            t0wnCampaign.enableRefunds()
                        ).to.be.revertedWith("SuccessfulCampaign_NoRefunds");
                    });
                    it("changes _state and enables pledger withdrawals", async function () {
                        const beforetime = await time.latest();
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );
                        await time.increase(1_728_060); // 20 days and one minute
                        const currentTime = await time.latest();
                        await t0wnCampaign.enableRefunds();
                        const state = await t0wnCampaign.state();
                        assert.equal(state, 1);
                    });
                    it("emits an event from RefundEscrow.sol", async function () {
                        await time.increase(1_728_060);
                        await expect(t0wnCampaign.enableRefunds()).to.emit(
                            t0wnCampaign,
                            "RefundsEnabled"
                        );
                    });
                });
                // Non-passing tests
                describe.skip("withdraw()", function () {
                    it("NonReentrant test?", async function () {});
                    it("reverts when pause() has been called", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );
                        await time.increase(1_728_060);
                        await t0wnCampaign.pauseCampaign();
                        await expect(
                            earlyPledgerCalling.withdraw(earlyPledger.address)
                        ).to.be.revertedWith("Pausable: paused");
                    });
                    // withdraw is onlyOwner
                    it.skip("reverts if caller has already withdrawn their alloted refund", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        await time.increase(1_728_060);
                        await t0wnCampaign.enableRefunds();
                        await pledgerCalling.withdraw(pledger.address);
                        const refundBool =
                            await t0wnCampaign.s_hasReceivedRefund(
                                pledger.address
                            );
                        console.log(refundBool);
                        await expect(
                            pledgerCalling.withdraw(pledger.address)
                        ).to.be.revertedWith("RefundAlreadyWithdrawn");
                    });
                    it("reverts if caller is not pledger", async function () {
                        await time.increase(1_728_060);
                        await t0wnCampaign.enableRefunds();
                        await expect(
                            randoCalling.withdraw(rando.address)
                        ).to.be.revertedWith("AddressIsNotAPledger");
                    });
                    // withdraw is onlyOwner
                    it.skip("lets pledger withdraw funds if all requirements met", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        await time.increase(1_728_060);
                        await t0wnCampaign.enableRefunds();
                        await expect(pledgerCalling.withdraw(pledger.address))
                            .to.not.be.reverted;
                    });
                    // withdraw is onlyOwner
                    it("calculates early refund amounts correctly", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );
                        // pledger is actually an early pledger here.
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        await time.increase(1_728_060);
                        const earlyRefundBonus =
                            await (t0wnCampaign.s_refundBonus() /
                                t0wnCampaign.getEarlyPledgers());
                        const baseWithdrawalAmount =
                            await t0wnCampaign.getAmountPledged(
                                earlyPledger.address
                            );
                        const refundAmount =
                            earlyRefundBonus + baseWithdrawalAmount;
                        await expect(
                            await earlyPledgerCalling.withdraw(
                                earlyPledger.address
                            )
                        ).to.changeEtherBalance(
                            earlyPledger.address,
                            refundAmount
                        );
                    });
                    // withdraw is onlyOwner
                    it("emits Withdrawn event from Escrow.sol", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );
                        await time.increase(1_728_060);
                        await t0wnCampaign.enableRefunds();
                        await expect(
                            earlyPledgerCalling.withdraw(earlyPledger.address)
                        )
                            .to.emit(t0wnCampaign, "Withdrawn")
                            .withArgs(
                                earlyPledger.address,
                                utils.parseEther("0.001")
                            );
                    });
                });
                describe.skip("close()", function () {
                    it("reverts when pause() has been called", async function () {
                        // Need a test for when deposit auto calls close?
                        await t0wnCampaign.pauseCampaign();
                        await expect(t0wnCampaign.close()).to.be.revertedWith(
                            "Pausable: paused"
                        );
                    });
                    it("reverts if campaign goal has not been met", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        await expect(t0wnCampaign.close()).to.be.revertedWith(
                            "CampaignGoalIsNotMet"
                        );
                    });
                    it("reverts if campaign is still active", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.0001"),
                        });
                        await expect(
                            t0wnCampaign.enableRefunds()
                        ).to.be.revertedWith("CampaignIsStillActive");
                    });
                    it("changes _state and enables beneficiary withdrawal", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.01"),
                        });
                        await time.increase(1_728_060);
                        await t0wnCampaign.close();
                        const state = await t0wnCampaign.state();
                        assert.equal(state, 2);
                    });
                    it("emits an event from RefundEscrow.sol", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        await time.increase(1_728_060);
                        await expect(t0wnCampaign.close()).to.emit(
                            t0wnCampaign,
                            "RefundsClosed"
                        );
                    });
                });
                describe("beneficiaryWithdraw()", function () {
                    // Pausing of this function is tested in Modifiers section below.
                    it("transfer correct amount to beneficiary", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.01"),
                        });
                        await t0wnCampaign.close();
                        await expect(
                            await beneficiaryCalling.beneficiaryWithdraw()
                        ).to.changeEtherBalance(
                            beneficiary.address,
                            TARGET_AMOUNT
                        );
                    });
                    // Time
                    it("emits sent event", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        await expect(beneficiaryCalling.beneficiaryWithdraw())
                            .to.emit(t0wnCampaign, "CampaignFundsSent")
                            .withArgs(beneficiary);
                    });
                    // Time
                    it("reverts if contract does not have sufficient funds", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        await beneficiaryCalling.beneficiaryWithdraw();
                        await expect(
                            beneficiaryCalling.beneficiaryWithdraw()
                        ).to.be.revertedWith("InsufficientFunds");
                    });
                });
                describe.skip("Modifiers", function () {
                    it("allows ownership transfer", async function () {
                        await expect(
                            t0wnCampaign.transferOwnership(rando.address)
                        ).to.not.be.reverted;
                        const owner = await t0wnCampaign.owner();
                        assert.equal(owner, rando.address);
                    });
                    it("Pausable functions can be paused and unpaused", async function () {
                        await t0wnCampaign.pauseCampaign();
                        await expect(
                            beneficiaryCalling.beneficiaryWithdraw()
                        ).to.be.revertedWith("Pausable: paused");
                        await t0wnCampaign.unpauseCampaign();
                        // If function is not paused, and no one has pledged,
                        // execution will proceed to the InsufficientFunds error.
                        await expect(
                            beneficiaryCalling.beneficiaryWithdraw()
                        ).to.be.revertedWith("InsufficientFunds");
                    });
                    it("ReentrancyGuard tests", async function () {});
                });
                describe("Getters", function () {
                    it("getCampaignInfo() returns correct date", async function () {
                        const [, , expiryDate] =
                            await t0wnCampaign.getCampaignInfo();
                        const campaignEndDate = (
                            (await time.latest()) +
                            CAMPAIGN_LENGTH_IN_DAYS * 24 * 60 * 60
                        ).toString();
                        const currentTimestamp = (
                            await ethers.provider.getBlock("latest")
                        ).timestamp;
                        assert.equal(
                            expiryDate.toString(),
                            campaignEndDate.toString()
                        );
                    });
                    it("getCampaignFundingStatus() returns % goal and goal met bool", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.00054"),
                            }
                        );
                        const actualPercentGoal =
                            (utils.parseEther("0.00054") / TARGET_AMOUNT) * 100;
                        const [, percentGoal, goalMetBool] =
                            await t0wnCampaign.getCampaignInfo();
                        assert.equal(percentGoal.toString(), actualPercentGoal);
                        assert.equal(goalMetBool, false);
                    });
                    it("getBalance() returns correct contract balance", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        const balance = await t0wnCampaign.getBalance();
                        assert.equal(balance.toString(), "0.001");
                    });
                    it("getPledgers() returns an array with pledgers", async function () {
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        await expect(t0wnCampaign.getPledgers())
                            .to.be.an("array")
                            .that.includes(pledger.address);
                    });
                    it("getEarlyPledgers() returns an array with early pledgers", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.0001"),
                            }
                        );
                        await expect(t0wnCampaign.getPledgers())
                            .to.be.an("array")
                            .that.includes(earlyPledger.address);
                    });
                    it("getAmountPledged() returns correct amount pledged for address", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.004"),
                            }
                        );
                        const pledged = await expect(
                            t0wnCampaign.getAmountPledged(earlyPledger.address)
                        );
                        assert.equal(pledged.toString(), "0.004");
                    });
                    // Time
                    it("getRefundStatus()", async function () {
                        await earlyPledgerCalling.deposit(
                            earlyPledger.address,
                            {
                                value: utils.parseEther("0.004"),
                            }
                        );
                        await pledgerCalling.deposit(pledger.address, {
                            value: utils.parseEther("0.001"),
                        });
                        await time.increase(1_728_060);
                        await t0wnCampaign.enableRefunds();
                        await pledgerCalling.withdraw(pledger.address);
                        const [
                            amountRefunded,
                            percentRefunded,
                            notRefunded,
                            refundsCompletedBool,
                        ] = await t0wnCampaign.getRefundStatus();
                        assert.equal(amountRefunded, "0.001");
                        assert.equal(percentRefunded, 20);
                        assert.equal(notRefunded, "0.003");
                        assert.equal(refundsCompletedBool, false);
                    });
                });
            });
        });
    });
}

// try {

// } catch(e) {
//     console.log(e);
// }

// const balance = await ethers.provider.getBalance(
//     t0wnCampaign.address
// );

// for (let i = 0; i < earlyPledgers.lenght; i++) {

// }

// await pledgerCalling.deposit(pledger.address, {
//     value: utils.parseEther("0.0001"),
// });

// await earlyPledgerCalling.deposit(earlyPledger.address, {
//     value: utils.parseEther("0.0001"),
// });

// const beforetime = await time.latest();
// console.log(beforetime);
// console.log(EXPIRY_DATE);
// await time.increase(1_728_000_600); // 20 days and one minute in milliseconds
// const currentTime = await time.latest();
// console.log(currentTime);

// const currentTimestamp = (
//     await ethers.provider.getBlock("latest")
// ).timestamp;
