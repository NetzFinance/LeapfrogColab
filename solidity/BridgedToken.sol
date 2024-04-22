// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract BridgedToken is ERC20Burnable, Ownable, Pausable {
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
        string memory name,
        string memory symbol,
        uint8 _decimals,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) {
        signers[_owner] = true;
        decimalUnits = _decimals;
        feeDetails = FeeDetails({
            feePercentage: 100,
            feeRatio: 10000,
            accruedFees: 0,
            dev_1: 0x6950f61e0A0119FAA4b1a78Da0c72b9f09938D8A,
            dev_2: 0x077adA2c6C51660aDf741c6D15680Fa4f9c2e895
        });

        feeDiscounts.push(
            FeeDiscount({
                token: IERC20(0xb30cd83bf39cf94af9d0fdcc9a5f4c0c60debf18),
                discountedPercentage: 0,
                balanceRequired: 5000000000000000
            })
        );

        feeDiscounts.push(
            FeeDiscount({
                token: IERC20(0x05e196d3b4ab1f2e9d6cc984f591764afed37d00),
                discountedPercentage: 0,
                balanceRequired: 10000000000000000000000000
            })
        );
    }

    //========== Bridge ==========\\
    function bridge(address _recipient, uint256 _amount) public whenNotPaused {
        require(balanceOf(msg.sender) >= _amount, "Not enough token balance");
        _burn(msg.sender, _amount);

        uint256 feePercentage = getFeePercentageForUser(msg.sender);
        uint256 feeRatio = feeDetails.feeRatio;
        uint256 _fee = (_amount * feePercentage) / feeRatio;
        uint256 _amountAfterFee = _amount - _fee;

        currentlyBridged -= _amountAfterFee;
        feeDetails.accruedFees += _fee;

        emit Bridge(_recipient, _amountAfterFee);
    }

    function receiveBridge(
        address _recipient,
        uint256 _amount
    ) public onlySigner whenNotPaused {
        currentlyBridged += _amount;
        _mint(_recipient, _amount);
        emit Mint(_recipient, _amount);
    }

    //========== Administrative ==========\\
    function isSetSigner(address _signer, bool _status) public onlySigner {
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
    function decimals() public view override(ERC20) returns (uint8) {
        return decimalUnits;
    }
}
