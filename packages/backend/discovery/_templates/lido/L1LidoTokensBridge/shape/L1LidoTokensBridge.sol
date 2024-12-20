// SPDX-License-Identifier: Unknown
pragma solidity 0.8.10;

library UnstructuredStorage {
    function getStorageBool(bytes32 position) internal view returns (bool data) {
        assembly { data := sload(position) }
    }

    function getStorageUint256(bytes32 position) internal view returns (uint256 data) {
        assembly { data := sload(position) }
    }

    function setStorageBool(bytes32 position, bool data) internal {
        assembly { sstore(position, data) }
    }

    function setStorageUint256(bytes32 position, uint256 data) internal {
        assembly { sstore(position, data) }
    }
}

contract Versioned {
    using UnstructuredStorage for bytes32;

    event ContractVersionSet(uint256 version);

    error NonZeroContractVersionOnInit();
    error InvalidContractVersionIncrement();
    error UnexpectedContractVersion(uint256 expected, uint256 received);

    /// @dev Storage slot: uint256 version
    /// Version of the initialized contract storage.
    /// The version stored in CONTRACT_VERSION_POSITION equals to:
    /// - 0 right after the deployment, before an initializer is invoked (and only at that moment);
    /// - N after calling initialize(), where N is the initially deployed contract version;
    /// - N after upgrading contract by calling finalizeUpgrade_vN().
    bytes32 internal constant CONTRACT_VERSION_POSITION = keccak256("lido.Versioned.contractVersion");

    uint256 internal constant PETRIFIED_VERSION_MARK = type(uint256).max;

    constructor() {
        // lock version in the implementation's storage to prevent initialization
        CONTRACT_VERSION_POSITION.setStorageUint256(PETRIFIED_VERSION_MARK);
    }

    /// @notice Returns the current contract version.
    function getContractVersion() public view returns (uint256) {
        return CONTRACT_VERSION_POSITION.getStorageUint256();
    }

    function _checkContractVersion(uint256 version) internal view {
        uint256 expectedVersion = getContractVersion();
        if (version != expectedVersion) {
            revert UnexpectedContractVersion(expectedVersion, version);
        }
    }

    /// @dev Sets the contract version to N. Should be called from the initialize() function.
    function _initializeContractVersionTo(uint256 version) internal {
        if (getContractVersion() != 0) revert NonZeroContractVersionOnInit();
        _setContractVersion(version);
    }

    /// @dev Updates the contract version. Should be called from a finalizeUpgrade_vN() function.
    function _updateContractVersion(uint256 newVersion) internal {
        if (newVersion != getContractVersion() + 1) revert InvalidContractVersionIncrement();
        _setContractVersion(newVersion);
    }

    function _setContractVersion(uint256 version) private {
        CONTRACT_VERSION_POSITION.setStorageUint256(version);
        emit ContractVersionSet(version);
    }
}

abstract contract TokenRateAndUpdateTimestampProvider {

    /// @notice Non-rebasable token of Core Lido procotol.
    address public immutable WSTETH;

    /// @notice Address of the AccountingOracle instance
    address public immutable ACCOUNTING_ORACLE;

    /// @notice Timetamp of the Consensus Layer genesis
    uint256 public immutable GENESIS_TIME;

    /// @notice Seconds per single Consensus Layer slot
    uint256 public immutable SECONDS_PER_SLOT;

    /// @notice Token rate decimals to push
    uint256 public constant TOKEN_RATE_DECIMALS = 27;

    constructor(address wstETH_, address accountingOracle_) {
        if (wstETH_ == address(0)) {
            revert ErrorZeroAddressWstETH();
        }
        if (accountingOracle_ == address(0)) {
            revert ErrorZeroAddressAccountingOracle();
        }
        WSTETH = wstETH_;
        ACCOUNTING_ORACLE = accountingOracle_;
        GENESIS_TIME = IAccountingOracle(ACCOUNTING_ORACLE).GENESIS_TIME();
        SECONDS_PER_SLOT = IAccountingOracle(ACCOUNTING_ORACLE).SECONDS_PER_SLOT();
    }

    function _getTokenRateAndUpdateTimestamp() internal view returns (uint256 rate, uint256 updateTimestamp) {
        rate = IERC20WstETH(WSTETH).getStETHByWstETH(10 ** TOKEN_RATE_DECIMALS);

        /// @dev github.com/ethereum/consensus-specs/blob/dev/specs/bellatrix/beacon-chain.md#compute_timestamp_at_slot
        updateTimestamp = GENESIS_TIME + SECONDS_PER_SLOT * IAccountingOracle(
            ACCOUNTING_ORACLE
        ).getLastProcessingRefSlot();
    }

    error ErrorZeroAddressWstETH();
    error ErrorZeroAddressAccountingOracle();
}

