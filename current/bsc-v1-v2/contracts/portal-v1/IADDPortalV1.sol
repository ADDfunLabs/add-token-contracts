// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Admission data signed as part of the factory or owner transaction.
/// @dev BNB targets use wei; tokenDeposit and quoteTarget use their own ERC20 base
///      units. A quote target is snapshotted, so later BNB/USDT exchange-rate changes
///      do not reprice an active sale. Metadata is an opaque URI, never executable.
struct ADDAdmissionV1 {
    address token;
    address creator;
    address quoteAsset; // address(0) = native BNB; native buys/sells remain available for ERC20 quotes.
    uint256 tokenDeposit; // Expected unencumbered balance ALREADY held by Portal.
    uint256 targetBNB;
    uint256 quoteTarget; // Expected asset target from Portal.quoteGraduationTarget.
    uint256 deadline;
    bool customTarget;
    bool lifecycleHooks;
    string metadataURI;
}

/// @notice Opt-in public external deposit. The caller becomes the recorded creator;
///         Portal pulls only this caller's approved amount in the same transaction.
struct ADDExternalLaunchV1 {
    address token;
    uint256 amount;
    address quoteAsset;
    uint256 targetBNB;
    uint256 quoteTarget;
    uint256 deadline;
    bool customTarget;
    string metadataURI;
}

interface IADDPortalAdmissionV1 {
    function registerFactoryToken(ADDAdmissionV1 calldata admission) external;
    function depositAndRegisterExternalToken(ADDExternalLaunchV1 calldata launch) external;
    function quoteGraduationTarget(address asset, uint256 targetBNB) external view returns (uint256 target, uint8 decimals_);
}

/// @notice Only owner-approved factories implementing this interface may auto-admit tokens.
/// @dev A factory must set its creation record BEFORE calling registerFactoryToken,
///      in the SAME transaction as creation/deposit. These getters are attestations
///      from a trusted, reviewed factory, not cryptographic proof of arbitrary code.
interface IADDTokenFactoryV1 {
    function portal() external view returns (address);
    function portalFactoryVersion() external pure returns (uint256);
    function isCreatedToken(address token) external view returns (bool);
    function creatorOf(address token) external view returns (address);
}

/// @notice Optional hooks for new compatible ADD tokens. Plain externally listed
///         ERC20s use lifecycleHooks=false and receive no lifecycle calls.
interface IADDPortalTokenHooksV1 {
    function portal() external view returns (address);
    function portalTokenVersion() external pure returns (uint256);
    function onPortalAdmission(address pair) external;
    function onPortalMigrationStart(address pair) external;
    function onPortalGraduation() external;
    function onPortalRefundStart() external;
    function onPortalRefundComplete() external;
}

interface IADDV2RouterV1 {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function getAmountsOut(uint256 amount, address[] calldata path) external view returns (uint256[] memory);
    function getAmountsIn(uint256 amount, address[] calldata path) external view returns (uint256[] memory);
    function swapETHForExactTokens(uint256 amountOut,address[] calldata path,address to,uint256 deadline) external payable returns (uint256[] memory);
    function swapExactTokensForETH(uint256 amountIn,uint256 minOut,address[] calldata path,address to,uint256 deadline) external returns (uint256[] memory);
    function swapExactTokensForTokens(uint256 amountIn,uint256 minOut,address[] calldata path,address to,uint256 deadline) external returns (uint256[] memory);
}

interface IADDV2FactoryV1 {
    function getPair(address a, address b) external view returns (address);
    function createPair(address a, address b) external returns (address);
}

interface IADDV2PairV1 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getReserves() external view returns (uint112,uint112,uint32);
    function mint(address recipient) external returns (uint256);
}

interface IADDWrappedNativeV1 {
    function deposit() external payable;
}
