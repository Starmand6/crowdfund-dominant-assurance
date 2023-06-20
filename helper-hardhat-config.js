const { utils } = require("ethers");

const networkConfig = {
    31337: {
        name: "hardhat",
        usdcAddress: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
    },
    420: {
        name: "optimismGoerli",
        usdcAddress: "0x3714A8C7824B22271550894f7555f0a672f97809",
    },
    10: {
        name: "optimismMainnet",
        usdcAddress: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
    },
};

const TITLE = "Beachfront Property";
const TARGET_AMOUNT = utils.parseEther("0.001");
const REFUND_BONUS = utils.parseEther("0.0002");
const MIN_PLEDGE_AMOUNT = utils.parseEther("0.0001");
const CAMPAIGN_LENGTH_IN_DAYS = 20; // Days
const MAX_EARLY_PLEDGERS = 1;

module.exports = {
    networkConfig,
    TITLE,
    TARGET_AMOUNT,
    REFUND_BONUS,
    CAMPAIGN_LENGTH_IN_DAYS,
    MIN_PLEDGE_AMOUNT,
    MAX_EARLY_PLEDGERS,
};

// const TITLE = "Beachfront Property";
// const TARGET_AMOUNT = 2_000_000;
// const REFUND_BONUS = 40_000;
// const EXPIRY_DATE = 1_728_000_000; // 20 days worth of milliseconds
// const MIN_PLEDGE_AMOUNT = 75_000;
// const MAX_EARLY_PLEDGERS = 8;
