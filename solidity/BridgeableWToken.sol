// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract BridgableWToken is ERC20, ERC20Wrapper, Ownable, Pausable {
    uint8 private decimalUnits;
    mapping(address => bool) public signers;

    uint256 public currentlyBridged;

    struct FeeDetails {
        uint256 feePercentage;
        uint256 feeRatio;
        uint256 accruedFees;
        address dev_1;
        address dev_2;
    }

    FeeDetails public feeDetails;

    struct FeeDiscount {
        IERC20 token;
        uint256 discountedPercentage;
        uint256 balanceRequired;
    }

    FeeDiscount[] public feeDiscounts;

    event Bridge(address indexed recipient, uint256 amount);

    event Mint(address indexed recipient, uint256 amount);

    modifier onlySigner() {
        require(signers[msg.sender], "caller is not a signer");
        _;
    }

    constructor(
        IERC20 underlyingToken,
        string memory _name,
        string memory _symbol,
        uint8 decimalUnits_,
        address _owner
    ) ERC20(_name, _symbol) ERC20Wrapper(underlyingToken) Ownable(_owner) {
        decimalUnits = decimalUnits_;
        signers[_owner] = true;
        feeDetails = FeeDetails({
            feePercentage: 100,
            feeRatio: 10000,
            accruedFees: 0,
            dev_1: 0x6950f61e0A0119FAA4b1a78Da0c72b9f09938D8A,
            dev_2: 0x077adA2c6C51660aDf741c6D15680Fa4f9c2e895
        });

        feeDiscounts.push(
            FeeDiscount({
                token: IERC20(0xC5FDf3569af74f3B3e97E46A187a626352D2d508),
                discountedPercentage: 0,
                balanceRequired: 1000000000000000
            })
        );
    }

    //========== Wrapper ==========\\
    function wrap(uint256 amount) public {
        depositFor(msg.sender, amount);
    }

    function unwrap(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Not enough WToken balance");
        withdrawTo(msg.sender, amount);
    }

    //========== Bridge ==========\\
    function bridge(address _recipient, uint256 _amount) public whenNotPaused {
        if (balanceOf(msg.sender) >= _amount) {
            _burn(msg.sender, _amount);
        } else {
            wrap(_amount);
            _burn(msg.sender, _amount);
        }

        uint256 feePercentage = getFeePercentageForUser(msg.sender);
        uint256 feeRatio = feeDetails.feeRatio;

        uint256 _fee = (_amount * feePercentage) / feeRatio;
        uint256 _amountAfterFee = _amount - _fee;
        currentlyBridged += _amountAfterFee;
        feeDetails.accruedFees += _fee;
        emit Bridge(_recipient, _amountAfterFee);
    }

    function receiveBridge(
        address _recipient,
        uint256 _amount
    ) public onlySigner whenNotPaused {
        currentlyBridged -= _amount;
        _mint(_recipient, _amount);
        emit Mint(_recipient, _amount);
    }

    //========== Administrative ==========\\
    function isSetSigner(address _signer, bool _status) public onlyOwner {
        signers[_signer] = _status;
    }

    function togglePause() public onlySigner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    //========== Fees ==========\\
    function collectAccruedFees() public onlySigner {
        uint256 accruedFees = feeDetails.accruedFees;
        address dev_1 = feeDetails.dev_1;
        address dev_2 = feeDetails.dev_2;
        uint256 splitFees = accruedFees / 2;
        feeDetails.accruedFees = 0;
        _mint(dev_1, splitFees);
        _mint(dev_2, splitFees);
    }

    function setNewDevs(address _dev_1, address _dev_2) public onlyOwner {
        feeDetails.dev_1 = _dev_1;
        feeDetails.dev_2 = _dev_2;
    }

    function setFeePercentage(uint256 _feePercentage) public onlyOwner {
        feeDetails.feePercentage = _feePercentage;
    }

    function addNewFeeDiscount(
        address _token,
        uint256 _discountedPercentage,
        uint256 _balanceRequired
    ) public onlyOwner {
        feeDiscounts.push(
            FeeDiscount({
                token: IERC20(_token),
                discountedPercentage: _discountedPercentage,
                balanceRequired: _balanceRequired
            })
        );
    }

    function removeFeeDiscount(uint256 index) public onlyOwner {
        require(index < feeDiscounts.length, "Index out of bounds");
        feeDiscounts[index] = feeDiscounts[feeDiscounts.length - 1];
        feeDiscounts.pop();
    }

    function getFeePercentageForUser(
        address _user
    ) public view returns (uint256) {
        uint256 feePercentage = feeDetails.feePercentage;

        for (uint256 i = 0; i < feeDiscounts.length; i++) {
            FeeDiscount memory discount = feeDiscounts[i];
            if (discount.token.balanceOf(_user) >= discount.balanceRequired) {
                return discount.discountedPercentage;
            }
        }
        return feePercentage;
    }

    //========== Overrides ==========\\
    function decimals()
        public
        view
        override(ERC20Wrapper, ERC20)
        returns (uint8)
    {
        return decimalUnits;
    }
}