interface IL1ERC20Bridge {
    event ERC20DepositInitiated(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    event ERC20WithdrawalFinalized(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    /// @notice get the address of the corresponding L2 bridge contract.
    /// @return Address of the corresponding L2 bridge contract.
    function l2TokenBridge() external returns (address);

    /// @notice deposit an amount of the ERC20 to the caller's balance on L2.
    /// @param l1Token_ Address of the L1 ERC20 we are depositing
    /// @param l2Token_ Address of the L1 respective L2 ERC20
    /// @param amount_ Amount of the ERC20 to deposit
    /// @param l2Gas_ Gas limit required to complete the deposit on L2.
    /// @param data_ Optional data to forward to L2. This data is provided
    ///        solely as a convenience for external contracts. Aside from enforcing a maximum
    ///        length, these contracts provide no guarantees about its content.
    function depositERC20(
        address l1Token_,
        address l2Token_,
        uint256 amount_,
        uint32 l2Gas_,
        bytes calldata data_
    ) external;

    /// @notice deposit an amount of ERC20 to a recipient's balance on L2.
    /// @param l1Token_ Address of the L1 ERC20 we are depositing
    /// @param l2Token_ Address of the L1 respective L2 ERC20
    /// @param to_ L2 address to credit the withdrawal to.
    /// @param amount_ Amount of the ERC20 to deposit.
    /// @param l2Gas_ Gas limit required to complete the deposit on L2.
    /// @param data_ Optional data to forward to L2. This data is provided
    ///        solely as a convenience for external contracts. Aside from enforcing a maximum
    ///        length, these contracts provide no guarantees about its content.
    function depositERC20To(
        address l1Token_,
        address l2Token_,
        address to_,
        uint256 amount_,
        uint32 l2Gas_,
        bytes calldata data_
    ) external;

    /// @notice Complete a withdrawal from L2 to L1, and credit funds to the recipient's balance of the
    /// L1 ERC20 token.
    /// @dev This call will fail if the initialized withdrawal from L2 has not been finalized.
    /// @param l1Token_ Address of L1 token to finalizeWithdrawal for.
    /// @param l2Token_ Address of L2 token where withdrawal was initiated.
    /// @param from_ L2 address initiating the transfer.
    /// @param to_ L1 address to credit the withdrawal to.
    /// @param amount_ Amount of the ERC20 to deposit.
    /// @param data_ Data provided by the sender on L2. This data is provided
    ///   solely as a convenience for external contracts. Aside from enforcing a maximum
    ///   length, these contracts provide no guarantees about its content.
    function finalizeERC20Withdrawal(
        address l1Token_,
        address l2Token_,
        address from_,
        address to_,
        uint256 amount_,
        bytes calldata data_
    ) external;
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

interface IAccessControl {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}

interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `_msgSender()` is missing `role`.
     * Overriding this function changes the behavior of the {onlyRole} modifier.
     *
     * Format of the revert message is described in {_checkRole}.
     *
     * _Available since v4.6._
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(uint160(account), 20),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     *
     * NOTE: This function is deprecated in favor of {_grantRole}.
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

contract BridgingManager is AccessControl {
    /// @dev Stores the state of the bridging
    /// @param isInitialized Shows whether the contract is initialized or not
    /// @param isDepositsEnabled Stores the state of the deposits
    /// @param isWithdrawalsEnabled Stores the state of the withdrawals
    struct State {
        /// @dev This variable is used to determine whether the contract has been initialized or not.
        /// At the same time, bridges have their own code for initialization and storage versioning.
        /// Therefore, it is recommended to base upgrade logic on new mechanisms since v2.
        bool isInitialized;
        bool isDepositsEnabled;
        bool isWithdrawalsEnabled;
    }

    bytes32 public constant DEPOSITS_ENABLER_ROLE =
        keccak256("BridgingManager.DEPOSITS_ENABLER_ROLE");
    bytes32 public constant DEPOSITS_DISABLER_ROLE =
        keccak256("BridgingManager.DEPOSITS_DISABLER_ROLE");
    bytes32 public constant WITHDRAWALS_ENABLER_ROLE =
        keccak256("BridgingManager.WITHDRAWALS_ENABLER_ROLE");
    bytes32 public constant WITHDRAWALS_DISABLER_ROLE =
        keccak256("BridgingManager.WITHDRAWALS_DISABLER_ROLE");

    /// @dev The location of the slot with State
    bytes32 private constant STATE_SLOT =
        keccak256("BridgingManager.bridgingState");

    /// @notice Initializes the contract to grant DEFAULT_ADMIN_ROLE to the admin_ address
    /// @dev This method might be called only once
    /// @param admin_ Address of the account to grant the DEFAULT_ADMIN_ROLE
    function _initializeBridgingManager(address admin_) internal {
        if (admin_ == address(0)) {
            revert ErrorZeroAddressAdmin();
        }
        State storage s = _loadState();
        if (s.isInitialized) {
            revert ErrorAlreadyInitialized();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        s.isInitialized = true;
        emit Initialized(admin_);
    }

    /// @notice Returns whether the contract is initialized or not
    function isInitialized() public view returns (bool) {
        return _loadState().isInitialized;
    }

    /// @notice Returns whether the deposits are enabled or not
    function isDepositsEnabled() public view returns (bool) {
        return _loadState().isDepositsEnabled;
    }

    /// @notice Returns whether the withdrawals are enabled or not
    function isWithdrawalsEnabled() public view returns (bool) {
        return _loadState().isWithdrawalsEnabled;
    }

    /// @notice Enables the deposits if they are disabled
    function enableDeposits() external onlyRole(DEPOSITS_ENABLER_ROLE) {
        if (isDepositsEnabled()) {
            revert ErrorDepositsEnabled();
        }
        _loadState().isDepositsEnabled = true;
        emit DepositsEnabled(msg.sender);
    }

    /// @notice Disables the deposits if they aren't disabled yet
    function disableDeposits()
        external
        whenDepositsEnabled
        onlyRole(DEPOSITS_DISABLER_ROLE)
    {
        _loadState().isDepositsEnabled = false;
        emit DepositsDisabled(msg.sender);
    }

    /// @notice Enables the withdrawals if they are disabled
    function enableWithdrawals() external onlyRole(WITHDRAWALS_ENABLER_ROLE) {
        if (isWithdrawalsEnabled()) {
            revert ErrorWithdrawalsEnabled();
        }
        _loadState().isWithdrawalsEnabled = true;
        emit WithdrawalsEnabled(msg.sender);
    }

    /// @notice Disables the withdrawals if they aren't disabled yet
    function disableWithdrawals()
        external
        whenWithdrawalsEnabled
        onlyRole(WITHDRAWALS_DISABLER_ROLE)
    {
        _loadState().isWithdrawalsEnabled = false;
        emit WithdrawalsDisabled(msg.sender);
    }

    function _isBridgingManagerInitialized() internal view returns (bool) {
        State storage s = _loadState();
        return s.isInitialized;
    }

    /// @dev Returns the reference to the slot with State struct
    function _loadState() private pure returns (State storage r) {
        bytes32 slot = STATE_SLOT;
        assembly {
            r.slot := slot
        }
    }

    /// @dev Validates that deposits are enabled
    modifier whenDepositsEnabled() {
        if (!isDepositsEnabled()) {
            revert ErrorDepositsDisabled();
        }
        _;
    }

    /// @dev Validates that withdrawals are enabled
    modifier whenWithdrawalsEnabled() {
        if (!isWithdrawalsEnabled()) {
            revert ErrorWithdrawalsDisabled();
        }
        _;
    }

    event DepositsEnabled(address indexed enabler);
    event DepositsDisabled(address indexed disabler);
    event WithdrawalsEnabled(address indexed enabler);
    event WithdrawalsDisabled(address indexed disabler);
    event Initialized(address indexed admin);

    error ErrorZeroAddressAdmin();
    error ErrorDepositsEnabled();
    error ErrorDepositsDisabled();
    error ErrorWithdrawalsEnabled();
    error ErrorWithdrawalsDisabled();
    error ErrorAlreadyInitialized();
    error ErrorBridgingManagerIsNotInitialized();
}

contract RebasableAndNonRebasableTokens {

    /// @notice Address of the bridged non rebasable token in the L1 chain
    address public immutable L1_TOKEN_NON_REBASABLE;

    /// @notice Address of the bridged rebasable token in the L1 chain
    address public immutable L1_TOKEN_REBASABLE;

    /// @notice Address of the non rebasable token minted on the L2 chain when token bridged
    address public immutable L2_TOKEN_NON_REBASABLE;

    /// @notice Address of the rebasable token minted on the L2 chain when token bridged
    address public immutable L2_TOKEN_REBASABLE;

    /// @param l1TokenNonRebasable_ Address of the bridged non rebasable token in the L1 chain
    /// @param l1TokenRebasable_ Address of the bridged rebasable token in the L1 chain
    /// @param l2TokenNonRebasable_ Address of the non rebasable token minted on the L2 chain when token bridged
    /// @param l2TokenRebasable_ Address of the rebasable token minted on the L2 chain when token bridged
    constructor(
        address l1TokenNonRebasable_,
        address l1TokenRebasable_,
        address l2TokenNonRebasable_,
        address l2TokenRebasable_
    ) {
        if (l1TokenNonRebasable_ == address(0)) {
            revert ErrorZeroAddressL1TokenNonRebasable();
        }
        if (l1TokenRebasable_ == address(0)) {
            revert ErrorZeroAddressL1TokenRebasable();
        }
        if (l2TokenNonRebasable_ == address(0)) {
            revert ErrorZeroAddressL2TokenNonRebasable();
        }
        if (l2TokenRebasable_ == address(0)) {
            revert ErrorZeroAddressL2TokenRebasable();
        }
        L1_TOKEN_NON_REBASABLE = l1TokenNonRebasable_;
        L1_TOKEN_REBASABLE = l1TokenRebasable_;
        L2_TOKEN_NON_REBASABLE = l2TokenNonRebasable_;
        L2_TOKEN_REBASABLE = l2TokenRebasable_;
    }

    function _isSupportedL1L2TokensPair(address l1Token_, address l2Token_) internal view returns (bool) {
        bool isNonRebasablePair = l1Token_ == L1_TOKEN_NON_REBASABLE && l2Token_ == L2_TOKEN_NON_REBASABLE;
        bool isRebasablePair = l1Token_ == L1_TOKEN_REBASABLE && l2Token_ == L2_TOKEN_REBASABLE;
        return isNonRebasablePair || isRebasablePair;
    }

    function _getL1Token(address l2Token_) internal view returns (address) {
        if (l2Token_ == L2_TOKEN_NON_REBASABLE) { return L1_TOKEN_NON_REBASABLE; }
        if (l2Token_ == L2_TOKEN_REBASABLE) { return L1_TOKEN_REBASABLE; }
        revert ErrorUnsupportedL2Token(l2Token_);
    }

    /// @dev Validates that passed l1Token_ and l2Token_ tokens pair is supported by the bridge.
    modifier onlySupportedL1L2TokensPair(address l1Token_, address l2Token_) {
        if (!_isSupportedL1L2TokensPair(l1Token_, l2Token_)) {
            revert ErrorUnsupportedL1L2TokensPair(l1Token_, l2Token_);
        }
        _;
    }

    /// @dev Validates that passed l2Token_ is supported by the bridge
    modifier onlySupportedL2Token(address l2Token_) {
        if (l2Token_ != L2_TOKEN_NON_REBASABLE && l2Token_ != L2_TOKEN_REBASABLE) {
            revert ErrorUnsupportedL2Token(l2Token_);
        }
        _;
    }

    /// @dev validates that account_ is not zero address
    modifier onlyNonZeroAccount(address account_) {
        if (account_ == address(0)) {
            revert ErrorAccountIsZeroAddress();
        }
        _;
    }

    error ErrorZeroAddressL1TokenNonRebasable();
    error ErrorZeroAddressL1TokenRebasable();
    error ErrorZeroAddressL2TokenNonRebasable();
    error ErrorZeroAddressL2TokenRebasable();
    error ErrorUnsupportedL2Token(address l2Token);
    error ErrorUnsupportedL1L2TokensPair(address l1Token, address l2Token);
    error ErrorAccountIsZeroAddress();
}

contract CrossDomainEnabled {
    /// @notice Messenger contract used to send and receive messages from the other domain
    ICrossDomainMessenger public immutable MESSENGER;

    /// @param messenger_ Address of the CrossDomainMessenger on the current layer
    constructor(address messenger_) {
        if (messenger_ == address(0)) {
            revert ErrorZeroAddressMessenger();
        }
        MESSENGER = ICrossDomainMessenger(messenger_);
    }

    /// @dev Sends a message to an account on another domain
    /// @param crossDomainTarget_ Intended recipient on the destination domain
    /// @param message_ Data to send to the target (usually calldata to a function with
    ///     `onlyFromCrossDomainAccount()`)
    /// @param gasLimit_ gasLimit for the receipt of the message on the target domain.
    function sendCrossDomainMessage(
        address crossDomainTarget_,
        uint32 gasLimit_,
        bytes memory message_
    ) internal {
        MESSENGER.sendMessage(crossDomainTarget_, message_, gasLimit_);
    }

    /// @dev Enforces that the modified function is only callable by a specific cross-domain account
    /// @param sourceDomainAccount_ The only account on the originating domain which is
    ///     authenticated to call this function
    modifier onlyFromCrossDomainAccount(address sourceDomainAccount_) {
        if (msg.sender != address(MESSENGER)) {
            revert ErrorUnauthorizedMessenger();
        }
        if (MESSENGER.xDomainMessageSender() != sourceDomainAccount_) {
            revert ErrorWrongCrossDomainSender();
        }
        _;
    }

    error ErrorZeroAddressMessenger();
    error ErrorUnauthorizedMessenger();
    error ErrorWrongCrossDomainSender();
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

library DepositDataCodec {

    uint8 internal constant RATE_FIELD_SIZE = 16;
    uint8 internal constant TIMESTAMP_FIELD_SIZE = 5;

    struct DepositData {
        uint128 rate;
        uint40 timestamp;
        bytes data;
    }

    function encodeDepositData(DepositData memory depositData) internal pure returns (bytes memory) {
        bytes memory data = bytes.concat(
            abi.encodePacked(depositData.rate),
            abi.encodePacked(depositData.timestamp),
            abi.encodePacked(depositData.data)
        );
        return data;
    }

    function decodeDepositData(bytes calldata buffer) internal pure returns (DepositData memory) {
        if (buffer.length < RATE_FIELD_SIZE + TIMESTAMP_FIELD_SIZE) {
            revert ErrorDepositDataLength();
        }

        DepositData memory depositData = DepositData({
            rate: uint128(bytes16(buffer[0:RATE_FIELD_SIZE])),
            timestamp: uint40(bytes5(buffer[RATE_FIELD_SIZE:RATE_FIELD_SIZE + TIMESTAMP_FIELD_SIZE])),
            data: buffer[RATE_FIELD_SIZE + TIMESTAMP_FIELD_SIZE:]
        });

        return depositData;
    }

    error ErrorDepositDataLength();
}

abstract contract L1ERC20ExtendedTokensBridge is
    IL1ERC20Bridge,
    BridgingManager,
    RebasableAndNonRebasableTokens,
    CrossDomainEnabled
{
    using SafeERC20 for IERC20;

    address private immutable L2_TOKEN_BRIDGE;

    /// @param messenger_ L1 messenger address being used for cross-chain communications
    /// @param l2TokenBridge_ Address of the corresponding L2 bridge
    /// @param l1TokenNonRebasable_ Address of the bridged token in the L1 chain
    /// @param l1TokenRebasable_ Address of the bridged token in the L1 chain
    /// @param l2TokenNonRebasable_ Address of the token minted on the L2 chain when token bridged
    /// @param l2TokenRebasable_ Address of the token minted on the L2 chain when token bridged
    constructor(
        address messenger_,
        address l2TokenBridge_,
        address l1TokenNonRebasable_,
        address l1TokenRebasable_,
        address l2TokenNonRebasable_,
        address l2TokenRebasable_
    ) CrossDomainEnabled(messenger_) RebasableAndNonRebasableTokens(
        l1TokenNonRebasable_,
        l1TokenRebasable_,
        l2TokenNonRebasable_,
        l2TokenRebasable_
    ) {
        if (l2TokenBridge_ == address(0)) {
            revert ErrorZeroAddressL2Bridge();
        }
        L2_TOKEN_BRIDGE = l2TokenBridge_;
    }

    /// @inheritdoc IL1ERC20Bridge
    function l2TokenBridge() external view returns (address) {
        return L2_TOKEN_BRIDGE;
    }

    /// @inheritdoc IL1ERC20Bridge
    function depositERC20(
        address l1Token_,
        address l2Token_,
        uint256 amount_,
        uint32 l2Gas_,
        bytes calldata data_
    )
        external
        whenDepositsEnabled
        onlySupportedL1L2TokensPair(l1Token_, l2Token_)
    {
        if (Address.isContract(msg.sender)) {
            revert ErrorSenderNotEOA();
        }
        bytes memory encodedDepositData  = _encodeInputDepositData(data_);
        _depositERC20To(l1Token_, l2Token_, msg.sender, msg.sender, amount_, l2Gas_, encodedDepositData);
        emit ERC20DepositInitiated(l1Token_, l2Token_, msg.sender, msg.sender, amount_, encodedDepositData);
    }

    /// @inheritdoc IL1ERC20Bridge
    function depositERC20To(
        address l1Token_,
        address l2Token_,
        address to_,
        uint256 amount_,
        uint32 l2Gas_,
        bytes calldata data_
    )
        external
        whenDepositsEnabled
        onlyNonZeroAccount(to_)
        onlySupportedL1L2TokensPair(l1Token_, l2Token_)
    {
        bytes memory encodedDepositData  = _encodeInputDepositData(data_);
        _depositERC20To(l1Token_, l2Token_, msg.sender, to_, amount_, l2Gas_, encodedDepositData);
        emit ERC20DepositInitiated(l1Token_, l2Token_, msg.sender, to_, amount_, encodedDepositData);
    }

    /// @inheritdoc IL1ERC20Bridge
    function finalizeERC20Withdrawal(
        address l1Token_,
        address l2Token_,
        address from_,
        address to_,
        uint256 amount_,
        bytes calldata data_
    )
        external
        whenWithdrawalsEnabled
        onlyFromCrossDomainAccount(L2_TOKEN_BRIDGE)
        onlySupportedL1L2TokensPair(l1Token_, l2Token_)
    {
        uint256 withdrawnL1TokenAmount = (l1Token_ == L1_TOKEN_REBASABLE && amount_ != 0) ?
            IERC20Wrapper(L1_TOKEN_NON_REBASABLE).unwrap(amount_) :
            amount_;
        IERC20(l1Token_).safeTransfer(to_, withdrawnL1TokenAmount);
        emit ERC20WithdrawalFinalized(l1Token_, l2Token_, from_, to_, withdrawnL1TokenAmount, data_);
    }

    /// @notice Performs the logic for deposits by informing the L2 token bridge contract
    ///     of the deposit and calling safeTransferFrom to lock the L1 funds.
    /// @param l1Token_ Address of the L1 ERC20 we are depositing
    /// @param l2Token_ Address of the L1 respective L2 ERC20
    /// @param from_ Account to pull the deposit from on L1
    /// @param to_ Account to give the deposit to on L2
    /// @param amount_ Amount of the ERC20 to deposit.
    /// @param l2Gas_ Gas limit required to complete the deposit on L2.
    /// @param encodedDepositData_ a concatenation of packed token rate with L1 time and
    ///        optional data passed by external contract
    function _depositERC20To(
        address l1Token_,
        address l2Token_,
        address from_,
        address to_,
        uint256 amount_,
        uint32 l2Gas_,
        bytes memory encodedDepositData_
    ) internal {
        uint256 nonRebasableAmountToDeposit = _transferToBridge(l1Token_, from_, amount_);

        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Bridge.finalizeDeposit.selector,
            l1Token_, l2Token_, from_, to_, nonRebasableAmountToDeposit, encodedDepositData_
        );

        sendCrossDomainMessage(L2_TOKEN_BRIDGE, l2Gas_, message);
    }

    /// @notice Transfers tokens to the bridge and wraps if needed.
    /// @param l1Token_ Address of the L1 ERC20 we are depositing.
    /// @param from_ Account to pull the deposit from on L1.
    /// @param amount_ Amount of the ERC20 to deposit.
    /// @return Amount of non-rebasable token.
    function _transferToBridge(
        address l1Token_,
        address from_,
        uint256 amount_
    ) internal returns (uint256) {
        if (amount_ != 0) {
            IERC20(l1Token_).safeTransferFrom(from_, address(this), amount_);
            if (l1Token_ == L1_TOKEN_REBASABLE) {
                IERC20(l1Token_).safeIncreaseAllowance(L1_TOKEN_NON_REBASABLE, amount_);
                return IERC20Wrapper(L1_TOKEN_NON_REBASABLE).wrap(amount_);
            }
        }
        return amount_;
    }

    /// @dev Helper that simplifies calling encoding by DepositDataCodec.
    ///      Encodes token rate, it's L1 timestamp and optional data.
    /// @param data_ Optional data to forward to L2.
    /// @return encoded data in the 'wired' bytes form.
    function _encodeInputDepositData(bytes calldata data_) internal view returns (bytes memory)  {
        (uint256 rate, uint256 timestamp) = _tokenRate();
        return DepositDataCodec.encodeDepositData(DepositDataCodec.DepositData({
            rate: uint128(rate),
            timestamp: uint40(timestamp),
            data: data_
        }));
    }

    /// @notice required to abstact a way token rate is requested.
    function _tokenRate() virtual internal view returns (uint256 rate_, uint256 updateTimestamp_);

    error ErrorSenderNotEOA();
    error ErrorZeroAddressL2Bridge();
}

contract L1LidoTokensBridge is L1ERC20ExtendedTokensBridge, TokenRateAndUpdateTimestampProvider, Versioned {

    /// @param messenger_ L1 messenger address being used for cross-chain communications
    /// @param l2TokenBridge_ Address of the corresponding L2 bridge
    /// @param l1TokenNonRebasable_ Address of the bridged token in the L1 chain
    /// @param l1TokenRebasable_ Address of the bridged token in the L1 chain
    /// @param l2TokenNonRebasable_ Address of the token minted on the L2 chain when token bridged
    /// @param l2TokenRebasable_ Address of the token minted on the L2 chain when token bridged
    /// @param accountingOracle_ Address of the AccountingOracle instance to retrieve rate update timestamps
    constructor(
        address messenger_,
        address l2TokenBridge_,
        address l1TokenNonRebasable_,
        address l1TokenRebasable_,
        address l2TokenNonRebasable_,
        address l2TokenRebasable_,
        address accountingOracle_
    ) L1ERC20ExtendedTokensBridge(
        messenger_,
        l2TokenBridge_,
        l1TokenNonRebasable_,
        l1TokenRebasable_,
        l2TokenNonRebasable_,
        l2TokenRebasable_
    ) TokenRateAndUpdateTimestampProvider(
        l1TokenNonRebasable_,
        accountingOracle_
    ) {}

    /// @notice Initializes the contract from scratch.
    /// @param admin_ Address of the account to grant the DEFAULT_ADMIN_ROLE
    function initialize(address admin_) external {
        _initializeContractVersionTo(2);
        _initializeBridgingManager(admin_);
    }

    /// @notice A function to finalize upgrade to v2 (from v1).
    function finalizeUpgrade_v2() external {
        if (!_isBridgingManagerInitialized()) {
            revert ErrorBridgingManagerIsNotInitialized();
        }
        _initializeContractVersionTo(2);
    }

    function _tokenRate() override internal view returns (uint256 rate, uint256 updateTimestamp) {
        return _getTokenRateAndUpdateTimestamp();
    }
}