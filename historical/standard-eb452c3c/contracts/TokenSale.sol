// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./openzeppelin/ERC20.sol";
import "./FullMath.sol";

interface IADDPortalState {
    function totalSold(address token) external view returns (uint256);
    /// @notice Compatibility inner-only quote forwarded to Portal; returns zero fill after graduation.
    function quoteBuy(address token, uint256 payment) external view returns (uint256,uint256,uint256,uint256);
    function quoteSell(address token,uint256 amount) external view returns(uint256,uint256,uint256);
}
/// @notice ADD ERC20. Inventory and native/ERC20 quote reserves are held by the Portal.
    /// @dev Non-upgradeable EIP-1167 clones. Audit initialization and domain separation in docs/audit/10-prepared-addresses.md.
    /// @dev Local openzeppelin directory is custom code and must be audited, not treated as upstream-certified.
contract TokenSale is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant SALE_AMOUNT = TOTAL_SUPPLY / 2;
    uint256 public constant LIQ_TOKEN_AMOUNT = TOTAL_SUPPLY / 2;
    /// @notice Net graduation target in quote-asset base units, initialized once; minimum one whole quote asset.
    uint256 public targetETHForSale;
    /// @notice address(0) = native BNB. Nonzero reserves and targets use quoteDecimals base units.
    address public quoteAsset;
    uint8 public quoteDecimals;
    /// @notice Display-only floor of target / 500 million. Settlement uses the exact target/SALE_AMOUNT ratio.
    uint256 public priceWeiPerToken;
    uint256 public constant FEE_BPS = 100;
    address public constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public factory;
    /// @notice Token lifecycle authority: Portal during the sale, dead permanently after verified graduation.
    /// factory remains the immutable-in-practice trading/ledger binding; this is NOT the Portal's own owner.
    address public owner;
    address public router;
    address public feeRecipient;
    /// @notice Fixed in implementation bytecode, shared by all clones of this template.
    address private immutable defaultInitializationAuthority;
    /// @notice Customer templates override this getter with their immutable approved ADD deployment helper.
    function initializationAuthority() public view virtual returns(address) { return defaultInitializationAuthority; }
    /// @notice Interface marker only; administrator review and code-hash approval are still required.
    function addTemplateVersion() external pure returns(uint256) { return 1; }
    bool private initialized;
    /// @dev Permanent issuance latch, separate from lifecycle and current total supply.
    /// No burn/remint cycle or inherited hook may use the standard accounting path to issue again.
    bool private initialSupplyMinted;
    address public pairAddress;
    uint256 public lpTokensBurned;
    /// @dev BondingCurve is a lifecycle name retained for familiarity; ADD uses a fixed inner price.
    enum Phase { BondingCurve, Migrating, DEX }
    Phase public phase;
    event PhaseChanged(Phase phase);
    event OwnershipTransferred(address indexed previousOwner,address indexed newOwner);
    modifier onlyPortal() { require(msg.sender == factory && owner == factory, "Only Portal"); _; }
    /// @dev Lock the implementation itself; clones start with their own zeroed storage.
    constructor() ERC20("", "") {
        defaultInitializationAuthority = msg.sender;
        initialized = true;
        owner = LP_BURN_ADDRESS;
    }
    /// @notice Deployer-only initialization, in the same transaction as clone creation. Mint once to Portal.
    /// @dev Mark initialized before state work. Reviewed customer hooks run before deployer postconditions; reverts roll back deployment.
    function initialize(string calldata n, string calldata s, address portal, uint256 target,
        address router_, address feeRecipient_) external {
        _initialize(n,s,portal,target,router_,feeRecipient_,address(0),18);
    }
    function initializeWithQuote(string calldata n,string calldata s,address portal,uint256 target,
        address router_,address feeRecipient_,address asset,uint8 decimals_) external {
        _initialize(n,s,portal,target,router_,feeRecipient_,asset,decimals_);
    }
    function _initialize(string calldata n,string calldata s,address portal,uint256 target,
        address router_,address feeRecipient_,address asset,uint8 decimals_) internal {
        require(msg.sender == initializationAuthority(), "Only deployer may initialize");
        require(!initialized, "Already initialized");
        initialized = true;
        require(bytes(n).length > 0 && bytes(s).length > 0, "Invalid name/symbol");
        require(portal != address(0) && router_ != address(0), "Invalid infrastructure");
        require(decimals_ <= 36 && (asset != address(0) || decimals_ == 18), "Invalid quote decimals");
        if(asset == address(0)) require(target >= 1 ether,"Target must be at least 1 BNB");
        require(target >= 10 ** uint256(decimals_), "Target below one quote unit");
        require(target % (10 ** uint256(decimals_)) == 0,"Quote target must be an integer");
        quoteAsset=asset; quoteDecimals=decimals_;
        require(feeRecipient_ != address(0), "Fee recipient zero");
        factory = portal; router = router_; feeRecipient = feeRecipient_;
        owner = portal;
        emit OwnershipTransferred(address(0),portal);
        targetETHForSale = target; priceWeiPerToken = FullMath.mulDiv(target,1 ether,SALE_AMOUNT);
        _initializeMetadata(n,s);
        _mint(portal, TOTAL_SUPPLY);
        _afterLaunchInitialization();
    }
    /// @dev Extension point for audited per-instance state. Runs once, atomically with initialization.
    /// Constructor storage is NOT copied to clones. Extensions must preserve inventory, phases and transfer rules.
    function _afterLaunchInitialization() internal virtual {}
    /// @notice Portal-only, one-time assignment of the canonical TOKEN/quote V2 pool (WBNB for native mode).
    /// @param pair Address with code obtained from the configured router's factory.
    function setMainPool(address pair) external onlyPortal {
        require(pairAddress == address(0) && pair.code.length > 0, "Invalid pool"); pairAddress = pair;
    }
    /// @notice Portal-only transition 0 -> 1; called inside the final inner purchase.
    function startMigration() external onlyPortal {
        require(phase == Phase.BondingCurve, "Invalid phase"); phase = Phase.Migrating; emit PhaseChanged(phase);
    }
    /// @notice Portal-only transition 1 -> 2 after Portal verifies LP delivery. Permanently relinquishes token authority.
    /// @param lp LP base units verified by Portal as delivered to dead.
    function finalizeMigration(uint256 lp) external onlyPortal {
        require(phase == Phase.Migrating && lp > 0, "Invalid phase");
        lpTokensBurned = lp; phase = Phase.DEX;
        owner = LP_BURN_ADDRESS;
        emit OwnershipTransferred(factory,LP_BURN_ADDRESS);
        emit PhaseChanged(phase);
    }
    /// @notice Read the isolated Portal ledger; this contract stores no inner BNB.
    function totalSold() external view returns(uint256) { return IADDPortalState(factory).totalSold(address(this)); }
    /// @notice True from migration onward, including the transient intra-transaction Migrating phase.
    function saleEnded() external view returns(bool) { return phase != Phase.BondingCurve; }
    /// @notice True only after migration verification completes.
    function liquidityAdded() external view returns(bool) { return phase == Phase.DEX; }
    /// @notice Compatibility getter: wallets can transfer in all settled phases.
    /// @dev True does not mean every destination is unrestricted; pool and accidental-deposit checks still apply.
    function transfersEnabled() external pure returns(bool) { return true; }
    function quoteBuy(uint256 value) public view returns(uint256,uint256,uint256,uint256) {
        return IADDPortalState(factory).quoteBuy(address(this),value);
    }
    /// @notice Inner-only estimate; does not quote the graduated pool. Use Portal.quoteExactInput for trading.
    function estimateTokensForETH(uint256 value) external view returns(uint256) { (uint256 out,,,) = quoteBuy(value); return out; }
    /// @notice Inner net BNB estimate, even after graduation; nonnative conversion uses current Router prices.
    /// @dev NOT a DEX quote, balance check, or sell authorization. Bounds prevent multiplication overflow.
    function estimateETHForTokens(uint256 amount) external view returns(uint256) {
        require(amount <= SALE_AMOUNT, "Amount exceeds sale supply");
        (,,uint256 net) = IADDPortalState(factory).quoteSell(address(this),amount); return net;
    }
    /// @dev Conventional V2/V3 pool detection. Custom vaults without these getters are not universally detectable.
    /// @notice Recognize the main pair and conventional V2/V3-style pools referencing this token.
    /// @param account Candidate sender or recipient.
    /// @return True if identified as a restricted pool (phase enforcement occurs in _update).
    /// @dev Heuristic only: constructor-time code absence, vault/singleton designs and custom pools can bypass it.
    /// @dev Both probes cap forwarded gas, but return-data handling and adversarial getters still need review.
    function isRestrictedPool(address account) public view returns(bool) {
        if (account == pairAddress && account != address(0)) return true;
        if (account.code.length == 0 || account == factory) return false;
        (bool ok0, bytes memory a) = account.staticcall{gas:12000}(abi.encodeWithSignature("token0()"));
        (bool ok1, bytes memory b) = account.staticcall{gas:12000}(abi.encodeWithSignature("token1()"));
        if (!ok0 || !ok1 || a.length != 32 || b.length != 32) return false;
        return uint256(bytes32(a)) == uint256(uint160(address(this))) || uint256(bytes32(b)) == uint256(uint160(address(this)));
    }
    /// @dev Issue exactly TOTAL_SUPPLY once to Portal during authorized initialization; no later mint or burn.
    /// Direct deposits to this token always fail.
    /// @dev Only Portal may transferFrom into itself; donations do not implicitly execute a sale.
    /// @dev Inner wallets can transfer; recognized pool transfers fail. Migrating allows Portal -> mainPool only.
    /// @dev DEX removes pool checks but retains accidental-deposit checks; never adds an ADD transfer tax.
    function _update(address from,address to,uint256 value) internal override {
        if (from == address(0)) {
            require(initialized && !initialSupplyMinted && msg.sender == initializationAuthority()
                && to == factory && value == TOTAL_SUPPLY, "Fixed supply: initial issuance only");
            initialSupplyMinted = true;
        } else {
            require(to != address(0), "Fixed supply: burn disabled");
            require(to != address(this), "Use Portal to trade");
            require(to != factory || msg.sender == factory, "Use Portal to sell");
            if (phase == Phase.BondingCurve) {
                require(!isRestrictedPool(from) && !isRestrictedPool(to), "Pool transfers locked before graduation");
            } else if (phase == Phase.Migrating) {
                require(from == factory && to == pairAddress, "Migration transfer only");
            }
        }
        super._update(from,to,value);
    }
}
