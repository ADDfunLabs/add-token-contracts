// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDPortalLedgerV1.sol";
interface IADDTradeHostV1 { function executeAfterBuy(address token) external; }

/// @notice Fixed trade implementation shared by immutable V1 Portals.
/// @dev Portal stores the module address immutably and delegates ONLY buy/sell.
///      This module and the host must inherit IDENTICAL ADDPortalLedgerV1 storage;
///      no upgrade setter exists. Deploy this module first, then pass its address
///      to the Portal constructor. Direct buy/sell on the module are forbidden.
contract ADDPortalTradeModuleV1 is ADDPortalLedgerV1 {
    address private immutable moduleAddress;
    error OnlyDelegateCall();
    constructor(address router_) ADDPortalLedgerV1(msg.sender,router_,msg.sender,false) {
        moduleAddress = address(this);
    }
    modifier onlyDelegate() {
        if (address(this) == moduleAddress) revert OnlyDelegateCall();
        _;
    }
    function buy(address token,uint256 minimumTokens,uint256 deadline) external payable onlyDelegate nonReentrant returns (uint256) {
        if (block.timestamp > deadline) revert TradeExpired();
        if (pools[token].phase != Phase.Active) revert PoolNotActive();
        if (address(this).balance - msg.value < totalNativeReserved) revert InsufficientBacking();
        _assertPoolBacking(token);
        BuyQuote memory q = quoteBuy(token,msg.value);
        if (q.tokens == 0) revert InvalidAmount();
        if (q.tokens < minimumTokens) revert SlippageExceeded();
        Pool storage p = pools[token];
        p.sold += q.tokens;
        p.reserve += q.principal;
        protectedERC20[token] -= q.tokens;
        if (p.quoteAsset == address(0)) totalNativeReserved += q.principal;
        else {
            uint256 beforeAsset = IERC20Minimal(p.quoteAsset).balanceOf(address(this));
            uint256[] memory spent = IADDV2RouterV1(router).swapETHForExactTokens{value:q.nativeUsed}(
                q.principal,_path(p.quoteAsset,true),address(this),deadline);
            if (spent.length != 2 || spent[0] != q.nativeUsed || spent[1] != q.principal
                || IERC20Minimal(p.quoteAsset).balanceOf(address(this)) != beforeAsset + q.principal) revert UnsupportedTransfer();
            protectedERC20[p.quoteAsset] += q.principal;
        }
        _exactTransfer(token,msg.sender,q.tokens);
        _send(feeRecipient,q.fee);
        _send(msg.sender,q.refund);
        emit Buy(token,msg.sender,msg.value,q.tokens,q.principal,q.nativeUsed,q.fee,q.refund);
        IADDTradeHostV1(address(this)).executeAfterBuy(token);
        _assertPoolBacking(token);
        return q.tokens;
    }

    function sell(address token,uint256 amount,uint256 minimumBNB,uint256 deadline) external onlyDelegate nonReentrant returns (uint256 net) {
        if (block.timestamp > deadline) revert TradeExpired();
        if (pools[token].phase != Phase.Active) revert PoolNotActive();
        _assertPoolBacking(token);
        (uint256 principal,uint256 gross,,) = quoteSell(token,amount);
        Pool storage p = pools[token];
        if (principal > p.reserve) revert InsufficientBacking();
        p.sold -= amount;
        p.reserve -= principal;
        protectedERC20[token] += amount;
        if (p.quoteAsset == address(0)) totalNativeReserved -= principal;
        else protectedERC20[p.quoteAsset] -= principal;
        _exactPull(token,msg.sender,amount);
        if (p.quoteAsset != address(0)) {
            uint256 beforeAsset = IERC20Minimal(p.quoteAsset).balanceOf(address(this));
            uint256 beforeBNB = address(this).balance;
            _approve(p.quoteAsset,principal);
            uint256[] memory received = IADDV2RouterV1(router).swapExactTokensForETH(
                principal,minimumBNB,_path(p.quoteAsset,false),address(this),deadline);
            _approve(p.quoteAsset,0);
            gross = address(this).balance - beforeBNB;
            if (received.length != 2 || received[0] != principal || received[1] != gross
                || IERC20Minimal(p.quoteAsset).balanceOf(address(this)) + principal != beforeAsset) revert UnsupportedTransfer();
        }
        uint256 fee = gross / 100;
        net = gross - fee;
        if (net == 0) revert InvalidAmount();
        if (net < minimumBNB) revert SlippageExceeded();
        _send(feeRecipient,fee);
        _send(msg.sender,net);
        emit Sell(token,msg.sender,amount,principal,gross,fee,net);
        _assertPoolBacking(token);
    }

}
