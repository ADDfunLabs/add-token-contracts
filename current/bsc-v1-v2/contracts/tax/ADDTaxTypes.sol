// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ADDTaxTypes {
    uint256 internal constant BPS = 10_000;
    // Initial release policy: each direction may charge at most 10%, fixed at creation.
    uint256 internal constant MAX_TAX_BPS = 1_000;
    enum RewardMode { BNB, Token, Self }
    struct Config {
        uint16 buyTaxBps;
        uint16 sellTaxBps;
        uint16 marketingBps;
        uint16 burnBps;
        uint16 dividendBps;
        uint16 liquidityBps;
        address marketingWallet;
        address operator; // Manual bounded maintenance fallback; automatic trades do not require this signature.
        RewardMode rewardMode;
        address rewardToken;
        uint256 minimumHolding;
    }
    function validate(Config memory c) internal view {
        require(c.buyTaxBps <= MAX_TAX_BPS && c.sellTaxBps <= MAX_TAX_BPS, "Tax exceeds 10%");
        require(c.buyTaxBps > 0 || c.sellTaxBps > 0, "Use zero-tax template");
        require(uint256(c.marketingBps)+c.burnBps+c.dividendBps+c.liquidityBps == BPS, "Allocation must total 100%");
        require(c.marketingBps == 0 || (c.marketingWallet != address(0) && c.marketingWallet != address(0xdead)), "Invalid marketing wallet");
        require(c.operator != address(0) && c.operator != address(0xdead), "Invalid operator");
        require(c.minimumHolding <= 1_000_000_000 ether, "Holding threshold exceeds supply");
        if(c.rewardMode == RewardMode.Token) require(c.rewardToken.code.length > 0, "Reward must be a token");
        else require(c.rewardToken == address(0), "Unexpected reward address");
    }
}

interface IADDTaxRouter {
    function factory() external view returns(address);
    function WETH() external view returns(address);
    function getAmountsOut(uint256,address[] calldata) external view returns(uint256[] memory);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[] calldata,address,uint256) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[] calldata,address,uint256) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[] calldata,address,uint256) external;
    function addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256) external returns(uint256,uint256,uint256);
}
interface IADDTaxLifecycle { function liquidityAdded() external view returns(bool); }
interface IADDTaxModules { function taxProcessor() external view returns(address); }
interface IADDTaxAutomaticState { function automaticActive() external view returns(bool); }
interface IADDTaxWrapped { function withdraw(uint256) external; }

library ADDTaxClones {
    function code(address implementation) internal pure returns(bytes memory) {
        return abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",implementation,hex"5af43d82803e903d91602b57fd5bf3");
    }
    function clone(address implementation) internal returns(address instance) {
        bytes memory creation=code(implementation);
        assembly ("memory-safe") { instance := create(0,add(creation,32),mload(creation)) }
        require(instance != address(0), "Clone failed");
    }
}
